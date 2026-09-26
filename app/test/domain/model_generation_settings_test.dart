import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';

void main() {
  test('low poly quad settings produce bounded function payload', () {
    const settings = ModelGenerationSettings(
      preset: ModelQualityPreset.lowPoly,
      topology: ModelTopology.quads,
      faceLimit: 12000,
      texture: true,
      pbr: false,
      enableImageAutofix: true,
    );

    expect(settings.toFunctionBody(), {
      'quality_preset': 'low_poly',
      'topology': 'quads',
      'face_limit': 12000,
      'texture': true,
      'pbr': false,
      'enable_image_autofix': true,
    });
    expect(settings.maxFaceLimit, 25000);
    expect(settings.mayProduceFbx, isTrue);
  });

  test('adaptive topology omits face limit', () {
    const settings = ModelGenerationSettings(
      preset: ModelQualityPreset.high,
      topology: ModelTopology.adaptive,
      faceLimit: 500000,
    );

    expect(settings.toFunctionBody().containsKey('face_limit'), isFalse);
  });

  test('PBR is disabled in payload when texture is disabled', () {
    const settings = ModelGenerationSettings(
      texture: false,
      pbr: true,
    );

    expect(settings.toFunctionBody()['pbr'], isFalse);
  });
}
