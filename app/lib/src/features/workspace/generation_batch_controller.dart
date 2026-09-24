import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/analytics/analytics.dart';
import '../../data/supabase/generation_gateway.dart';
import '../../domain/generation/generation_job.dart';
import 'generation_state.dart';
import 'job_polling_service.dart';

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
    required Iterable<String> parts,
  }) async {
    final normalizedParts = <String>[];
    final seen = <String>{};

    for (final rawPart in parts) {
      final part = rawPart.trim();
      if (part.isEmpty || !seen.add(part)) continue;
      normalizedParts.add(part);
    }

    final submitted = <String, String>{};
    for (final partKey in normalizedParts) {
      if (_disposed) return;
      final jobId = await _submitPart(partKey);
      if (jobId != null) submitted[partKey] = jobId;
    }

    await Future.wait(
      submitted.entries.map(
        (entry) => _pollPart(entry.key, entry.value),
      ),
      eagerError: false,
    );
  }

  Future<void> regeneratePart(String partKey) async {
    final normalized = partKey.trim();
    if (normalized.isEmpty || _disposed) return;

    _capture(
      AnalyticsEvents.partRegenerated,
      {'part_key': normalized},
    );

    final jobId = await _submitPart(normalized);
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

  Future<String?> _submitPart(String partKey) async {
    _state[partKey] = GenerationPartState.submitting(partKey);
    _notify();

    try {
      final jobId = await gateway.generateImagePart(
        projectId: projectId,
        partKey: partKey,
      );
      if (_disposed) return null;

      _capture(
        AnalyticsEvents.generationStarted,
        {
          'operation': 'image_to_image',
          'part_key': partKey,
        },
      );

      _state[partKey] = GenerationPartState.queued(partKey, jobId);
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
      _state[partKey] = GenerationPartState.failedSubmission(partKey);
      _notify();
      return null;
    }
  }

  Future<void> _pollPart(String partKey, String jobId) async {
    try {
      final job = await pollingService.pollUntilTerminal(jobId);
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
