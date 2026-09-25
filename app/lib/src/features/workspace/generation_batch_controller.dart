import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/analytics/analytics.dart';
import '../../data/supabase/generation_gateway.dart';
import '../../domain/generation/generation_job.dart';
import 'generation_state.dart';
import 'job_polling_service.dart';

final class GenerationPartRequest {
  const GenerationPartRequest({
    required this.key,
    required this.label,
    required this.prompt,
  });

  final String key;
  final String label;
  final String prompt;
}

final class GenerationBatchController extends ChangeNotifier {
  GenerationBatchController({
    required this.gateway,
    required this.pollingService,
    required this.projectId,
  });

  final GenerationGateway gateway;
  final JobPollingService pollingService;
  final String projectId;
  final Map<String, GenerationPartState> _state = {};
  bool _disposed = false;

  Map<String, GenerationPartState> get state =>
      Map<String, GenerationPartState>.unmodifiable(_state);

  bool get isBusy => _state.values.any((part) => part.isActive);

  void _capture(String event, Map<String, Object?> properties) {
    final analytics = AnalyticsBinding.maybeCurrent;
    if (analytics == null) return;
    unawaited(captureAnalyticsSafely(analytics, event, properties));
  }

  Future<void> generateAll({
    required Iterable<GenerationPartRequest> parts,
  }) async {
    final normalizedParts = <GenerationPartRequest>[];
    final seen = <String>{};

    for (final rawPart in parts) {
      final key = rawPart.key.trim();
      final label = rawPart.label.trim();
      final prompt = rawPart.prompt.trim();
      if (key.isEmpty || label.isEmpty || prompt.isEmpty || !seen.add(key)) continue;
      normalizedParts.add(
        GenerationPartRequest(key: key, label: label, prompt: prompt),
      );
    }

    for (final part in normalizedParts) {
      if (_disposed) return;

      final jobId = await _submitPart(part);
      if (jobId == null || _disposed) continue;

      // Keep Tripo image generation intentionally serialized. Each part first
      // uploads the private reference image to /v3/files, so launching many
      // parts together can hit provider upload/parallelism limits.
      await _pollPart(part.key, jobId);
    }
  }

  Future<void> generatePart(GenerationPartRequest part) async {
    if (_disposed ||
        part.key.trim().isEmpty ||
        part.label.trim().isEmpty ||
        part.prompt.trim().isEmpty) {
      return;
    }

    final jobId = await _submitPart(part);
    if (jobId == null || _disposed) return;
    await _pollPart(part.key, jobId);
  }

  Future<void> regeneratePart(GenerationPartRequest part) async {
    final normalized = part.key.trim();
    if (normalized.isEmpty || _disposed) return;

    _capture(
      AnalyticsEvents.partRegenerated,
      {'part_key': normalized},
    );

    final jobId = await _submitPart(part);
    if (jobId == null || _disposed) return;

    await _pollPart(normalized, jobId);
  }

  Future<void> resumeJobs(Iterable<GenerationJob> jobs) async {
    final active = <String, String>{};

    for (final job in jobs) {
      final partKey = job.partKey?.trim();
      if (partKey == null || partKey.isEmpty || job.isTerminal) continue;

      _state[partKey] = GenerationPartState.fromJob(
        job,
        submittedJobId: job.id,
        startedAt: job.createdAt,
      );
      active[partKey] = job.id;
    }
    _notify();

    await Future.wait(
      active.entries.map(
        (entry) => _pollPart(entry.key, entry.value),
      ),
      eagerError: false,
    );
  }

  Future<String?> _submitPart(GenerationPartRequest part) async {
    final partKey = part.key.trim();
    final startedAt = DateTime.now();
    _state[partKey] = GenerationPartState.submitting(
      partKey,
      startedAt: startedAt,
    );
    _notify();

    try {
      final jobId = await gateway.generateImagePart(
        projectId: projectId,
        partKey: partKey,
        partLabel: part.label.trim(),
        partPrompt: part.prompt.trim(),
      );
      if (_disposed) return null;

      _capture(
        AnalyticsEvents.generationStarted,
        {
          'operation': 'image_to_image',
          'part_key': partKey,
        },
      );

      _state[partKey] = GenerationPartState.queued(
        partKey,
        jobId,
        startedAt: startedAt,
      );
      _notify();
      return jobId;
    } catch (_) {
      if (_disposed) return null;
      _capture(
        AnalyticsEvents.generationFailed,
        {
          'operation': 'image_to_image',
          'part_key': partKey,
          'error_code': 'submission_failed',
        },
      );
      _state[partKey] = GenerationPartState.failedSubmission(
        partKey,
        startedAt: startedAt,
      );
      _notify();
      return null;
    }
  }

  Future<void> _pollPart(String partKey, String jobId) async {
    try {
      final initialStartedAt = _state[partKey]?.startedAt;
      final job = await pollingService.pollUntilTerminalWithUpdates(
        jobId,
        (updatedJob) {
          if (_disposed) return;
          _state[partKey] = GenerationPartState.fromJob(
            updatedJob,
            submittedJobId: jobId,
            startedAt: initialStartedAt,
          );
          _notify();
        },
      );
      if (_disposed) return;

      if (job.status == GenerationStatus.success) {
        _capture(
          AnalyticsEvents.generationCompleted,
          {
            'operation': 'image_to_image',
            'part_key': partKey,
          },
        );
      } else {
        _capture(
          AnalyticsEvents.generationFailed,
          {
            'operation': 'image_to_image',
            'part_key': partKey,
            'error_code': job.errorCode ?? 'provider_failed',
          },
        );
      }

      _state[partKey] = GenerationPartState.fromJob(
        job,
        submittedJobId: jobId,
        startedAt: initialStartedAt,
      );
      _notify();
    } on JobPollingCancelled {
      return;
    } catch (_) {
      if (_disposed) return;

      _capture(
        AnalyticsEvents.generationFailed,
        {
          'operation': 'image_to_image',
          'part_key': partKey,
          'error_code': 'polling_failed',
        },
      );

      _state[partKey] = GenerationPartState(
        partKey: partKey,
        phase: GenerationPartPhase.failed,
        jobId: jobId,
        progress: 1,
        errorCode: 'polling_failed',
        errorMessage: 'Generation job could not be refreshed.',
        startedAt: _state[partKey]?.startedAt,
        finishedAt: DateTime.now(),
      );
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pollingService.dispose();
    super.dispose();
  }
}
