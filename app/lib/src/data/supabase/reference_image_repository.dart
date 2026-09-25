import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

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

abstract interface class DirectModelImageRepository {
  Future<String> uploadModelInput({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
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
        PartReferenceCropper,
        DirectModelImageRepository {
  DefaultReferenceImageRepository(
    this._storage, {
    String Function()? objectId,
  }) : _objectId = objectId ?? const Uuid().v4;

  final ReferenceStoragePort _storage;
  final String Function() _objectId;

  @override
  Future<Uint8List> downloadReference(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      throw AppFailure.validation('Reference image path is empty.');
    }
    return _storage.downloadReference(normalized);
  }

  @override
  Future<String> createPartReferenceCrop({
    required String userId,
    required String projectId,
    required String partKey,
    required String sourcePath,
    required NormalizedRegion region,
  }) async {
    if (userId.trim().isEmpty ||
        projectId.trim().isEmpty ||
        partKey.trim().isEmpty ||
        sourcePath.trim().isEmpty ||
        !region.isValid) {
      throw AppFailure.validation('Part crop information is incomplete.');
    }

    try {
      final bytes = await _storage.downloadReference(sourcePath.trim());
      final source = img.decodeImage(bytes);
      if (source == null || source.width <= 0 || source.height <= 0) {
        throw AppFailure.storage();
      }

      final clamped = region.clamp();
      final x = (clamped.left * source.width)
          .floor()
          .clamp(0, source.width - 1)
          .toInt();
      final y = (clamped.top * source.height)
          .floor()
          .clamp(0, source.height - 1)
          .toInt();
      final right = (clamped.right * source.width)
          .ceil()
          .clamp(x + 1, source.width)
          .toInt();
      final bottom = (clamped.bottom * source.height)
          .ceil()
          .clamp(y + 1, source.height)
          .toInt();

      final crop = img.copyCrop(
        source,
        x: x,
        y: y,
        width: right - x,
        height: bottom - y,
      );
      final png = Uint8List.fromList(img.encodePng(crop));
      final safeKey = partKey
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final path =
          '${userId.trim()}/${projectId.trim()}/parts/$safeKey.png';

      await _storage.upload(
        path: path,
        bytes: png,
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
  Future<String> uploadModelInput({
    required String userId,
    required String projectId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (userId.trim().isEmpty ||
        projectId.trim().isEmpty ||
        bytes.isEmpty) {
      throw AppFailure.validation('Direct model image data is incomplete.');
    }

    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final contentType = switch (normalizedExtension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => throw AppFailure.validation(
          'Direct model image must be PNG or JPEG.',
        ),
    };
    final outputExtension =
        normalizedExtension == 'jpeg' ? 'jpg' : normalizedExtension;
    final id = _objectId().trim();
    if (id.isEmpty) {
      throw AppFailure.storage();
    }
    final path =
        '${userId.trim()}/${projectId.trim()}/model-inputs/$id.$outputExtension';

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
