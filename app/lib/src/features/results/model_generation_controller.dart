import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/analytics/analytics.dart';
import '../../data/supabase/generation_gateway.dart';
import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';
import '../../domain/generation/model_generation_settings.dart';

typedef ModelJobPoller = Future<GenerationJob> Function(String jobId);
typedef ModelJobProgressPoller = Future<GenerationJob> Function(
  String jobId,
  void Function(GenerationJob job) onUpdate,
);

final class ModelGenerationController extends ChangeNotifier {
  ModelGenerationController({
    required this.gateway,
    required this.pollUntilTerminal,
    this.pollUntilTerminalWithUpdates,
  });

  final GenerationGateway gateway;
  final ModelJobPoller pollUntilTerminal;
  final ModelJobProgressPoller? pollUntilTerminalWithUpdates;

  bool isBusy = false;
  String? activeAssetResultId;
  GenerationJob? job;
  String? errorCode;
  bool _disposed = false;

  bool canGenerateFrom(AssetResult asset) => asset.isImage && !isBusy;

  void _capture(String event, Map<String, Object?> properties) {
    final analytics = AnalyticsBinding.maybeCurrent;
    if (analytics == null) return;
    unawaited(captureAnalyticsSafely(analytics, event, properties));
  }

  Future<void> generateFromImage(
    AssetResult asset, {
    ModelGenerationSettings settings = const ModelGenerationSettings(),
  }) async {
    if (_disposed || isBusy) return;

    if (!asset.isImage) {
      errorCode = 'image_required';
      _notify();
      return;
    }

    isBusy = true;
    activeAssetResultId = asset.id;
    errorCode = null;
    job = null;
    _notify();

    _capture(
      AnalyticsEvents.modelGenerationStarted,
      {'source_mime_type': asset.mimeType},
    );

    try {
      final jobId = await gateway.generateModel(
        asset.id,
        settings: settings,
      );
      if (_disposed) return;

      job = GenerationJob(
        id: jobId,
        projectId: asset.projectId,
        provider: 'tripo',
        operation: GenerationOperation.imageToModel,
        status: GenerationStatus.queued,
        partKey: asset.partKey,
        progress: 0,
      );
      _notify();

      await _pollModelJob(jobId);
    } catch (_) {
      if (_disposed) return;
      errorCode = 'model_generation_failed';
      _capture(
        AnalyticsEvents.modelGenerationFailed,
        const {'error_code': 'client_request_failed'},
      );
      _notify();
    } finally {
      _finishBusyState();
    }
  }

  Future<void> resumeJob(GenerationJob activeJob) async {
    if (_disposed ||
        isBusy ||
        activeJob.isTerminal ||
        activeJob.operation != GenerationOperation.imageToModel) {
      return;
    }

    isBusy = true;
    activeAssetResultId = null;
    errorCode = null;
    job = activeJob;
    _notify();

    try {
      await _pollModelJob(activeJob.id);
    } catch (_) {
      if (_disposed) return;
      errorCode = 'model_generation_failed';
      _capture(
        AnalyticsEvents.modelGenerationFailed,
        const {'error_code': 'resume_failed'},
      );
      _notify();
    } finally {
      _finishBusyState();
    }
  }

  Future<void> _pollModelJob(String jobId) async {
    final progressPoller = pollUntilTerminalWithUpdates;
    final terminal = progressPoller == null
        ? await pollUntilTerminal(jobId)
        : await progressPoller(
            jobId,
            (updatedJob) {
              if (_disposed) return;
              job = updatedJob;
              _notify();
            },
          );
    if (_disposed) return;

    job = terminal;
    if (terminal.status == GenerationStatus.success) {
      errorCode = null;
      _capture(
        AnalyticsEvents.modelGenerationCompleted,
        {
          'output_mime_type': terminal.mimeType ?? 'model/gltf-binary',
        },
      );
    } else {
      errorCode = terminal.errorCode ?? 'model_generation_failed';
      _capture(
        AnalyticsEvents.modelGenerationFailed,
        {'error_code': errorCode!},
      );
    }
    _notify();
  }

  void _finishBusyState() {
    if (_disposed) return;
    isBusy = false;
    activeAssetResultId = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
