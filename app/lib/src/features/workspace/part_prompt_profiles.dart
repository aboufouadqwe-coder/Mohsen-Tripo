import '../../domain/smart_parts/smart_part.dart';

abstract final class PartPromptProfiles {
  static String build(
    SmartPartKind kind, {
    String? userInstructions,
  }) {
    final base = switch (kind) {
      SmartPartKind.fullBodyAPose => _fullBody,
      SmartPartKind.headClean => _headClean,
      SmartPartKind.hairHeadwear => _hairHeadwear,
      SmartPartKind.faceOnly => _faceOnly,
      SmartPartKind.torsoFront => _torso,
      SmartPartKind.rightArmDetached => _rightArm,
      SmartPartKind.leftArmDetached => _leftArm,
      SmartPartKind.rightHandOpen => _rightHand,
      SmartPartKind.leftHandOpen => _leftHand,
      SmartPartKind.rightLegDetached => _rightLeg,
      SmartPartKind.leftLegDetached => _leftLeg,
      SmartPartKind.feetShoes => _feet,
      SmartPartKind.accessory => _accessory,
      SmartPartKind.custom => _custom,
    };

    final extra = userInstructions?.trim();
    if (extra == null || extra.isEmpty) return base;
    return '$base\nAdditional user requirement: $extra';
  }

  static const _fullBody =
      'Create a clean full-body 3D character reference preserving the source identity and costume. '
      'Front-facing A-pose, centered, both arms separated clearly from the torso and armpits visible, '
      'legs slightly separated, hands visible with fingers separated, feet fully visible, neutral stance. '
      'Do not crop any body part. Keep proportions and costume details accurate. '
      'Plain neutral background, high detail, suitable as a high-quality MetaHuman/body-conform reference.';

  static const _headClean =
      'Create a clean isolated 3D-ready character head from the source identity. '
      'Output only the bald head, ears, and upper neck. Front-facing, centered, symmetrical, neutral expression, '
      'eyes open, mouth closed. Preserve facial identity, skin tone, facial proportions, wounds, scars, and skin detail. '
      'Remove all hair, eyelashes, headwear, clothing, shoulders, torso, jewelry, and detachable accessories. '
      'Plain neutral background, clean silhouette, high detail, suitable for MetaHuman facial modeling and rigging.';

  static const _hairHeadwear =
      'Create only the character hair and/or headwear as a separate clean asset reference. '
      'Preserve the exact silhouette, length, volume, material, damage, color, and placement from the source. '
      'Do not include the face, skin, torso, or clothing except minimal overlap required to understand attachment. '
      'Centered on a plain neutral background, suitable for separate 3D asset creation.';

  static const _faceOnly =
      'Create a front-facing face-only reference preserving the exact identity, facial proportions, skin tone, '
      'eyes, nose, lips, scars, wounds, and fine facial details. Neutral expression, eyes open, mouth closed. '
      'Remove hair, headwear, clothing, shoulders, and background distractions. Plain neutral background.';

  static const _torso =
      'Create an isolated front torso reference from the base of the neck to the hips. '
      'Preserve body proportions, clothing, material, stains, tears, wounds, and silhouette. '
      'Exclude the head, hands, forearms, legs, and unrelated accessories. Front-facing, centered, neutral background.';

  static const _rightArm =
      'Create only the complete right arm as an isolated 3D-ready reference, from shoulder attachment to fingertips. '
      'Keep the arm separated from the torso, preserve anatomy, clothing, damage, bandages, gloves, and proportions. '
      'Fingers clearly separated, neutral background, no left arm or torso.';

  static const _leftArm =
      'Create only the complete left arm as an isolated 3D-ready reference, from shoulder attachment to fingertips. '
      'Keep the arm separated from the torso, preserve anatomy, clothing, damage, bandages, gloves, and proportions. '
      'Fingers clearly separated, neutral background, no right arm or torso.';

  static const _rightHand =
      'Create only the right hand as a clean isolated reference. Open relaxed hand, fingers clearly separated, '
      'front/three-quarter readable angle, preserve skin, wounds, nails, gloves, jewelry, and proportions. '
      'No forearm beyond a short wrist connection, plain neutral background.';

  static const _leftHand =
      'Create only the left hand as a clean isolated reference. Open relaxed hand, fingers clearly separated, '
      'front/three-quarter readable angle, preserve skin, wounds, nails, gloves, jewelry, and proportions. '
      'No forearm beyond a short wrist connection, plain neutral background.';

  static const _rightLeg =
      'Create only the complete right leg as an isolated reference from hip attachment to foot. '
      'Preserve anatomy, clothing, damage, footwear, and proportions. Straight readable pose, neutral background, '
      'no left leg or torso beyond minimal hip attachment.';

  static const _leftLeg =
      'Create only the complete left leg as an isolated reference from hip attachment to foot. '
      'Preserve anatomy, clothing, damage, footwear, and proportions. Straight readable pose, neutral background, '
      'no right leg or torso beyond minimal hip attachment.';

  static const _feet =
      'Create a clear isolated reference of the feet and footwear. Preserve exact shoe shape, materials, wear, '
      'laces, stains, damage, skin visibility, and proportions. Both feet separated and fully visible, neutral background.';

  static const _accessory =
      'Create only the selected accessory as a separate clean 3D asset reference. '
      'Preserve its exact shape, material, color, damage, scale, and attachment details. '
      'Exclude the character body except the minimum attachment context. Plain neutral background.';

  static const _custom =
      'Create only the requested selected part as a clean isolated 3D-ready asset reference. '
      'Preserve identity-relevant shape, materials, damage, colors, and proportions from the source. '
      'Exclude unrelated body parts and background distractions. Plain neutral background.';
}

abstract final class PartKindClassifier {
  static SmartPartKind classify(String label) {
    final value = label.trim().toLowerCase();

    if (_hasAny(value, const ['full body', 'body', 'جسم كامل', 'الجسم'])) {
      return SmartPartKind.fullBodyAPose;
    }
    if (_hasAny(value, const ['head', 'metahuman head', 'رأس', 'راس'])) {
      return SmartPartKind.headClean;
    }
    if (_hasAny(value, const ['hair', 'headwear', 'hat', 'cap', 'شعر', 'قبعة', 'غطاء'])) {
      return SmartPartKind.hairHeadwear;
    }
    if (_hasAny(value, const ['face', 'وجه'])) return SmartPartKind.faceOnly;
    if (_hasAny(value, const ['torso', 'chest', 'جذع', 'صدر'])) {
      return SmartPartKind.torsoFront;
    }
    if (_hasAny(value, const ['right arm', 'ذراع يمين', 'الذراع اليمنى'])) {
      return SmartPartKind.rightArmDetached;
    }
    if (_hasAny(value, const ['left arm', 'ذراع يسار', 'الذراع اليسرى'])) {
      return SmartPartKind.leftArmDetached;
    }
    if (_hasAny(value, const ['right hand', 'يد يمين', 'اليد اليمنى'])) {
      return SmartPartKind.rightHandOpen;
    }
    if (_hasAny(value, const ['left hand', 'يد يسار', 'اليد اليسرى'])) {
      return SmartPartKind.leftHandOpen;
    }
    if (_hasAny(value, const ['right leg', 'ساق يمين', 'الرجل اليمنى'])) {
      return SmartPartKind.rightLegDetached;
    }
    if (_hasAny(value, const ['left leg', 'ساق يسار', 'الرجل اليسرى'])) {
      return SmartPartKind.leftLegDetached;
    }
    if (_hasAny(value, const ['foot', 'feet', 'shoe', 'shoes', 'قدم', 'حذاء', 'أحذية'])) {
      return SmartPartKind.feetShoes;
    }
    if (_hasAny(value, const ['accessory', 'accessories', 'اكسسوار', 'إكسسوار', 'ملحق'])) {
      return SmartPartKind.accessory;
    }
    return SmartPartKind.custom;
  }

  static bool _hasAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }
}
