import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mohsen_tripo/src/data/supabase/reference_image_repository.dart';
import 'package:mohsen_tripo/src/domain/smart_parts/smart_part.dart';

final class FakeReferenceStorage implements ReferenceStoragePort {
  FakeReferenceStorage(this.referenceBytes);

  final Uint8List referenceBytes;
  String? uploadedPath;
  Uint8List? uploadedBytes;
  String? uploadedContentType;

  @override
  Future<Uint8List> downloadReference(String path) async => referenceBytes;

  @override
  Future<Uint8List> downloadGenerated(String path) async => referenceBytes;

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadedPath = path;
    uploadedBytes = bytes;
    uploadedContentType = contentType;
  }
}

void main() {
  test('direct 3d model input is stored under owned model-inputs path', () async {
    final source = img.Image(width: 300, height: 300);
    final bytes = Uint8List.fromList(img.encodePng(source));
    final storage = FakeReferenceStorage(bytes);
    final repository = DefaultReferenceImageRepository(
      storage,
      objectId: () => 'model-input-1',
    );

    final directRepository = repository as DirectModelImageRepository;
    final path = await directRepository.uploadModelInput(
      userId: 'user-1',
      projectId: 'project-1',
      bytes: bytes,
      extension: 'png',
    );

    expect(path, 'user-1/project-1/model-inputs/model-input-1.png');
    expect(storage.uploadedPath, path);
    expect(storage.uploadedContentType, 'image/png');
  });

  test('part crop stores a normalized PNG under owned project path', () async {
    final source = img.Image(width: 100, height: 80);
    final storage = FakeReferenceStorage(
      Uint8List.fromList(img.encodePng(source)),
    );
    final repository = DefaultReferenceImageRepository(storage);

    final path = await repository.createPartReferenceCrop(
      userId: 'user-1',
      projectId: 'project-1',
      partKey: 'Head Clean',
      sourcePath: 'user-1/project-1/reference.png',
      region: const NormalizedRegion(
        left: 0.2,
        top: 0.25,
        right: 0.8,
        bottom: 0.75,
      ),
    );

    expect(path, 'user-1/project-1/parts/Head_Clean.png');
    expect(storage.uploadedPath, path);
    expect(storage.uploadedContentType, 'image/png');

    final crop = img.decodePng(storage.uploadedBytes!);
    expect(crop, isNotNull);
    expect(crop!.width, 60);
    expect(crop.height, 40);
  });
}
