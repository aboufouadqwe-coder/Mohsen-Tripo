import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mohsen_tripo/src/features/workspace/desktop_reference_analysis_service.dart';

void main() {
  const service = DesktopReferenceAnalysisService();

  test('desktop templates make no unsupported face or pose detection claims', () async {
    final image = img.Image(width: 2, height: 2);
    final bytes = Uint8List.fromList(img.encodePng(image));
    final result = await service.analyze(bytes);

    expect(result.hasFace, false);
    expect(result.hasPose, false);
    expect(result.isFullBody, false);
    expect(result.hasUpperBody, false);
    expect(result.suggestions, isNotEmpty);
    expect(result.suggestions.every((p) => p.region == null), isTrue);
    expect(result.suggestions.every((p) => !p.enabled), isTrue);
  });

  test('desktop templates reject invalid images', () async {
    await expectLater(
      service.analyze(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
  });
}
