import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/results_repository.dart';
import 'package:mohsen_tripo/src/domain/assets/asset_result.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/features/results/results_gallery.dart';

GenerationJob imageJob({
  required String id,
  required GenerationStatus status,
  String? errorCode,
}) {
  return GenerationJob(
    id: id,
    projectId: 'project-1',
    provider: 'tripo',
    operation: GenerationOperation.imageToImage,
    status: status,
    partKey: 'head',
    progress: 1,
    errorCode: errorCode,
  );
}

AssetResult imageAsset(String id, String jobId) {
  return AssetResult(
    id: id,
    projectId: 'project-1',
    generationJobId: jobId,
    partKey: 'head',
    storagePath: 'user-1/project-1/$id.png',
    mimeType: 'image/png',
  );
}

final class FakeResultsRepository implements ResultsRepository {
  FakeResultsRepository(this.entries);

  final List<ResultHistoryEntry> entries;
  int calls = 0;

  @override
  Future<List<ResultHistoryEntry>> listHistory(String projectId) async {
    calls += 1;
    return entries;
  }
}

void main() {
  testWidgets('successful persisted image exposes image-to-3D action',
      (tester) async {
    final asset = imageAsset('asset-1', 'job-1');
    final repository = FakeResultsRepository([
      ResultHistoryEntry(
        job: imageJob(id: 'job-1', status: GenerationStatus.success),
        assets: [asset],
        signedUrlsByAssetId: const {
          'asset-1': 'https://signed.test/asset-1.png',
        },
        createdAt: DateTime.utc(2026, 9, 25, 10),
      ),
    ]);
    String? selectedAssetId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsGallery(
            projectId: 'project-1',
            repository: repository,
            onGenerateModel: (selected) async {
              selectedAssetId = selected.id;
            },
            imagePreviewBuilder: (context, url) => Text('preview:$url'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('preview:https://signed.test/asset-1.png'),
      findsOneWidget,
    );
    expect(find.text('تحويل إلى 3D'), findsOneWidget);
    expect(find.text('تنزيل الصورة'), findsNothing);

    await tester.tap(find.text('تحويل إلى 3D'));
    await tester.pump();

    expect(selectedAssetId, 'asset-1');
  });

  testWidgets('failed persistence job shows failure without usable asset action',
      (tester) async {
    final repository = FakeResultsRepository([
      ResultHistoryEntry(
        job: imageJob(
          id: 'job-failed',
          status: GenerationStatus.failed,
          errorCode: 'persistence_failed',
        ),
        assets: const [],
        signedUrlsByAssetId: const {},
        createdAt: DateTime.utc(2026, 9, 25, 11),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsGallery(
            projectId: 'project-1',
            repository: repository,
            onGenerateModel: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('persistence_failed'), findsOneWidget);
    expect(find.text('تحويل إلى 3D'), findsNothing);
  });

  testWidgets('regenerations remain as separate history entries',
      (tester) async {
    final newest = imageAsset('asset-new', 'job-new');
    final older = imageAsset('asset-old', 'job-old');
    final repository = FakeResultsRepository([
      ResultHistoryEntry(
        job: imageJob(id: 'job-new', status: GenerationStatus.success),
        assets: [newest],
        signedUrlsByAssetId: const {},
        createdAt: DateTime.utc(2026, 9, 25, 12),
      ),
      ResultHistoryEntry(
        job: imageJob(id: 'job-old', status: GenerationStatus.success),
        assets: [older],
        signedUrlsByAssetId: const {},
        createdAt: DateTime.utc(2026, 9, 25, 10),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsGallery(
            projectId: 'project-1',
            repository: repository,
            onGenerateModel: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('result-job-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-job-old')), findsOneWidget);
  });

  testWidgets('persisted image exposes explicit download action',
      (tester) async {
    final asset = imageAsset('asset-download', 'job-download');
    final repository = FakeResultsRepository([
      ResultHistoryEntry(
        job: imageJob(id: 'job-download', status: GenerationStatus.success),
        assets: [asset],
        signedUrlsByAssetId: const {
          'asset-download': 'https://signed.test/download.png',
        },
        createdAt: DateTime.utc(2026, 9, 25, 13),
      ),
    ]);
    String? downloadedAssetId;
    String? downloadedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsGallery(
            projectId: 'project-1',
            repository: repository,
            onDownloadImage: (selected, url) async {
              downloadedAssetId = selected.id;
              downloadedUrl = url;
            },
            imagePreviewBuilder: (context, url) => Text('preview:$url'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تنزيل الصورة'), findsOneWidget);
    await tester.tap(find.text('تنزيل الصورة'));
    await tester.pump();

    expect(downloadedAssetId, 'asset-download');
    expect(downloadedUrl, 'https://signed.test/download.png');
  });

}
