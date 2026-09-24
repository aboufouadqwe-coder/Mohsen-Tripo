import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/assets/asset_result.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/features/results/model_generation_controller.dart';

final class FakeModelGateway implements GenerationGateway {
  int modelCalls = 0;
  String? lastAssetResultId;

  @override
  Future<String> generateModel(String assetResultId) async {
    modelCalls += 1;
    lastAssetResultId = assetResultId;
    return 'model-job-$modelCalls';
  }

  @override
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? customInstructions,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<GenerationJob> refreshJob(String jobId) {
    throw UnimplementedError();
  }
}

AssetResult asset({
  required String id,
  required String mimeType,
}) {
  return AssetResult(
    id: id,
    projectId: 'project-1',
    generationJobId: 'image-job-1',
    storagePath: 'user-1/project-1/$id',
    mimeType: mimeType,
  );
}

GenerationJob completedModelJob(String jobId) {
  return GenerationJob(
    id: jobId,
    projectId: 'project-1',
    provider: 'tripo',
    operation: GenerationOperation.imageToModel,
    status: GenerationStatus.success,
    progress: 1,
    assetResultId: 'model-asset-1',
    storagePath: 'user-1/project-1/$jobId.glb',
    mimeType: 'model/gltf-binary',
  );
}

void main() {
  test('model generation uses selected image asset_result_id', () async {
    final gateway = FakeModelGateway();
    final controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (jobId) async => completedModelJob(jobId),
    );

    await controller.generateFromImage(
      asset(id: 'image-asset-7', mimeType: 'image/png'),
    );

    expect(gateway.modelCalls, 1);
    expect(gateway.lastAssetResultId, 'image-asset-7');
    expect(controller.job?.status, GenerationStatus.success);
    expect(controller.job?.operation, GenerationOperation.imageToModel);
  });

  test('non-image result cannot start model generation', () async {
    final gateway = FakeModelGateway();
    final controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (jobId) async => completedModelJob(jobId),
    );

    await controller.generateFromImage(
      asset(id: 'existing-model', mimeType: 'model/gltf-binary'),
    );

    expect(gateway.modelCalls, 0);
    expect(controller.errorCode, 'image_required');
  });

  test('repeated taps while model job is active create only one job', () async {
    final gateway = FakeModelGateway();
    final terminal = Completer<GenerationJob>();
    final controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (_) => terminal.future,
    );
    final image = asset(id: 'image-asset-1', mimeType: 'image/jpeg');

    final first = controller.generateFromImage(image);
    await Future<void>.delayed(Duration.zero);

    await controller.generateFromImage(image);

    expect(controller.isBusy, isTrue);
    expect(gateway.modelCalls, 1);

    terminal.complete(completedModelJob('model-job-1'));
    await first;

    expect(controller.isBusy, isFalse);
    expect(controller.job?.status, GenerationStatus.success);
  });
}
