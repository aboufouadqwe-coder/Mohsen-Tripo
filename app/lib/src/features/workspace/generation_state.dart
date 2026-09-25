import '../../domain/generation/generation_job.dart';

enum GenerationPartPhase {
  submitting,
  queued,
  running,
  success,
  failed,
  cancelled,
}

final class GenerationPartState {
  const GenerationPartState({
    required this.partKey,
    required this.phase,
    this.jobId,
    this.progress = 0,
    this.assetResultId,
    this.storagePath,
    this.mimeType,
    this.errorCode,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
  });

  final String partKey;
  final GenerationPartPhase phase;
  final String? jobId;
  final double progress;
  final String? assetResultId;
  final String? storagePath;
  final String? mimeType;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  Duration? get elapsed {
    final start = startedAt;
    if (start == null) return null;
    final end = finishedAt ?? DateTime.now();
    if (end.isBefore(start)) return null;
    return end.difference(start);
  }

  bool get isSuccess => phase == GenerationPartPhase.success;

  bool get isFailure =>
      phase == GenerationPartPhase.failed ||
      phase == GenerationPartPhase.cancelled;

  bool get isActive =>
      phase == GenerationPartPhase.submitting ||
      phase == GenerationPartPhase.queued ||
      phase == GenerationPartPhase.running;

  factory GenerationPartState.submitting(
    String partKey, {
    DateTime? startedAt,
  }) {
    return GenerationPartState(
      partKey: partKey,
      phase: GenerationPartPhase.submitting,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  factory GenerationPartState.queued(
    String partKey,
    String jobId, {
    DateTime? startedAt,
  }) {
    return GenerationPartState(
      partKey: partKey,
      phase: GenerationPartPhase.queued,
      jobId: jobId,
      startedAt: startedAt,
    );
  }

  factory GenerationPartState.failedSubmission(
    String partKey, {
    String errorCode = 'submission_failed',
    DateTime? startedAt,
  }) {
    return GenerationPartState(
      partKey: partKey,
      phase: GenerationPartPhase.failed,
      progress: 1,
      errorCode: errorCode,
      errorMessage: 'Generation job could not be submitted.',
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
  }

  factory GenerationPartState.fromJob(
    GenerationJob job, {
    String? submittedJobId,
    DateTime? startedAt,
  }) {
    final partKey = job.partKey;
    if (partKey == null || partKey.trim().isEmpty) {
      throw ArgumentError('Part generation jobs require partKey.');
    }

    return GenerationPartState(
      partKey: partKey,
      phase: switch (job.status) {
        GenerationStatus.queued => GenerationPartPhase.queued,
        GenerationStatus.running => GenerationPartPhase.running,
        GenerationStatus.success => GenerationPartPhase.success,
        GenerationStatus.failed => GenerationPartPhase.failed,
        GenerationStatus.cancelled => GenerationPartPhase.cancelled,
      },
      jobId: submittedJobId ?? job.id,
      progress: job.progress,
      assetResultId: job.assetResultId,
      storagePath: job.storagePath,
      mimeType: job.mimeType,
      errorCode: job.errorCode,
      errorMessage: job.errorMessage,
      startedAt: job.createdAt ?? startedAt,
      finishedAt: job.completedAt ??
          (job.isTerminal ? DateTime.now() : null),
    );
  }
}
