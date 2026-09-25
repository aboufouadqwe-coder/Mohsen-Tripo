import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';
import 'package:mohsen_tripo/src/features/workspace/generation_batch_controller.dart';
import 'package:mohsen_tripo/src/features/workspace/job_polling_service.dart';

GenerationJob successJob(String partKey, String assetResultId) {
  return GenerationJob(
    id: 'job-$partKey',
    projectId: 'project-1',
    provider: 'tripo',
    operation: GenerationOperation.imageToImage,
    status: GenerationStatus.success,
    partKey: partKey,
    progress: 1,
    assetResultId: assetResultId,
    storagePath: 'user-1/project-1/$partKey.png',
    mimeType: 'image/png',
  );
}

GenerationJob failedJob(String partKey, String code) {
  return GenerationJob(
    id: 'job-$partKey',
    projectId: 'project-1',
    provider: 'tripo',
    operation: GenerationOperation.imageToImage,
    status: GenerationStatus.failed,
    partKey: partKey,
    progress: 1,
    errorCode: code,
  );
}

final class FakeBatchGateway implements GenerationGateway {
  final Map<String, List<GenerationJob>> resultQueueByPart = {};
  final Map<String, String> partByJobId = {};
  final Map<String, int> submitCountByPart = {};
  final List<String> events = [];

  @override
  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? partLabel,
    String? partPrompt,
    String? customInstructions,
  }) async {
    events.add('submit:$partKey');
    final next = (submitCountByPart[partKey] ?? 0) + 1;
    submitCountByPart[partKey] = next;
    final jobId = 'job-$partKey-$next';
    partByJobId[jobId] = partKey;
    return jobId;
  }

  @override
  Future<GenerationJob> refreshJob(String jobId) async {
    final partKey = partByJobId[jobId]!;
    events.add('poll:$partKey');
    final queue = resultQueueByPart[partKey]!;
    if (queue.length == 1) return queue.first;
    return queue.removeAt(0);
  }

  @override
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateModel(
    String assetResultId, {
    ModelGenerationSettings settings = const ModelGenerationSettings(),
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('one failed part does not erase successful siblings', () async {
    final gateway = FakeBatchGateway()
      ..resultQueueByPart.addAll({
        'head': [successJob('head', 'head-result')],
        'left_hand': [failedJob('left_hand', 'provider_failed')],
        'right_hand': [successJob('right_hand', 'right-result')],
      });

    final polling = JobPollingService(
      gateway: gateway,
      delay: (_) async {},
    );
    final controller = GenerationBatchController(
      gateway: gateway,
      pollingService: polling,
      projectId: 'project-1',
    );

    await controller.generateAll(
      parts: const [
        GenerationPartRequest(key: 'head', label: 'Head', prompt: 'head prompt'),
        GenerationPartRequest(key: 'left_hand', label: 'Left Hand', prompt: 'left prompt'),
        GenerationPartRequest(key: 'right_hand', label: 'Right Hand', prompt: 'right prompt'),
      ],
    );

    expect(controller.state['head']!.isSuccess, isTrue);
    expect(controller.state['left_hand']!.isFailure, isTrue);
    expect(controller.state['right_hand']!.isSuccess, isTrue);
    expect(controller.state['head']!.assetResultId, 'head-result');
    expect(controller.state['right_hand']!.assetResultId, 'right-result');
  });

  test('batch generation waits for each part before submitting the next', () async {
    final gateway = FakeBatchGateway()
      ..resultQueueByPart.addAll({
        'head': [successJob('head', 'head-result')],
        'left_hand': [successJob('left_hand', 'left-result')],
        'right_hand': [successJob('right_hand', 'right-result')],
      });

    final controller = GenerationBatchController(
      gateway: gateway,
      pollingService: JobPollingService(
        gateway: gateway,
        delay: (_) async {},
      ),
      projectId: 'project-1',
    );

    await controller.generateAll(
      parts: const [
        GenerationPartRequest(key: 'head', label: 'Head', prompt: 'head prompt'),
        GenerationPartRequest(key: 'left_hand', label: 'Left Hand', prompt: 'left prompt'),
        GenerationPartRequest(key: 'right_hand', label: 'Right Hand', prompt: 'right prompt'),
      ],
    );

    expect(
      gateway.events,
      [
        'submit:head',
        'poll:head',
        'submit:left_hand',
        'poll:left_hand',
        'submit:right_hand',
        'poll:right_hand',
      ],
    );
  });

  test('single-part generation submits and polls only requested part', () async {
    final gateway = FakeBatchGateway()
      ..resultQueueByPart['custom-1'] = [
        successJob('custom-1', 'custom-result'),
      ];

    final controller = GenerationBatchController(
      gateway: gateway,
      pollingService: JobPollingService(
        gateway: gateway,
        delay: (_) async {},
      ),
      projectId: 'project-1',
    );

    await controller.generatePart(
      const GenerationPartRequest(
        key: 'custom-1',
        label: 'Arm with shoulder',
        prompt: 'Keep the same arm angle.',
      ),
    );

    expect(gateway.events, ['submit:custom-1', 'poll:custom-1']);
    expect(controller.state['custom-1']!.isSuccess, isTrue);
  });

  test('retry creates a new provider job and replaces only latest part state',
      () async {
    final gateway = FakeBatchGateway()
      ..resultQueueByPart['head'] = [
        failedJob('head', 'provider_failed'),
        successJob('head', 'head-result-2'),
      ];

    final controller = GenerationBatchController(
      gateway: gateway,
      pollingService: JobPollingService(
        gateway: gateway,
        delay: (_) async {},
      ),
      projectId: 'project-1',
    );

    await controller.generateAll(
      parts: const [
        GenerationPartRequest(key: 'head', label: 'Head', prompt: 'head prompt'),
      ],
    );
    final firstJobId = controller.state['head']!.jobId;
    expect(controller.state['head']!.isFailure, isTrue);

    await controller.regeneratePart(
      const GenerationPartRequest(
        key: 'head',
        label: 'Head',
        prompt: 'head prompt',
      ),
    );
    final secondJobId = controller.state['head']!.jobId;

    expect(firstJobId, isNot(secondJobId));
    expect(gateway.submitCountByPart['head'], 2);
    expect(controller.state['head']!.isSuccess, isTrue);
    expect(controller.state['head']!.assetResultId, 'head-result-2');
  });
}
