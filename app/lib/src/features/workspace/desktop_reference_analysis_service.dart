import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/smart_parts/smart_part.dart';
import 'part_prompt_profiles.dart';
import 'reference_analysis_service.dart';

/// Windows fallback: provides editable part templates, not ML detections.
///
/// Google ML Kit Flutter face/pose detection has no Windows implementation.
/// Do not claim that a face, pose, or region was detected on desktop.
final class DesktopReferenceAnalysisService implements ReferenceAnalysisService {
  const DesktopReferenceAnalysisService();

  @override
  Future<ReferenceAnalysis> analyze(Uint8List bytes) async {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw StateError('Reference image could not be decoded.');
    }
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw StateError('Reference image could not be decoded.');
    }

    const templates = <(String, String, SmartPartKind)>[
      ('full_body_apose', 'جسم كامل A-Pose', SmartPartKind.fullBodyAPose),
      ('head', 'رأس نظيف / أصلع', SmartPartKind.headClean),
      ('hair_headwear', 'شعر / غطاء رأس', SmartPartKind.hairHeadwear),
      ('torso', 'الجذع', SmartPartKind.torsoFront),
      ('clothing_outfit', 'الملابس / الزي', SmartPartKind.clothingOutfit),
      ('right_arm', 'الذراع اليمنى', SmartPartKind.rightArmDetached),
      ('left_arm', 'الذراع اليسرى', SmartPartKind.leftArmDetached),
      ('right_leg', 'الساق اليمنى', SmartPartKind.rightLegDetached),
      ('left_leg', 'الساق اليسرى', SmartPartKind.leftLegDetached),
      ('feet_shoes', 'الأحذية / القدم', SmartPartKind.feetShoes),
    ];

    return ReferenceAnalysis(
      hasFace: false,
      hasPose: false,
      isFullBody: false,
      hasUpperBody: false,
      suggestions: [
        for (final (key, label, kind) in templates)
          SuggestedPart(
            key: key,
            label: label,
            kind: kind,
            prompt: PartPromptProfiles.build(kind),
            enabled: false,
          ),
      ],
    );
  }
}
