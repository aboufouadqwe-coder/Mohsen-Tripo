import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
  });

  static const _channel =
      MethodChannel('com.mohsentripo.mohsen_tripo/media');

  final ImageBytesFetcher? fetcher;
  final ImageBytesSaver? saver;

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

    final extension = asset.isFbx ? 'fbx' : 'glb';
    final mimeType =
        asset.isFbx ? 'application/octet-stream' : 'model/gltf-binary';
    final fileName = 'Mohsen-Tripo-${asset.id}.$extension';
    if (Platform.isWindows) {
      await _saveModelToDesktop(signedUrl, fileName);
      return;
    }

    final savedUri = await _channel.invokeMethod<String>(
      'saveModelFromUrl',
      {
        'url': signedUrl,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    if (savedUri == null || savedUri.trim().isEmpty) {
      throw StateError('Android did not return a saved model URI.');
    }
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

  // The Android MethodChannel is intentionally not invoked on Windows.
  static Future<Directory> _desktopDownloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    final fallback = await getApplicationDocumentsDirectory();
    final root = downloads ?? fallback;
    final directory = Directory('${root.path}${Platform.pathSeparator}Mohsen-Tripo');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<void> _saveModelToDesktop(String url, String fileName) async {
    final directory = await _desktopDownloadDirectory();
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    final partial = File('${target.path}.part');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Model download failed: HTTP ${response.statusCode}');
      }
      final sink = partial.openWrite();
      try {
        await sink.addStream(response);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await partial.length() == 0) {
        throw StateError('Downloaded model is empty.');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }

  static Future<void> _saveToGallery({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (Platform.isWindows) {
      final directory = await _desktopDownloadDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return;
    }

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
