import 'package:flutter/material.dart';

import '../../domain/smart_parts/smart_part.dart';

final class SmartPartPlannerPanel extends StatefulWidget {
  const SmartPartPlannerPanel({
    super.key,
    required this.analysis,
    required this.loading,
    required this.enabled,
    required this.onAnalyze,
    required this.onApply,
  });

  final ReferenceAnalysis? analysis;
  final bool loading;
  final bool enabled;
  final VoidCallback onAnalyze;
  final ValueChanged<List<SuggestedPart>> onApply;

  @override
  State<SmartPartPlannerPanel> createState() => _SmartPartPlannerPanelState();
}

final class _SmartPartPlannerPanelState extends State<SmartPartPlannerPanel> {
  final Map<String, bool> _enabled = {};

  @override
  void initState() {
    super.initState();
    _syncAnalysis();
  }

  @override
  void didUpdateWidget(covariant SmartPartPlannerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.analysis, widget.analysis)) {
      _syncAnalysis();
    }
  }

  void _syncAnalysis() {
    _enabled.clear();
    final analysis = widget.analysis;
    if (analysis == null) return;
    for (final suggestion in analysis.suggestions) {
      _enabled[suggestion.key] = suggestion.enabled;
    }
  }

  void _apply() {
    final analysis = widget.analysis;
    if (analysis == null) return;
    widget.onApply(
      analysis.suggestions
          .map(
            (suggestion) => suggestion.copyWith(
              enabled: _enabled[suggestion.key] ?? suggestion.enabled,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'التقسيم الذكي',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'يحلل الوجه ووضعية الجسم محليًا على الهاتف، ثم يقترح أجزاء وSmart Prompts مناسبة لمسار 3D/MetaHuman.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.enabled && !widget.loading
                  ? widget.onAnalyze
                  : null,
              icon: widget.loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.center_focus_strong),
              label: Text(
                widget.loading
                    ? 'جارٍ تحليل الصورة…'
                    : 'تحليل الصورة واقتراح الأجزاء',
              ),
            ),
            if (analysis != null) ...[
              const SizedBox(height: 12),
              Text(analysis.summary),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(
                    label: Text(
                      analysis.hasFace ? 'وجه مكتشف' : 'لا يوجد وجه مؤكد',
                    ),
                  ),
                  Chip(
                    label: Text(
                      analysis.isFullBody
                          ? 'Full Body'
                          : analysis.hasUpperBody
                              ? 'Upper Body'
                              : 'Portrait/Partial',
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              ...analysis.suggestions.map(
                (part) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _enabled[part.key] ?? part.enabled,
                  onChanged: (value) {
                    setState(() => _enabled[part.key] = value ?? false);
                  },
                  secondary: Icon(
                    part.region == null
                        ? Icons.auto_awesome
                        : Icons.crop_free,
                  ),
                  title: Text(part.label),
                  subtitle: Text(
                    part.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _apply,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('تطبيق الاقتراحات على قائمة الأجزاء'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
