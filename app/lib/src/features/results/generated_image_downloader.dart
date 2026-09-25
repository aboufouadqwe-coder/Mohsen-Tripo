import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../domain/assets/asset_result.dart';

typedef ImageBytesFetcher = Future<Uint8List> Function(String url);
typedef ImageBytesSaver = Future<void> Function({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
});

final class GeneratedImageDownloader {
  const GeneratedImageDownloader({
    this.fetcher,
    this.saver,
    this.modelSaver,
  });

  static const _channel =
      MethodChannel('com.mohsentripo.mohsen_tripo/media');

  final ImageBytesFetcher? fetcher;
  final ImageBytesSaver? saver;
  final ImageBytesSaver? modelSaver;

  Future<void> download(
    AssetResult asset,
    String signedUrl,
  ) async {
    if (!asset.isImage) {
      throw StateError('Only image assets can be downloaded.');
    }

    final uri = Uri.tryParse(signedUrl);
    if (uri == null || !uri.hasScheme) {
      throw StateError('Image URL is invalid.');
    }

    final bytes = await (fetcher ?? _downloadBytes)(signedUrl);
    if (bytes.isEmpty) {
      throw StateError('Downloaded image is empty.');
    }

    final extension = switch (asset.mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => throw StateError('Unsupported image type.'),
    };

    final fileName = 'Mohsen-Tripo-${asset.id}.$extension';
    final imageSaver = saver ?? _saveToGallery;
    await imageSaver(
      bytes: bytes,
      fileName: fileName,
      mimeType: asset.mimeType,
    );
  }

  Future<void> downloadModel(
    AssetResult asset,
    String signedUrl,
  ) async {
    if (!asset.isModel) {
      throw StateError('Only model assets can be downloaded.');
    }

    final uri = Uri.tryParse(signedUrl);
    if (uri == null || !uri.hasScheme) {
      throw StateError('Model URL is invalid.');
    }

    final bytes = await (fetcher ?? _downloadBytes)(signedUrl);
    if (bytes.isEmpty) {
      throw StateError('Downloaded model is empty.');
    }

    final fileName = 'Mohsen-Tripo-${asset.id}.glb';
    final modelFileSaver = modelSaver ?? _saveModelToDownloads;
    await modelFileSaver(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'model/gltf-binary',
    );
  }

  static Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Image download failed with status ${response.statusCode}.',
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _saveModelToDownloads({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final savedUri = await _channel.invokeMethod<String>(
      'saveModel',
      {
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    if (savedUri == null || savedUri.trim().isEmpty) {
      throw StateError('Android did not return a saved model URI.');
    }
  }

  static Future<void> _saveToGallery({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final savedUri = await _channel.invokeMethod<String>(
      'saveImage',
      {
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    if (savedUri == null || savedUri.trim().isEmpty) {
      throw StateError('Android did not return a saved image URI.');
    }
  }
}
