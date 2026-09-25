import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';

final class FakeFunctionInvoker implements FunctionInvoker {
  String? lastFunction;
  Map<String, Object?>? lastBody;
  final Map<String, Map<String, Object?>> responses = {};

  @override
  Future<Map<String, Object?>> invoke(
    String functionName,
    Map<String, Object?> body,
  ) async {
    lastFunction = functionName;
    lastBody = body;
    return responses[functionName] ?? const {};
  }
}

void main() {
  test('generateSourceImage invokes the expected Edge Function', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-source-image'] = {'job_id': 'job-source'};
    final gateway = DefaultGenerationGateway(invoker);

    final jobId = await gateway.generateSourceImage(
      projectId: 'project-1',
      prompt: 'old hospital patient',
    );

    expect(jobId, 'job-source');
    expect(invoker.lastFunction, 'generate-source-image');
    expect(invoker.lastBody, {
      'project_id': 'project-1',
      'prompt': 'old hospital patient',
    });
  });

  test('generateImagePart omits null custom instructions', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-image-part'] = {'job_id': 'job-part'};
    final gateway = DefaultGenerationGateway(invoker);

    final jobId = await gateway.generateImagePart(
      projectId: 'project-1',
      partKey: 'head',
    );

    expect(jobId, 'job-part');
    expect(invoker.lastBody, {
      'project_id': 'project-1',
      'part_key': 'head',
    });
  });

  test('generateImagePart forwards exact part label and prompt', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-image-part'] = {'job_id': 'job-part'};
    final gateway = DefaultGenerationGateway(invoker);

    final jobId = await gateway.generateImagePart(
      projectId: 'project-1',
      partKey: 'custom-1',
      partLabel: 'Arm with shoulder',
      partPrompt: 'Keep the same arm angle and silhouette.',
    );

    expect(jobId, 'job-part');
    expect(invoker.lastBody, {
      'project_id': 'project-1',
      'part_key': 'custom-1',
      'part_label': 'Arm with shoulder',
      'part_prompt': 'Keep the same arm angle and silhouette.',
    });
  });

  test('refreshJob maps provider-neutral job response', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['refresh-generation-job'] = {
        'job_id': 'job-1',
        'project_id': 'project-1',
        'part_key': 'head',
        'provider': 'tripo',
        'operation': 'image_to_image',
        'provider_task_id': 'provider-task-1',
        'status': 'running',
        'progress': 0.4,
      };
    final gateway = DefaultGenerationGateway(invoker);

    final job = await gateway.refreshJob('job-1');

    expect(job.id, 'job-1');
    expect(job.projectId, 'project-1');
    expect(job.operation, GenerationOperation.imageToImage);
    expect(job.status, GenerationStatus.running);
    expect(job.progress, 0.4);
  });

  test('generateModel invokes model Edge Function', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-model'] = {'job_id': 'job-model'};
    final gateway = DefaultGenerationGateway(invoker);

    final jobId = await gateway.generateModel(
      'asset-1',
      settings: const ModelGenerationSettings(
        preset: ModelQualityPreset.lowPoly,
        topology: ModelTopology.quads,
        faceLimit: 12000,
        texture: true,
        pbr: false,
        enableImageAutofix: true,
      ),
    );

    expect(jobId, 'job-model');
    expect(invoker.lastFunction, 'generate-model');
    expect(invoker.lastBody, {
      'asset_result_id': 'asset-1',
      'quality_preset': 'low_poly',
      'topology': 'quads',
      'face_limit': 12000,
      'texture': true,
      'pbr': false,
      'enable_image_autofix': true,
    });
  });
}
