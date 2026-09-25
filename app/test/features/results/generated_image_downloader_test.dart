import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/assets/asset_result.dart';
import 'package:mohsen_tripo/src/features/results/generated_image_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download fetches signed image and saves with stable gallery filename',
      () async {
    String? fetchedUrl;
    String? savedName;
    String? savedMime;
    Uint8List? savedBytes;

    final downloader = GeneratedImageDownloader(
      fetcher: (url) async {
        fetchedUrl = url;
        return Uint8List.fromList([1, 2, 3]);
      },
      saver: ({
        required bytes,
        required fileName,
        required mimeType,
      }) async {
        savedBytes = bytes;
        savedName = fileName;
        savedMime = mimeType;
      },
    );

    await downloader.download(
      AssetResult(
        id: 'asset-123',
        projectId: 'project-1',
        generationJobId: 'job-1',
        storagePath: 'user/project/image.png',
        mimeType: 'image/png',
      ),
      'https://signed.test/image.png',
    );

    expect(fetchedUrl, 'https://signed.test/image.png');
    expect(savedName, 'Mohsen-Tripo-asset-123.png');
    expect(savedMime, 'image/png');
    expect(savedBytes, Uint8List.fromList([1, 2, 3]));
  });

  test('downloadModel delegates URL streaming to Android', () async {
    const channel = MethodChannel('com.mohsentripo.mohsen_tripo/media');
    MethodCall? received;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'content://downloads/model-123.glb';
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final downloader = GeneratedImageDownloader();

    await downloader.downloadModel(
      const AssetResult(
        id: 'model-123',
        projectId: 'project-1',
        generationJobId: 'model-job-1',
        storagePath: 'user/project/model.glb',
        mimeType: 'model/gltf-binary',
      ),
      'https://signed.test/model.glb',
    );

    expect(received?.method, 'saveModelFromUrl');
    expect(received?.arguments, {
      'url': 'https://signed.test/model.glb',
      'fileName': 'Mohsen-Tripo-model-123.glb',
      'mimeType': 'model/gltf-binary',
    });
  });
}
