import '../generation/generation_job.dart';

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
    this.createdAt,
  });

  final String id;
  final String projectId;
  final String generationJobId;
  final String? partKey;
  final String storagePath;
  final String mimeType;
  final int? width;
  final int? height;
  final DateTime? createdAt;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  bool get isGlb {
    final normalized = mimeType.toLowerCase();
    return normalized == 'model/gltf-binary' ||
        storagePath.toLowerCase().endsWith('.glb');
  }

  bool get isFbx {
    final path = storagePath.toLowerCase();
    return path.endsWith('.fbx') ||
        mimeType.toLowerCase().contains('fbx');
  }

  bool get isModel {
    final normalized = mimeType.toLowerCase();
    return isGlb ||
        isFbx ||
        normalized.startsWith('model/') ||
        normalized == 'application/octet-stream' ||
        normalized == 'application/x-binary';
  }
}

final class ResultHistoryEntry {
  const ResultHistoryEntry({
    required this.job,
    required this.createdAt,
    this.assets = const [],
    this.signedUrlsByAssetId = const {},
  });

  final GenerationJob job;
  final DateTime createdAt;
  final List<AssetResult> assets;
  final Map<String, String> signedUrlsByAssetId;

  bool get hasUsableAsset =>
      job.status == GenerationStatus.success && assets.isNotEmpty;

  AssetResult? get firstImageAsset {
    for (final asset in assets) {
      if (asset.isImage) return asset;
    }
    return null;
  }

  AssetResult? get modelAsset {
    for (final asset in assets) {
      if (asset.isModel) return asset;
    }
    return null;
  }

  String? signedUrlFor(AssetResult asset) => signedUrlsByAssetId[asset.id];
}
