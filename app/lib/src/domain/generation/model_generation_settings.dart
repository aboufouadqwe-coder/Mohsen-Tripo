enum ModelQualityPreset {
  lowPoly,
  standard,
  high,
}

enum ModelTopology {
  adaptive,
  triangles,
  quads,
}

final class ModelGenerationSettings {
  const ModelGenerationSettings({
    this.preset = ModelQualityPreset.standard,
    this.topology = ModelTopology.triangles,
    this.faceLimit = 100000,
    this.texture = true,
    this.pbr = true,
    this.enableImageAutofix = false,
  });

  final ModelQualityPreset preset;
  final ModelTopology topology;
  final int? faceLimit;
  final bool texture;
  final bool pbr;
  final bool enableImageAutofix;

  int get minFaceLimit {
    if (preset == ModelQualityPreset.lowPoly) {
      return topology == ModelTopology.quads ? 48 : 50;
    }
    return 48;
  }

  int get maxFaceLimit {
    if (topology == ModelTopology.quads) {
      return preset == ModelQualityPreset.lowPoly ? 25000 : 150000;
    }

    return switch (preset) {
      ModelQualityPreset.lowPoly => 20000,
      ModelQualityPreset.standard => 1000000,
      ModelQualityPreset.high => 2000000,
    };
  }

  int? get validatedFaceLimit {
    if (topology == ModelTopology.adaptive) return null;
    final value = faceLimit ?? defaultFaceLimitFor(preset, topology);
    return value.clamp(minFaceLimit, maxFaceLimit).toInt();
  }

  bool get mayProduceFbx => topology == ModelTopology.quads;

  ModelGenerationSettings copyWith({
    ModelQualityPreset? preset,
    ModelTopology? topology,
    int? faceLimit,
    bool clearFaceLimit = false,
    bool? texture,
    bool? pbr,
    bool? enableImageAutofix,
  }) {
    return ModelGenerationSettings(
      preset: preset ?? this.preset,
      topology: topology ?? this.topology,
      faceLimit: clearFaceLimit ? null : (faceLimit ?? this.faceLimit),
      texture: texture ?? this.texture,
      pbr: pbr ?? this.pbr,
      enableImageAutofix: enableImageAutofix ?? this.enableImageAutofix,
    );
  }

  Map<String, Object?> toFunctionBody() {
    final body = <String, Object?>{
      'quality_preset': switch (preset) {
        ModelQualityPreset.lowPoly => 'low_poly',
        ModelQualityPreset.standard => 'standard',
        ModelQualityPreset.high => 'high',
      },
      'topology': switch (topology) {
        ModelTopology.adaptive => 'adaptive',
        ModelTopology.triangles => 'triangles',
        ModelTopology.quads => 'quads',
      },
      'texture': texture,
      'pbr': pbr && texture,
      'enable_image_autofix': enableImageAutofix,
    };

    final limit = validatedFaceLimit;
    if (limit != null) {
      body['face_limit'] = limit;
    }
    return body;
  }

  static int defaultFaceLimitFor(
    ModelQualityPreset preset,
    ModelTopology topology,
  ) {
    if (topology == ModelTopology.adaptive) return 0;
    if (topology == ModelTopology.quads) {
      return preset == ModelQualityPreset.lowPoly ? 10000 : 50000;
    }
    return switch (preset) {
      ModelQualityPreset.lowPoly => 10000,
      ModelQualityPreset.standard => 100000,
      ModelQualityPreset.high => 500000,
    };
  }
}
