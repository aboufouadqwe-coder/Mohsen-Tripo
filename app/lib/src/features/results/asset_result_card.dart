import 'package:flutter/material.dart';

import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';

typedef ResultImagePreviewBuilder = Widget Function(
  BuildContext context,
  String url,
);

final class AssetResultCard extends StatelessWidget {
  const AssetResultCard({
    super.key,
    required this.entry,
    this.onGenerateModel,
    this.imagePreviewBuilder,
    this.modelGenerationBusy = false,
    this.activeModelAssetResultId,
  });

  final ResultHistoryEntry entry;
  final Future<void> Function(AssetResult asset)? onGenerateModel;
  final ResultImagePreviewBuilder? imagePreviewBuilder;
  final bool modelGenerationBusy;
  final String? activeModelAssetResultId;

  String _statusLabel(GenerationStatus status) {
    return switch (status) {
      GenerationStatus.queued => 'في قائمة الانتظار',
      GenerationStatus.running => 'جارٍ التوليد',
      GenerationStatus.success => 'مكتمل',
      GenerationStatus.failed => 'فشل',
      GenerationStatus.cancelled => 'أُلغي',
    };
  }

  String _title() {
    final part = entry.job.partKey;
    if (part != null && part.isNotEmpty) return part;

    return switch (entry.job.operation) {
      GenerationOperation.textToImage => 'صورة مرجعية',
      GenerationOperation.imageToImage => 'صورة مولدة',
      GenerationOperation.imageToModel => 'نموذج 3D',
    };
  }

  Widget _defaultPreview(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageAsset = entry.firstImageAsset;
    final signedImageUrl =
        imageAsset == null ? null : entry.signedUrlFor(imageAsset);
    final usableImage = entry.hasUsableAsset &&
            entry.job.operation != GenerationOperation.imageToModel
        ? imageAsset
        : null;
    final canGenerateModel = usableImage != null && onGenerateModel != null;
    final isActiveAsset = activeModelAssetResultId != null &&
        activeModelAssetResultId == imageAsset?.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(_statusLabel(entry.job.status)),
              ],
            ),
            if (signedImageUrl != null) ...[
              const SizedBox(height: 12),
              (imagePreviewBuilder ?? _defaultPreview)(
                context,
                signedImageUrl,
              ),
            ],
            if (entry.modelAsset != null) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.view_in_ar_outlined),
                  SizedBox(width: 8),
                  Text('نموذج GLB محفوظ'),
                ],
              ),
            ],
            if (entry.job.errorCode != null) ...[
              const SizedBox(height: 8),
              Text(
                'الخطأ: ' + entry.job.errorCode!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (canGenerateModel) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: modelGenerationBusy
                    ? null
                    : () async {
                        await onGenerateModel!(usableImage);
                      },
                icon: isActiveAsset
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.view_in_ar),
                label: Text(
                  isActiveAsset ? 'جارٍ إنشاء 3D' : 'تحويل إلى 3D',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
