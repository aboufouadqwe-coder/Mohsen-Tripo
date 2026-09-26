import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../domain/smart_parts/smart_part.dart';
import 'part_prompt_profiles.dart';

abstract interface class ReferenceAnalysisService {
  Future<ReferenceAnalysis> analyze(Uint8List bytes);
}

final class MlKitReferenceAnalysisService implements ReferenceAnalysisService {
  const MlKitReferenceAnalysisService();

  @override
  Future<ReferenceAnalysis> analyze(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw StateError('Reference image could not be decoded.');
    }

    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/mohsen-tripo-analysis-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(
      img.encodeJpg(decoded, quality: 94),
      flush: true,
    );

    final poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode: PoseDetectionMode.single,
      ),
    );
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableContours: true,
      ),
    );

    try {
      final input = InputImage.fromFilePath(file.path);
      final poses = await poseDetector.processImage(input);
      final faces = await faceDetector.processImage(input);

      final pose = poses.isEmpty ? null : poses.first;
      final face = faces.isEmpty ? null : faces.first;
      return _buildAnalysis(
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
        pose: pose,
        face: face,
      );
    } finally {
      await poseDetector.close();
      await faceDetector.close();
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  ReferenceAnalysis _buildAnalysis({
    required double width,
    required double height,
    required Pose? pose,
    required Face? face,
  }) {
    final hasFace = face != null;
    final hasPose = pose != null;

    bool visible(PoseLandmarkType type, [double threshold = 0.45]) {
      final landmark = pose?.landmarks[type];
      return landmark != null && landmark.likelihood >= threshold;
    }

    final shoulders = visible(PoseLandmarkType.leftShoulder) &&
        visible(PoseLandmarkType.rightShoulder);
    final hips = visible(PoseLandmarkType.leftHip) &&
        visible(PoseLandmarkType.rightHip);
    final knees = visible(PoseLandmarkType.leftKnee) &&
        visible(PoseLandmarkType.rightKnee);
    final ankles = visible(PoseLandmarkType.leftAnkle) &&
        visible(PoseLandmarkType.rightAnkle);
    final wrists = visible(PoseLandmarkType.leftWrist) &&
        visible(PoseLandmarkType.rightWrist);

    final isFullBody = shoulders && hips && knees && ankles;
    final hasUpperBody = shoulders && (hips || wrists);

    final suggestions = <SuggestedPart>[];

    NormalizedRegion? poseRegion(
      List<PoseLandmarkType> types, {
      double padding = 0.12,
    }) {
      final points = <math.Point<double>>[];
      for (final type in types) {
        final landmark = pose?.landmarks[type];
        if (landmark != null && landmark.likelihood >= 0.35) {
          points.add(math.Point(landmark.x, landmark.y));
        }
      }
      if (points.length < 2) return null;
      return _regionFromPoints(
        points,
        width: width,
        height: height,
        padding: padding,
      );
    }

    NormalizedRegion? faceRegion() {
      if (face == null) return null;
      final rect = face.boundingBox;
      final horizontalPad = rect.width * 0.28;
      final topPad = rect.height * 0.22;
      final bottomPad = rect.height * 0.48;
      return _normalizeRect(
        left: rect.left - horizontalPad,
        top: rect.top - topPad,
        right: rect.right + horizontalPad,
        bottom: rect.bottom + bottomPad,
        width: width,
        height: height,
      );
    }

    if (isFullBody) {
      final allVisible = pose!.landmarks.values
          .where((landmark) => landmark.likelihood >= 0.35)
          .map((landmark) => math.Point(landmark.x, landmark.y))
          .toList(growable: false);
      suggestions.add(
        SuggestedPart(
          key: 'full_body_apose',
          label: 'Full Body A-Pose',
          kind: SmartPartKind.fullBodyAPose,
          prompt: PartPromptProfiles.build(SmartPartKind.fullBodyAPose),
          region: _regionFromPoints(
            allVisible,
            width: width,
            height: height,
            padding: 0.1,
          ),
        ),
      );
    }

    final headRegion = faceRegion() ??
        poseRegion(
          const [
            PoseLandmarkType.leftEar,
            PoseLandmarkType.rightEar,
            PoseLandmarkType.leftEye,
            PoseLandmarkType.rightEye,
            PoseLandmarkType.nose,
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.rightShoulder,
          ],
          padding: 0.18,
        );

    if (hasFace || headRegion != null) {
      suggestions.add(
        SuggestedPart(
          key: 'head',
          label: 'Head Clean / Bald',
          kind: SmartPartKind.headClean,
          prompt: PartPromptProfiles.build(SmartPartKind.headClean),
          region: headRegion,
        ),
      );
      suggestions.add(
        SuggestedPart(
          key: 'hair_headwear',
          label: 'Hair / Headwear',
          kind: SmartPartKind.hairHeadwear,
          prompt: PartPromptProfiles.build(SmartPartKind.hairHeadwear),
          enabled: false,
          region: headRegion,
        ),
      );
      if (!isFullBody && !hasUpperBody) {
        suggestions.add(
          SuggestedPart(
            key: 'face_only',
            label: 'Face Only',
            kind: SmartPartKind.faceOnly,
            prompt: PartPromptProfiles.build(SmartPartKind.faceOnly),
            enabled: false,
            region: headRegion,
          ),
        );
      }
    }

    if (hasUpperBody || isFullBody) {
      suggestions.add(
        SuggestedPart(
          key: 'torso',
          label: 'Torso',
          kind: SmartPartKind.torsoFront,
          prompt: PartPromptProfiles.build(SmartPartKind.torsoFront),
          region: poseRegion(
            const [
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.rightHip,
            ],
            padding: 0.16,
          ),
        ),
      );

      final clothingRegion = poseRegion(
        const [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.leftAnkle,
          PoseLandmarkType.rightAnkle,
        ],
        padding: 0.18,
      );
      if (clothingRegion != null) {
        suggestions.add(
          SuggestedPart(
            key: 'clothing_outfit',
            label: 'Clothing / Outfit',
            kind: SmartPartKind.accessory,
            prompt: PartPromptProfiles.clothingOutfit,
            region: clothingRegion,
          ),
        );
      }

      _addLimbSuggestions(suggestions, poseRegion);
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        SuggestedPart(
          key: 'head',
          label: 'Head Clean / Bald',
          kind: SmartPartKind.headClean,
          prompt: PartPromptProfiles.build(SmartPartKind.headClean),
          enabled: false,
        ),
      );
    }

    return ReferenceAnalysis(
      hasFace: hasFace,
      hasPose: hasPose,
      isFullBody: isFullBody,
      hasUpperBody: hasUpperBody,
      suggestions: suggestions,
    );
  }

  void _addLimbSuggestions(
    List<SuggestedPart> suggestions,
    NormalizedRegion? Function(
      List<PoseLandmarkType> types, {
      double padding,
    }) region,
  ) {
    void add({
      required String key,
      required String label,
      required SmartPartKind kind,
      required List<PoseLandmarkType> points,
      double padding = 0.18,
    }) {
      final detected = region(points, padding: padding);
      if (detected == null) return;
      suggestions.add(
        SuggestedPart(
          key: key,
          label: label,
          kind: kind,
          prompt: PartPromptProfiles.build(kind),
          region: detected,
        ),
      );
    }

    add(
      key: 'right_arm',
      label: 'Right Arm',
      kind: SmartPartKind.rightArmDetached,
      points: const [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.rightIndex,
      ],
    );
    add(
      key: 'left_arm',
      label: 'Left Arm',
      kind: SmartPartKind.leftArmDetached,
      points: const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.leftIndex,
      ],
    );
    add(
      key: 'right_hand',
      label: 'Right Hand',
      kind: SmartPartKind.rightHandOpen,
      points: const [
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.rightThumb,
        PoseLandmarkType.rightIndex,
        PoseLandmarkType.rightPinky,
      ],
      padding: 0.28,
    );
    add(
      key: 'left_hand',
      label: 'Left Hand',
      kind: SmartPartKind.leftHandOpen,
      points: const [
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.leftThumb,
        PoseLandmarkType.leftIndex,
        PoseLandmarkType.leftPinky,
      ],
      padding: 0.28,
    );
    add(
      key: 'right_leg',
      label: 'Right Leg',
      kind: SmartPartKind.rightLegDetached,
      points: const [
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle,
        PoseLandmarkType.rightFootIndex,
      ],
    );
    add(
      key: 'left_leg',
      label: 'Left Leg',
      kind: SmartPartKind.leftLegDetached,
      points: const [
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.leftFootIndex,
      ],
    );

    final feet = region(
      const [
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
        PoseLandmarkType.leftHeel,
        PoseLandmarkType.rightHeel,
        PoseLandmarkType.leftFootIndex,
        PoseLandmarkType.rightFootIndex,
      ],
      padding: 0.25,
    );
    if (feet != null) {
      suggestions.add(
        SuggestedPart(
          key: 'feet_shoes',
          label: 'Feet / Shoes',
          kind: SmartPartKind.feetShoes,
          prompt: PartPromptProfiles.build(SmartPartKind.feetShoes),
          region: feet,
        ),
      );
    }
  }

  NormalizedRegion _regionFromPoints(
    List<math.Point<double>> points, {
    required double width,
    required double height,
    required double padding,
  }) {
    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }

    final boxWidth = math.max(1.0, maxX - minX);
    final boxHeight = math.max(1.0, maxY - minY);
    return _normalizeRect(
      left: minX - boxWidth * padding,
      top: minY - boxHeight * padding,
      right: maxX + boxWidth * padding,
      bottom: maxY + boxHeight * padding,
      width: width,
      height: height,
    );
  }

  NormalizedRegion _normalizeRect({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double width,
    required double height,
  }) {
    return NormalizedRegion(
      left: left / width,
      top: top / height,
      right: right / width,
      bottom: bottom / height,
    ).clamp();
  }
}
