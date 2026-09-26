import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/data/supabase/reference_image_repository.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';
import 'package:mohsen_tripo/src/features/workspace/reference_image_picker.dart';
import 'package:mohsen_tripo/src/features/workspace/source_image_generator.dart';

final class RecordingReferenceRepository
    implements ReferenceImageRepository {
  int uploadCalls = 0;

  @override
  Future<String> uploadReference({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  }) async {
    uploadCalls += 1;
    return '$userId/$projectId/reference.$extension';
  }

}

final class FakeGenerationGateway implements GenerationGateway {
  FakeGenerationGateway(this.jobs);

  final List<GenerationJob> jobs;
  int generateSourceImageCalls = 0;
  int refreshCalls = 0;

  @override
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  }) async {
    generateSourceImageCalls += 1;
    return 'job-source-1';
  }

  @override
  Future<GenerationJob> refreshJob(String jobId) async {
    final index = refreshCalls.clamp(0, jobs.length - 1);
    refreshCalls += 1;
    return jobs[index];
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
  Future<String> generateModel(
    String assetResultId, {
    ModelGenerationSettings settings = const ModelGenerationSettings(),
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('reference picker rejects unsupported extension before upload',
      (tester) async {
    final repository = RecordingReferenceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferenceImagePicker(
            userId: 'user-1',
            projectId: 'project-1',
            repository: repository,
            pickImage: () async => LocalReferenceImage(
              name: 'patient.gif',
              sizeBytes: 1024,
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            ),
            onUploaded: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('رفع صورة'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PNG أو JPEG'), findsOneWidget);
    expect(repository.uploadCalls, 0);
  });

  testWidgets('reference picker rejects files larger than 20 MB before upload',
      (tester) async {
    final repository = RecordingReferenceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferenceImagePicker(
            userId: 'user-1',
            projectId: 'project-1',
            repository: repository,
            pickImage: () async => LocalReferenceImage(
              name: 'patient.png',
              sizeBytes: 20 * 1024 * 1024 + 1,
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            ),
            onUploaded: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('رفع صورة'));
    await tester.pumpAndSettle();

    expect(find.textContaining('20 MB'), findsOneWidget);
    expect(repository.uploadCalls, 0);
  });

  testWidgets('blank source prompt is rejected locally', (tester) async {
    final gateway = FakeGenerationGateway([
      const GenerationJob(
        id: 'job-source-1',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.textToImage,
        status: GenerationStatus.success,
        progress: 1,
        assetResultId: 'asset-1',
        storagePath: 'user-1/project-1/source.png',
        mimeType: 'image/png',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceImageGenerator(
            projectId: 'project-1',
            gateway: gateway,
            pollInterval: Duration.zero,
            onSelectPersistedImage: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('source-prompt')), '   ');
    await tester.tap(find.text('إنشاء صورة مرجعية'));
    await tester.pumpAndSettle();

    expect(find.textContaining('اكتب وصف'), findsOneWidget);
    expect(gateway.generateSourceImageCalls, 0);
  });

  testWidgets(
      'submitted source prompt creates one job and successful persisted image can be selected',
      (tester) async {
    final gateway = FakeGenerationGateway([
      const GenerationJob(
        id: 'job-source-1',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.textToImage,
        status: GenerationStatus.success,
        progress: 1,
        assetResultId: 'asset-1',
        storagePath: 'user-1/project-1/source.png',
        mimeType: 'image/png',
      ),
    ]);
    String? selectedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceImageGenerator(
            projectId: 'project-1',
            gateway: gateway,
            pollInterval: Duration.zero,
            onSelectPersistedImage: (job) {
              selectedPath = job.storagePath;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('source-prompt')),
      'مريض شاب بضمادات رأس داخل مستشفى مهجور',
    );
    await tester.tap(find.text('إنشاء صورة مرجعية'));
    await tester.pumpAndSettle();

    expect(gateway.generateSourceImageCalls, 1);
    expect(gateway.refreshCalls, 1);
    expect(find.text('اعتماد كمرجع'), findsOneWidget);

    await tester.tap(find.text('اعتماد كمرجع'));
    await tester.pump();

    expect(selectedPath, 'user-1/project-1/source.png');
  });

  testWidgets('failed or unpersisted source image cannot be selected',
      (tester) async {
    final gateway = FakeGenerationGateway([
      const GenerationJob(
        id: 'job-source-1',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.textToImage,
        status: GenerationStatus.failed,
        progress: 1,
        errorCode: 'provider_failed',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceImageGenerator(
            projectId: 'project-1',
            gateway: gateway,
            pollInterval: Duration.zero,
            onSelectPersistedImage: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('source-prompt')),
      'hospital patient',
    );
    await tester.tap(find.text('إنشاء صورة مرجعية'));
    await tester.pumpAndSettle();

    expect(gateway.generateSourceImageCalls, 1);
    expect(find.text('اعتماد كمرجع'), findsNothing);
  });
  testWidgets('source generation shows elapsed time without fake zero percent progress',
      (tester) async {
    final gateway = FakeGenerationGateway([
      const GenerationJob(
        id: 'job-source-1',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.textToImage,
        status: GenerationStatus.running,
        progress: 0,
      ),
      const GenerationJob(
        id: 'job-source-1',
        projectId: 'project-1',
        provider: 'tripo',
        operation: GenerationOperation.textToImage,
        status: GenerationStatus.success,
        progress: 1,
        assetResultId: 'asset-1',
        storagePath: 'user-1/project-1/source.png',
        mimeType: 'image/png',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceImageGenerator(
            projectId: 'project-1',
            gateway: gateway,
            pollInterval: const Duration(seconds: 1),
            onSelectPersistedImage: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('source-prompt')),
      'hospital patient',
    );
    await tester.tap(find.text('إنشاء صورة مرجعية'));
    await tester.pump();

    expect(find.textContaining('الوقت المنقضي:'), findsOneWidget);
    expect(find.text('التقدم: جارٍ التوليد…'), findsOneWidget);
    expect(find.text('التقدم: 0%'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('التقدم: 100%'), findsOneWidget);
  });


}
