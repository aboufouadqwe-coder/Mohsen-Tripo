import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/reference_image_repository.dart';
import 'package:mohsen_tripo/src/features/results/direct_model_image_picker.dart';

final class FakeDirectModelImageRepository
    implements DirectModelImageRepository {
  int calls = 0;

  @override
  Future<String> uploadModelInput({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  }) async {
    calls += 1;
    return '$userId/$projectId/model-inputs/test.$extension';
  }
}

void main() {
  testWidgets('direct 3d picker rejects unsupported image format before upload',
      (tester) async {
    final repository = FakeDirectModelImageRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectModelImagePicker(
            userId: 'user-1',
            projectId: 'project-1',
            repository: repository,
            pickImage: () async => DirectModelLocalImage(
              name: 'patient.gif',
              sizeBytes: 100,
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            ),
            onGenerate: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('اختيار صورة للـ 3D'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PNG أو JPEG'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('valid direct image uploads then can start 3d generation',
      (tester) async {
    final repository = FakeDirectModelImageRepository();
    String? generatedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectModelImagePicker(
            userId: 'user-1',
            projectId: 'project-1',
            repository: repository,
            pickImage: () async => DirectModelLocalImage(
              name: 'patient.png',
              sizeBytes: 1024,
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            ),
            onGenerate: (path) async {
              generatedPath = path;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('اختيار صورة للـ 3D'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.text('patient.png'), findsOneWidget);
    expect(find.text('توليد 3D من الصورة'), findsOneWidget);

    await tester.tap(find.text('توليد 3D من الصورة'));
    await tester.pumpAndSettle();

    expect(
      generatedPath,
      'user-1/project-1/model-inputs/test.png',
    );
  });
}
