import '../../core/errors/app_failure.dart';
import '../../domain/generation/generation_job.dart';

abstract interface class GenerationGateway {
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  });

  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? customInstructions,
  });

  Future<GenerationJob> refreshJob(String jobId);

  Future<String> generateModel(String assetResultId);
}

abstract interface class ActiveGenerationJobsGateway {
  Future<List<GenerationJob>> listActiveJobs(String projectId);
}

abstract interface class GenerationJobDataSource {
  Future<List<Map<String, Object?>>> listActiveJobs(String projectId);
}

abstract interface class FunctionInvoker {
  Future<Map<String, Object?>> invoke(
    String functionName,
    Map<String, Object?> body,
  );
}

final class DefaultGenerationGateway
    implements GenerationGateway, ActiveGenerationJobsGateway {
  const DefaultGenerationGateway(
    this._invoker, {
    this.jobDataSource,
  });

  final FunctionInvoker _invoker;
  final GenerationJobDataSource? jobDataSource;

  @override
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  }) async {
    return _invokeForJobId(
      'generate-source-image',
      {
        'project_id': projectId,
        'prompt': prompt,
      },
    );
  }

  @override
  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? customInstructions,
  }) async {
    final body = <String, Object?>{
      'project_id': projectId,
      'part_key': partKey,
    };
    if (customInstructions != null) {
      body['custom_instructions'] = customInstructions;
    }

    return _invokeForJobId('generate-image-part', body);
  }

  @override
  Future<String> generateModel(String assetResultId) {
    return _invokeForJobId(
      'generate-model',
      {'asset_result_id': assetResultId},
    );
  }

  @override
  Future<GenerationJob> refreshJob(String jobId) async {
    try {
      final response = await _invoker.invoke(
        'refresh-generation-job',
        {'job_id': jobId},
      );
      return _jobFromFunctionResponse(response);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.function();
    }
  }

  @override
  Future<List<GenerationJob>> listActiveJobs(String projectId) async {
    final source = jobDataSource;
    if (source == null) return const [];

    try {
      final rows = await source.listActiveJobs(projectId);
      return rows.map(_jobFromDatabaseRow).toList(growable: false);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  Future<String> _invokeForJobId(
    String functionName,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _invoker.invoke(functionName, body);
      final jobId = response['job_id'];
      if (jobId is! String || jobId.trim().isEmpty) {
        throw AppFailure.function();
      }
      return jobId;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.function();
    }
  }

  GenerationJob _jobFromFunctionResponse(Map<String, Object?> response) {
    return _jobFromFields(
      id: response['job_id'],
      projectId: response['project_id'],
      provider: response['provider'],
      operation: response['operation'],
      status: response['status'],
      progress: response['progress'],
      partKey: response['part_key'],
      providerTaskId: response['provider_task_id'],
      assetResultId: response['asset_result_id'],
      storagePath: response['storage_path'],
      mimeType: response['mime_type'],
      errorCode: response['error_code'],
      errorMessage: response['error_message'],
    );
  }

  GenerationJob _jobFromDatabaseRow(Map<String, Object?> row) {
    return _jobFromFields(
      id: row['id'],
      projectId: row['project_id'],
      provider: row['provider'],
      operation: row['operation'],
      status: row['status'],
      progress: row['progress'],
      partKey: row['part_key'],
      providerTaskId: row['provider_task_id'],
      errorCode: row['error_code'],
      errorMessage: row['error_message'],
    );
  }

  GenerationJob _jobFromFields({
    required Object? id,
    required Object? projectId,
    required Object? provider,
    required Object? operation,
    required Object? status,
    required Object? progress,
    Object? partKey,
    Object? providerTaskId,
    Object? assetResultId,
    Object? storagePath,
    Object? mimeType,
    Object? errorCode,
    Object? errorMessage,
  }) {
    if (id is! String ||
        projectId is! String ||
        provider is! String ||
        operation is! String ||
        status is! String ||
        progress is! num ||
        (partKey != null && partKey is! String) ||
        (providerTaskId != null && providerTaskId is! String) ||
        (assetResultId != null && assetResultId is! String) ||
        (storagePath != null && storagePath is! String) ||
        (mimeType != null && mimeType is! String) ||
        (errorCode != null && errorCode is! String) ||
        (errorMessage != null && errorMessage is! String)) {
      throw AppFailure.function();
    }

    return GenerationJob(
      id: id,
      projectId: projectId,
      provider: provider,
      operation: switch (operation) {
        'text_to_image' => GenerationOperation.textToImage,
        'image_to_image' => GenerationOperation.imageToImage,
        'image_to_model' => GenerationOperation.imageToModel,
        _ => throw AppFailure.function(),
      },
      status: switch (status) {
        'queued' => GenerationStatus.queued,
        'running' => GenerationStatus.running,
        'success' => GenerationStatus.success,
        'failed' => GenerationStatus.failed,
        'cancelled' => GenerationStatus.cancelled,
        _ => throw AppFailure.function(),
      },
      partKey: partKey as String?,
      providerTaskId: providerTaskId as String?,
      progress: progress.toDouble(),
      errorCode: errorCode as String?,
      errorMessage: errorMessage as String?,
      assetResultId: assetResultId as String?,
      storagePath: storagePath as String?,
      mimeType: mimeType as String?,
    );
  }
}
