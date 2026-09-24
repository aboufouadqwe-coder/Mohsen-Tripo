enum GenerationOperation {
  textToImage,
  imageToImage,
  imageToModel,
}

enum GenerationStatus {
  queued,
  running,
  success,
  failed,
  cancelled,
}

final class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.projectId,
    required this.provider,
    required this.operation,
    required this.status,
    this.partKey,
    this.providerTaskId,
    this.progress = 0,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String projectId;
  final String provider;
  final GenerationOperation operation;
  final GenerationStatus status;
  final String? partKey;
  final String? providerTaskId;
  final double progress;
  final String? errorCode;
  final String? errorMessage;

  bool get isTerminal => switch (status) {
        GenerationStatus.success ||
        GenerationStatus.failed ||
        GenerationStatus.cancelled =>
          true,
        GenerationStatus.queued || GenerationStatus.running => false,
      };
}
