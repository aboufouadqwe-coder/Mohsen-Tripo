import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/tripo/tripo_credential.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';

final class FakeFunctionInvoker implements FunctionInvoker {
  String? lastFunction;
  Map<String, Object?>? lastBody;
  Map<String, String>? lastHeaders;
  final Map<String, Map<String, Object?>> responses = {};

  @override
  Future<Map<String, Object?>> invoke(
    String functionName,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    lastFunction = functionName;
    lastBody = body;
    lastHeaders = headers;
    return responses[functionName] ?? const {};
  }
  test('generateModelFromReferencePath invokes model Edge Function', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-model'] = {'job_id': 'job-direct-model'};
    final gateway = gatewayWith(invoker);
    final directGateway = gateway as DirectModelGenerationGateway;

    final jobId = await directGateway.generateModelFromReferencePath(
      projectId: 'project-1',
      referenceStoragePath:
          'user-1/project-1/model-inputs/model-input-1.png',
      settings: const ModelGenerationSettings(
        preset: ModelQualityPreset.standard,
        topology: ModelTopology.triangles,
      ),
    );

    expect(jobId, 'job-direct-model');
    expect(invoker.lastFunction, 'generate-model');
    expect(invoker.lastBody?['project_id'], 'project-1');
    expect(
      invoker.lastBody?['reference_storage_path'],
      'user-1/project-1/model-inputs/model-input-1.png',
    );
    expect(invoker.lastBody?.containsKey('asset_result_id'), isFalse);
  });
}

final class FakeCredentialProvider implements ActiveTripoCredentialProvider {
  const FakeCredentialProvider();

  @override
  Future<TripoCredential?> getActive() async => TripoCredential(
        name: 'Test',
        apiKey: 'tsk_test_key_12345678901234567890',
        fingerprint: 'fingerprint-1',
        createdAt: DateTime.utc(2026, 9, 26),
      );

  @override
  Future<TripoCredential?> findByFingerprint(String fingerprint) async =>
      fingerprint == 'fingerprint-1' ? getActive() : null;
}

DefaultGenerationGateway gatewayWith(FakeFunctionInvoker invoker) =>
    DefaultGenerationGateway(
      invoker,
      credentialProvider: const FakeCredentialProvider(),
    );

void main() {
  test('generateSourceImage invokes the expected Edge Function', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-source-image'] = {'job_id': 'job-source'};
    final gateway = gatewayWith(invoker);

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
    expect(
      invoker.lastHeaders?['x-tripo-api-key'],
      'tsk_test_key_12345678901234567890',
    );
  });

  test('generateImagePart omits null custom instructions', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-image-part'] = {'job_id': 'job-part'};
    final gateway = gatewayWith(invoker);

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
    final gateway = gatewayWith(invoker);

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

  test('generateImagePart forwards cropped reference storage path', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['generate-image-part'] = {'job_id': 'job-part'};
    final gateway = gatewayWith(invoker);

    final jobId = await gateway.generateImagePart(
      projectId: 'project-1',
      partKey: 'head',
      partLabel: 'Head Clean',
      partPrompt: 'Generate only a clean bald head.',
      referenceStoragePath: 'user-1/project-1/parts/head.png',
    );

    expect(jobId, 'job-part');
    expect(invoker.lastBody, {
      'project_id': 'project-1',
      'part_key': 'head',
      'part_label': 'Head Clean',
      'part_prompt': 'Generate only a clean bald head.',
      'reference_storage_path': 'user-1/project-1/parts/head.png',
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
    final gateway = gatewayWith(invoker);

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
    final gateway = gatewayWith(invoker);

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

  test('getCreditBalance maps secure balance function response', () async {
    final invoker = FakeFunctionInvoker()
      ..responses['tripo-balance'] = {
        'balance': 987.5,
        'frozen': 20,
      };
    final gateway = gatewayWith(invoker);

    final balance = await gateway.getCreditBalance();

    expect(invoker.lastFunction, 'tripo-balance');
    expect(balance.available, 987.5);
    expect(balance.frozen, 20);
  });

}
