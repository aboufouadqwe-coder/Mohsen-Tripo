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
      SmartPartKind.clothingOutfit => clothingOutfit,
      SmartPartKind.accessory => _accessory,
      SmartPartKind.custom => _custom,
    };

    final extra = userInstructions?.trim();
    if (extra == null || extra.isEmpty) return base;
    return '$base\nAdditional user requirement: $extra';
  }

  static const _fullBody =
      'Create a clean full-body BASE ANATOMY reference for MetaHuman body conforming. '
      'Front-facing A-pose, centered, arms clearly separated from the torso with visible armpit gaps, '
      'legs slightly separated, hands visible with every finger separated, feet fully visible. '
      'Remove all clothing, underwear, shoes, gloves, bandages/wraps, jewelry, hair, headwear, and detachable accessories. '
      'Preserve body proportions, silhouette, skin tone, and skin-only scars/wounds from the source. '
      'Use a smooth neutral mannequin-like skin surface with no explicit sexual anatomy, no nipples, and no genital detail. '
      'Do not crop any body part. Plain neutral background, high detail, suitable for MetaHuman/body-conform reference.';

  static const _headClean =
      'Create a clean isolated 3D-ready character head from the source identity. '
      'Output only the bald head, ears, and upper neck. Front-facing, centered, symmetrical, neutral expression, '
      'eyes open, mouth closed. Preserve facial identity, skin tone, facial proportions, and skin-only scars/wounds. '
      'Remove all hair, eyelashes, headwear, bandages/wraps, jewelry, clothing, collars, shoulders, torso, and detachable accessories. '
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
      'Create only the BARE base torso anatomy from the base of the neck to the hips. '
      'Remove shirts, gowns, jackets, uniforms, underwear, bandages/wraps, jewelry, and every clothing/accessory layer. '
      'Preserve body proportions, skin tone, silhouette, and skin-only scars/wounds. '
      'Use a smooth neutral mannequin-like skin surface with no explicit sexual anatomy, no nipples, and no genital detail. '
      'Exclude the head, hands, forearms, legs, and unrelated assets. Front-facing, centered, neutral background.';

  static const _rightArm =
      'Create only the complete BARE right arm as an isolated 3D-ready anatomy reference, from shoulder attachment to fingertips. '
      'Remove sleeves, gloves, bandages/wraps, jewelry, and every clothing/accessory layer. '
      'Preserve arm proportions, skin tone, and skin-only scars/wounds. Keep the arm fully separated from the torso. '
      'All fingers clearly separated, neutral background, no left arm or torso.';

  static const _leftArm =
      'Create only the complete BARE left arm as an isolated 3D-ready anatomy reference, from shoulder attachment to fingertips. '
      'Remove sleeves, gloves, bandages/wraps, jewelry, and every clothing/accessory layer. '
      'Preserve arm proportions, skin tone, and skin-only scars/wounds. Keep the arm fully separated from the torso. '
      'All fingers clearly separated, neutral background, no right arm or torso.';

  static const _rightHand =
      'Create only the BARE right hand as a clean isolated anatomy reference with a short wrist connection. '
      'Remove gloves, bandages/wraps, jewelry, sleeves, and accessories. '
      'Open relaxed hand, every finger clearly separated, preserve skin tone, proportions, nails, and skin-only scars/wounds. '
      'No forearm beyond a short wrist connection, plain neutral background.';

  static const _leftHand =
      'Create only the BARE left hand as a clean isolated anatomy reference with a short wrist connection. '
      'Remove gloves, bandages/wraps, jewelry, sleeves, and accessories. '
      'Open relaxed hand, every finger clearly separated, preserve skin tone, proportions, nails, and skin-only scars/wounds. '
      'No forearm beyond a short wrist connection, plain neutral background.';

  static const _rightLeg =
      'Create only the complete BARE right leg as an isolated anatomy reference from hip attachment through the foot. '
      'Remove trousers, skirts, socks, shoes, bandages/wraps, and every clothing/accessory layer. '
      'Preserve leg proportions, skin tone, and skin-only scars/wounds. Straight readable pose, neutral background, '
      'no left leg or torso beyond minimal hip attachment.';

  static const _leftLeg =
      'Create only the complete BARE left leg as an isolated anatomy reference from hip attachment through the foot. '
      'Remove trousers, skirts, socks, shoes, bandages/wraps, and every clothing/accessory layer. '
      'Preserve leg proportions, skin tone, and skin-only scars/wounds. Straight readable pose, neutral background, '
      'no right leg or torso beyond minimal hip attachment.';

  static const _feet =
      'Create only the character footwear/shoes as separate wearable assets. '
      'Do not include feet, leg skin, trousers, socks, or other body geometry. '
      'Preserve exact shoe shape, soles, laces, materials, wear, stains, damage, scale, and left/right proportions. '
      'Both shoes separated and fully visible on a neutral background.';

  static const clothingOutfit =
      'Create only the character clothing/outfit as separate empty wearable geometry. '
      'Include torso and leg garments such as gown, shirt, jacket, uniform, trousers, skirt, or dress when visible. '
      'Do not include skin, body anatomy, head, hands, feet, hair, headwear, shoes, gloves, jewelry, or unrelated accessories. '
      'Preserve exact garment silhouette, sleeves, seams, folds, tears, stains, material, color, damage, and fit from the source. '
      'Plain neutral background, centered and uncropped, suitable for separate 3D clothing creation.';

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
    if (_hasAny(value, const ['hair', 'headwear', 'hat', 'cap', 'شعر', 'قبعة', 'غطاء'])) {
      return SmartPartKind.hairHeadwear;
    }
    if (_hasAny(value, const ['head', 'metahuman head', 'رأس', 'راس'])) {
      return SmartPartKind.headClean;
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
    if (_hasAny(value, const ['clothing', 'outfit', 'clothes', 'ملابس', 'زي', 'ثوب', 'فستان'])) {
      return SmartPartKind.clothingOutfit;
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
