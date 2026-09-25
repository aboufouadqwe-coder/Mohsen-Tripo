import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/generation/model_generation_settings.dart';
import 'package:mohsen_tripo/src/features/results/model_generation_settings_panel.dart';

void main() {
  testWidgets('3d settings panel updates preset topology and face count',
      (tester) async {
    var settings = const ModelGenerationSettings();

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: ModelGenerationSettingsPanel(
                settings: settings,
                onChanged: (next) {
                  setState(() => settings = next);
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Low Poly'));
    await tester.pump();
    expect(settings.preset, ModelQualityPreset.lowPoly);

    await tester.tap(find.text('مربعات'));
    await tester.pump();
    expect(settings.topology, ModelTopology.quads);
    expect(settings.faceLimit, 10000);

    await tester.enterText(
      find.byKey(const Key('model-face-limit')),
      '12000',
    );
    await tester.pump();
    expect(settings.faceLimit, 12000);
    expect(settings.maxFaceLimit, 25000);
    expect(find.textContaining('FBX'), findsOneWidget);
  });
}
