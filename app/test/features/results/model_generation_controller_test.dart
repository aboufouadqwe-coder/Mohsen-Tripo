import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/assets/asset_result.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';
import 'package:mohsen_tripo/src/features/results/model_generation_controller.dart';

final class FakeModelGateway implements GenerationGateway {
  int modelCalls = 0;
  String? lastAssetResultId;
  ModelGenerationSettings? lastSettings;

  @override
  Future<String> generateModel(
    String assetResultId, {
    ModelGenerationSettings settings = const ModelGenerationSettings(),
  }) async {
    modelCalls += 1;
    lastAssetResultId = assetResultId;
    lastSettings = settings;
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
    String? partLabel,
    String? partPrompt,
    String? customInstructions,
    String? referenceStoragePath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<GenerationJob> refreshJob(String jobId) {
    throw UnimplementedError();
  }
  @override
  Future<String> generateModelFromReferencePath({
    required String projectId,
    required String referenceStoragePath,
    ModelGenerationSettings settings = const ModelGenerationSettings(),
  }) async {
    modelCalls += 1;
    lastAssetResultId = referenceStoragePath;
    lastSettings = settings;
    return 'model-job-$modelCalls';
  }
  test('direct reference path can start model generation', () async {
    final gateway = FakeModelGateway();
    final controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (jobId) async => completedModelJob(jobId),
    );

    await controller.generateFromReferencePath(
      projectId: 'project-1',
      referenceStoragePath:
          'user-1/project-1/model-inputs/model-input-1.png',
    );

    expect(gateway.modelCalls, 1);
    expect(
      gateway.lastAssetResultId,
      'user-1/project-1/model-inputs/model-input-1.png',
    );
    expect(controller.job?.status, GenerationStatus.success);
  });
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
      settings: const ModelGenerationSettings(
        preset: ModelQualityPreset.high,
        topology: ModelTopology.triangles,
        faceLimit: 750000,
      ),
    );

    expect(gateway.modelCalls, 1);
    expect(gateway.lastAssetResultId, 'image-asset-7');
    expect(gateway.lastSettings?.preset, ModelQualityPreset.high);
    expect(gateway.lastSettings?.faceLimit, 750000);
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

  test('3d controller exposes intermediate progress while polling', () async {
    final gateway = FakeModelGateway();
    final seen = <double>[];
    late final ModelGenerationController controller;

    controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (jobId) async => completedModelJob(jobId),
      pollUntilTerminalWithUpdates: (jobId, onUpdate) async {
        onUpdate(
          GenerationJob(
            id: jobId,
            projectId: 'project-1',
            provider: 'tripo',
            operation: GenerationOperation.imageToModel,
            status: GenerationStatus.running,
            progress: 0.86,
          ),
        );
        seen.add(controller.job?.progress ?? -1);
        return completedModelJob(jobId);
      },
    );

    await controller.generateFromImage(
      asset(id: 'image-asset-progress', mimeType: 'image/png'),
    );

    expect(seen, [0.86]);
    expect(controller.job?.progress, 1);
  });

  test('active 3d job can be resumed without creating a second provider task',
      () async {
    final gateway = FakeModelGateway();
    final controller = ModelGenerationController(
      gateway: gateway,
      pollUntilTerminal: (jobId) async => completedModelJob(jobId),
    );

    await controller.resumeJob(
      const GenerationJob(
        id: 'existing-model-job',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.imageToModel,
        status: GenerationStatus.running,
        partKey: 'head',
        progress: 0.56,
      ),
    );

    expect(gateway.modelCalls, 0);
    expect(controller.isBusy, isFalse);
    expect(controller.job?.id, 'existing-model-job');
    expect(controller.job?.status, GenerationStatus.success);
  });

}
