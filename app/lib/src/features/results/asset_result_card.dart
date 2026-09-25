import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';

typedef ResultImagePreviewBuilder = Widget Function(
  BuildContext context,
  String url,
);

typedef ResultImageDownload = Future<void> Function(
  AssetResult asset,
  String signedUrl,
);

typedef ResultModelPreviewBuilder = Widget Function(
  BuildContext context,
  String url,
);

typedef ResultModelDownload = Future<void> Function(
  AssetResult asset,
  String signedUrl,
);

final class AssetResultCard extends StatelessWidget {
  const AssetResultCard({
    super.key,
    required this.entry,
    this.onGenerateModel,
    this.imagePreviewBuilder,
    this.modelPreviewBuilder,
    this.onDownloadImage,
    this.onDownloadModel,
    this.modelGenerationBusy = false,
    this.activeModelAssetResultId,
  });

  final ResultHistoryEntry entry;
  final Future<void> Function(AssetResult asset)? onGenerateModel;
  final ResultImagePreviewBuilder? imagePreviewBuilder;
  final ResultModelPreviewBuilder? modelPreviewBuilder;
  final ResultImageDownload? onDownloadImage;
  final ResultModelDownload? onDownloadModel;
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

  Widget _defaultModelPreview(BuildContext context, String url) {
    return _LazyModelPreview(url: url);
  }

  @override
  Widget build(BuildContext context) {
    final imageAsset = entry.firstImageAsset;
    final signedImageUrl =
        imageAsset == null ? null : entry.signedUrlFor(imageAsset);
    final modelAsset = entry.modelAsset;
    final signedModelUrl =
        modelAsset == null ? null : entry.signedUrlFor(modelAsset);
    final usableImage = entry.hasUsableAsset &&
            entry.job.operation != GenerationOperation.imageToModel
        ? imageAsset
        : null;
    final canGenerateModel = usableImage != null && onGenerateModel != null;
    final canDownloadImage =
        imageAsset != null && signedImageUrl != null && onDownloadImage != null;
    final canDownloadModel =
        modelAsset != null && signedModelUrl != null && onDownloadModel != null;
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
            if (canDownloadImage) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await onDownloadImage!(imageAsset, signedImageUrl);
                },
                icon: const Icon(Icons.download),
                label: const Text('تنزيل الصورة'),
              ),
            ],
            if (modelAsset != null) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.view_in_ar_outlined),
                  SizedBox(width: 8),
                  Text('نموذج 3D'),
                ],
              ),
              if (signedModelUrl != null) ...[
                const SizedBox(height: 10),
                if (modelAsset.isGlb) ...[
                  (modelPreviewBuilder ?? _defaultModelPreview)(
                    context,
                    signedModelUrl,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اسحب لتدوير المجسم، واستخدم إصبعين للتكبير والتصغير.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else if (modelAsset.isFbx) ...[
                  const Text(
                    'هذا المجسم بصيغة FBX (Quad). يمكن تنزيله، لكن العارض الداخلي يدعم GLB فقط.',
                  ),
                ],
                if (canDownloadModel) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await onDownloadModel!(modelAsset, signedModelUrl);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('تنزيل المجسم'),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 8),
                const Text('تعذر تحميل رابط عرض المجسم.'),
              ],
            ],
            if (entry.job.errorCode != null) ...[
              const SizedBox(height: 8),
              Text(
                'الخطأ: ${entry.job.errorCode}',
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


final class _LazyModelPreview extends StatefulWidget {
  const _LazyModelPreview({
    required this.url,
  });

  final String url;

  @override
  State<_LazyModelPreview> createState() => _LazyModelPreviewState();
}

final class _LazyModelPreviewState extends State<_LazyModelPreview> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return FilledButton.tonalIcon(
        onPressed: () {
          setState(() => _visible = true);
        },
        icon: const Icon(Icons.view_in_ar),
        label: const Text('عرض المجسم'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 360,
            child: ModelViewer(
              src: widget.url,
              alt: 'نموذج 3D مولد',
              ar: false,
              autoRotate: false,
              cameraControls: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() => _visible = false);
          },
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Text('إخفاء المجسم'),
        ),
      ],
    );
  }
}
