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

abstract interface class FunctionInvoker {
  Future<Map<String, Object?>> invoke(
    String functionName,
    Map<String, Object?> body,
  );
}

final class DefaultGenerationGateway implements GenerationGateway {
  const DefaultGenerationGateway(this._invoker);

  final FunctionInvoker _invoker;

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
      return _jobFromResponse(response);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.function();
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

  GenerationJob _jobFromResponse(Map<String, Object?> response) {
    final id = response['job_id'];
    final projectId = response['project_id'];
    final provider = response['provider'];
    final operation = response['operation'];
    final status = response['status'];
    final progress = response['progress'];
    final partKey = response['part_key'];
    final providerTaskId = response['provider_task_id'];

    if (id is! String ||
        projectId is! String ||
        provider is! String ||
        operation is! String ||
        status is! String ||
        progress is! num ||
        (partKey != null && partKey is! String) ||
        (providerTaskId != null && providerTaskId is! String)) {
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
      errorCode: response['error_code'] as String?,
      errorMessage: response['error_message'] as String?,
    );
  }
}
