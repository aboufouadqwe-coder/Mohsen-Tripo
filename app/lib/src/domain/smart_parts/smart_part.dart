enum SmartPartKind {
  fullBodyAPose,
  headClean,
  hairHeadwear,
  faceOnly,
  torsoFront,
  rightArmDetached,
  leftArmDetached,
  rightHandOpen,
  leftHandOpen,
  rightLegDetached,
  leftLegDetached,
  feetShoes,
  accessory,
  custom,
}

enum PartPromptMode {
  exact,
  smart,
}

final class NormalizedRegion {
  const NormalizedRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isValid =>
      left >= 0 &&
      top >= 0 &&
      right <= 1 &&
      bottom <= 1 &&
      right > left &&
      bottom > top;

  NormalizedRegion clamp() {
    final l = left.clamp(0.0, 1.0).toDouble();
    final t = top.clamp(0.0, 1.0).toDouble();
    final r = right.clamp(0.0, 1.0).toDouble();
    final b = bottom.clamp(0.0, 1.0).toDouble();
    return NormalizedRegion(
      left: l,
      top: t,
      right: r <= l ? (l + 0.01).clamp(0.0, 1.0).toDouble() : r,
      bottom: b <= t ? (t + 0.01).clamp(0.0, 1.0).toDouble() : b,
    );
  }
}

final class SuggestedPart {
  const SuggestedPart({
    required this.key,
    required this.label,
    required this.kind,
    required this.prompt,
    this.enabled = true,
    this.region,
  });

  final String key;
  final String label;
  final SmartPartKind kind;
  final String prompt;
  final bool enabled;
  final NormalizedRegion? region;

  SuggestedPart copyWith({
    String? key,
    String? label,
    SmartPartKind? kind,
    String? prompt,
    bool? enabled,
    NormalizedRegion? region,
    bool clearRegion = false,
  }) {
    return SuggestedPart(
      key: key ?? this.key,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      region: clearRegion ? null : (region ?? this.region),
    );
  }
}

final class ReferenceAnalysis {
  const ReferenceAnalysis({
    required this.hasFace,
    required this.hasPose,
    required this.isFullBody,
    required this.hasUpperBody,
    required this.suggestions,
  });

  final bool hasFace;
  final bool hasPose;
  final bool isFullBody;
  final bool hasUpperBody;
  final List<SuggestedPart> suggestions;

  String get summary {
    if (isFullBody) {
      return 'تم اكتشاف شخصية كاملة؛ تم اقتراح الجسم والرأس والأطراف.';
    }
    if (hasUpperBody) {
      return 'تم اكتشاف الجزء العلوي؛ تم اقتراح الرأس والجذع والأجزاء الظاهرة.';
    }
    if (hasFace) {
      return 'تم اكتشاف وجه/بورتريه؛ تم اقتراح رأس نظيف وأجزاء الوجه.';
    }
    return 'لم يتم اكتشاف وضعية كاملة بثقة؛ يمكنك تعديل الاقتراحات أو إضافة جزء يدويًا.';
  }
}
