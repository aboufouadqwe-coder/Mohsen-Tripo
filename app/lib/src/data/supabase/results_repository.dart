import '../../core/errors/app_failure.dart';
import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';

abstract interface class ResultsRepository {
  Future<List<ResultHistoryEntry>> listHistory(String projectId);
}

abstract interface class ResultsDataSource {
  Future<List<Map<String, Object?>>> listHistoryRows(String projectId);

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required int expiresIn,
  });
}

final class DefaultResultsRepository implements ResultsRepository {
  const DefaultResultsRepository({
    required this.dataSource,
  });

  final ResultsDataSource dataSource;

  @override
  Future<List<ResultHistoryEntry>> listHistory(String projectId) async {
    if (projectId.trim().isEmpty) {
      throw AppFailure.validation('Project id is required.');
    }

    try {
      final rows = await dataSource.listHistoryRows(projectId.trim());
      final entries = <ResultHistoryEntry>[];

      for (final row in rows) {
        final job = _jobFromRow(row);
        final assets = _assetsFromRow(row);
        final signedUrls = <String, String>{};

        for (final asset in assets) {
          try {
            signedUrls[asset.id] = await dataSource.createSignedUrl(
              bucket: asset.isImage ? 'generated-images' : 'generated-models',
              path: asset.storagePath,
              expiresIn: 300,
            );
          } catch (_) {
            // Keep history visible even when a temporary URL cannot be signed.
          }
        }

        entries.add(
          ResultHistoryEntry(
            job: job,
            assets: assets,
            signedUrlsByAssetId: signedUrls,
            createdAt: _requiredDate(row['created_at']),
          ),
        );
      }

      entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return entries;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  GenerationJob _jobFromRow(Map<String, Object?> row) {
    final id = row['id'];
    final projectId = row['project_id'];
    final provider = row['provider'];
    final operation = row['operation'];
    final status = row['status'];
    final progress = row['progress'];
    final partKey = row['part_key'];
    final providerTaskId = row['provider_task_id'];
    final errorCode = row['error_code'];
    final errorMessage = row['error_message'];

    if (id is! String ||
        projectId is! String ||
        provider is! String ||
        operation is! String ||
        status is! String ||
        progress is! num ||
        (partKey != null && partKey is! String) ||
        (providerTaskId != null && providerTaskId is! String) ||
        (errorCode != null && errorCode is! String) ||
        (errorMessage != null && errorMessage is! String)) {
      throw AppFailure.data();
    }

    return GenerationJob(
      id: id,
      projectId: projectId,
      provider: provider,
      operation: switch (operation) {
        'text_to_image' => GenerationOperation.textToImage,
        'image_to_image' => GenerationOperation.imageToImage,
        'image_to_model' => GenerationOperation.imageToModel,
        _ => throw AppFailure.data(),
      },
      status: switch (status) {
        'queued' => GenerationStatus.queued,
        'running' => GenerationStatus.running,
        'success' => GenerationStatus.success,
        'failed' => GenerationStatus.failed,
        'cancelled' => GenerationStatus.cancelled,
        _ => throw AppFailure.data(),
      },
      partKey: partKey as String?,
      providerTaskId: providerTaskId as String?,
      progress: progress.toDouble(),
      errorCode: errorCode as String?,
      errorMessage: errorMessage as String?,
    );
  }

  List<AssetResult> _assetsFromRow(Map<String, Object?> row) {
    final rawAssets = row['asset_results'];
    if (rawAssets == null) return const [];
    if (rawAssets is! List) throw AppFailure.data();

    final assets = <AssetResult>[];
    for (final raw in rawAssets) {
      if (raw is! Map) throw AppFailure.data();
      final asset = Map<String, Object?>.from(
        raw.cast<String, Object?>(),
      );

      final id = asset['id'];
      final projectId = asset['project_id'];
      final generationJobId = asset['generation_job_id'];
      final partKey = asset['part_key'];
      final storagePath = asset['storage_path'];
      final mimeType = asset['mime_type'];
      final width = asset['width'];
      final height = asset['height'];

      if (id is! String ||
          projectId is! String ||
          generationJobId is! String ||
          storagePath is! String ||
          mimeType is! String ||
          (partKey != null && partKey is! String) ||
          (width != null && width is! int) ||
          (height != null && height is! int)) {
        throw AppFailure.data();
      }

      assets.add(
        AssetResult(
          id: id,
          projectId: projectId,
          generationJobId: generationJobId,
          partKey: partKey as String?,
          storagePath: storagePath,
          mimeType: mimeType,
          width: width as int?,
          height: height as int?,
          createdAt: _optionalDate(asset['created_at']),
        ),
      );
    }

    return assets;
  }

  DateTime _requiredDate(Object? value) {
    final parsed = _optionalDate(value);
    if (parsed == null) throw AppFailure.data();
    return parsed;
  }

  DateTime? _optionalDate(Object? value) {
    if (value == null) return null;
    if (value is! String) throw AppFailure.data();
    return DateTime.tryParse(value);
  }
}
