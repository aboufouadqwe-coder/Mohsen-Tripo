import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/generation/model_generation_settings.dart';

final class ModelGenerationSettingsPanel extends StatefulWidget {
  const ModelGenerationSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.disabled = false,
  });

  final ModelGenerationSettings settings;
  final ValueChanged<ModelGenerationSettings> onChanged;
  final bool disabled;

  @override
  State<ModelGenerationSettingsPanel> createState() =>
      _ModelGenerationSettingsPanelState();
}

final class _ModelGenerationSettingsPanelState
    extends State<ModelGenerationSettingsPanel> {
  late final TextEditingController _faceLimitController;

  @override
  void initState() {
    super.initState();
    _faceLimitController = TextEditingController(
      text: _faceText(widget.settings),
    );
  }

  @override
  void didUpdateWidget(covariant ModelGenerationSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _faceText(widget.settings);
    if (_faceLimitController.text != next) {
      _faceLimitController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _faceLimitController.dispose();
    super.dispose();
  }

  String _faceText(ModelGenerationSettings settings) {
    if (settings.topology == ModelTopology.adaptive) return '';
    return (settings.validatedFaceLimit ??
            ModelGenerationSettings.defaultFaceLimitFor(
              settings.preset,
              settings.topology,
            ))
        .toString();
  }

  void _setPreset(ModelQualityPreset preset) {
    final topology = widget.settings.topology;
    final next = widget.settings.copyWith(
      preset: preset,
      faceLimit: topology == ModelTopology.adaptive
          ? null
          : ModelGenerationSettings.defaultFaceLimitFor(preset, topology),
      clearFaceLimit: topology == ModelTopology.adaptive,
    );
    widget.onChanged(next);
  }

  void _setTopology(ModelTopology topology) {
    final next = widget.settings.copyWith(
      topology: topology,
      faceLimit: topology == ModelTopology.adaptive
          ? null
          : ModelGenerationSettings.defaultFaceLimitFor(
              widget.settings.preset,
              topology,
            ),
      clearFaceLimit: topology == ModelTopology.adaptive,
    );
    widget.onChanged(next);
  }

  void _setFaceLimit(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    widget.onChanged(widget.settings.copyWith(faceLimit: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final disabled = widget.disabled;
    final adaptive = settings.topology == ModelTopology.adaptive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إعدادات المجسم 3D',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Text(
              'الجودة',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ModelQualityPreset>(
              segments: const [
                ButtonSegment(
                  value: ModelQualityPreset.lowPoly,
                  label: Text('Low Poly'),
                ),
                ButtonSegment(
                  value: ModelQualityPreset.standard,
                  label: Text('Standard'),
                ),
                ButtonSegment(
                  value: ModelQualityPreset.high,
                  label: Text('High'),
                ),
              ],
              selected: {settings.preset},
              onSelectionChanged: disabled
                  ? null
                  : (selection) => _setPreset(selection.single),
            ),
            const SizedBox(height: 16),
            Text(
              'نوع المضلعات',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ModelTopology>(
              segments: const [
                ButtonSegment(
                  value: ModelTopology.adaptive,
                  label: Text('تلقائي'),
                ),
                ButtonSegment(
                  value: ModelTopology.triangles,
                  label: Text('مثلثات'),
                ),
                ButtonSegment(
                  value: ModelTopology.quads,
                  label: Text('مربعات'),
                ),
              ],
              selected: {settings.topology},
              onSelectionChanged: disabled
                  ? null
                  : (selection) => _setTopology(selection.single),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('model-face-limit'),
              controller: _faceLimitController,
              enabled: !disabled && !adaptive,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: _setFaceLimit,
              decoration: InputDecoration(
                labelText: adaptive
                    ? 'عدد المضلعات: تلقائي'
                    : 'عدد المضلعات',
                helperText: adaptive
                    ? 'سيحدد Tripo العدد تلقائيًا.'
                    : 'المسموح حاليًا: ${settings.minFaceLimit} – ${settings.maxFaceLimit}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Texture'),
              subtitle: const Text('إنشاء خامة للمجسم'),
              value: settings.texture,
              onChanged: disabled
                  ? null
                  : (value) {
                      widget.onChanged(
                        settings.copyWith(
                          texture: value,
                          pbr: value ? settings.pbr : false,
                        ),
                      );
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PBR'),
              subtitle: const Text('Metallic / Roughness / Normal'),
              value: settings.pbr && settings.texture,
              onChanged: disabled || !settings.texture
                  ? null
                  : (value) {
                      widget.onChanged(settings.copyWith(pbr: value));
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto Fix'),
              subtitle: const Text('تحسين الصورة قبل إنشاء 3D'),
              value: settings.enableImageAutofix,
              onChanged: disabled
                  ? null
                  : (value) {
                      widget.onChanged(
                        settings.copyWith(enableImageAutofix: value),
                      );
                    },
            ),
            if (settings.mayProduceFbx) ...[
              const SizedBox(height: 8),
              Text(
                'تنبيه: خيار المربعات قد ينتج ملف FBX. يمكن تنزيله، لكن عارض GLB داخل التطبيق لن يعرض FBX.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
