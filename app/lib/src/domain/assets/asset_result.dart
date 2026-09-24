final class AssetResult {
  const AssetResult({
    required this.id,
    required this.projectId,
    required this.generationJobId,
    required this.storagePath,
    required this.mimeType,
    this.partKey,
    this.width,
    this.height,
  });

  final String id;
  final String projectId;
  final String generationJobId;
  final String? partKey;
  final String storagePath;
  final String mimeType;
  final int? width;
  final int? height;
}
