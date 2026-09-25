import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/errors/app_failure.dart';
import '../../domain/smart_parts/smart_part.dart';

abstract interface class ReferenceImageRepository {
  Future<String> uploadReference({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  });
}

abstract interface class ReferenceImageBytesReader {
  Future<Uint8List> downloadReference(String path);
}

abstract interface class PartReferenceCropper {
  Future<String> createPartReferenceCrop({
    required String userId,
    required String projectId,
    required String partKey,
    required String sourcePath,
    required NormalizedRegion region,
  });
}

abstract interface class GeneratedReferenceCopier {
  Future<String> copyGeneratedReference({
    required String userId,
    required String projectId,
    required String generatedPath,
  });
}

abstract interface class ReferenceStoragePort {
  Future<Uint8List> downloadReference(String path);

  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  });

  Future<Uint8List> downloadGenerated(String path);
}

final class DefaultReferenceImageRepository
    implements
        ReferenceImageRepository,
        GeneratedReferenceCopier,
        ReferenceImageBytesReader,
        PartReferenceCropper {
  const DefaultReferenceImageRepository(this._storage);

  final ReferenceStoragePort _storage;

  @override
  Future<String> copyGeneratedReference({
    required String userId,
    required String projectId,
    required String generatedPath,
  }) async {
    if (userId.trim().isEmpty ||
        projectId.trim().isEmpty ||
        generatedPath.trim().isEmpty) {
      throw AppFailure.validation(
        'Generated reference information is incomplete.',
      );
    }

    try {
      final bytes = await _storage.downloadGenerated(generatedPath.trim());
      if (bytes.isEmpty) throw AppFailure.storage();

      final path = '${userId.trim()}/${projectId.trim()}/reference.png';
      await _storage.upload(
        path: path,
        bytes: bytes,
        contentType: 'image/png',
      );
      return path;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.storage();
    }
  }

  @override
  Future<String> uploadReference({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (userId.trim().isEmpty ||
        projectId.trim().isEmpty ||
        bytes.isEmpty) {
      throw AppFailure.validation('Reference image data is incomplete.');
    }

    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final contentType = switch (normalizedExtension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => throw AppFailure.validation(
          'Reference image must be PNG or JPEG.',
        ),
    };
    final outputExtension =
        normalizedExtension == 'jpeg' ? 'jpg' : normalizedExtension;
    final path =
        '${userId.trim()}/${projectId.trim()}/reference.$outputExtension';

    try {
      await _storage.upload(
        path: path,
        bytes: bytes,
        contentType: contentType,
      );
      return path;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.storage();
    }
  }
}
