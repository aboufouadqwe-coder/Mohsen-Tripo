import 'dart:typed_data';

import '../../core/errors/app_failure.dart';

abstract interface class ReferenceImageRepository {
  Future<String> uploadReference({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  });
}

abstract interface class ReferenceStoragePort {
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  });
}

final class DefaultReferenceImageRepository
    implements ReferenceImageRepository {
  const DefaultReferenceImageRepository(this._storage);

  final ReferenceStoragePort _storage;

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
