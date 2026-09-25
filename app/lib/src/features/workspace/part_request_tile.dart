import 'package:flutter/material.dart';

import 'generation_state.dart';

final class PartRequestTile extends StatelessWidget {
  const PartRequestTile({
    super.key,
    required this.label,
    required this.promptFragment,
    required this.enabled,
    required this.onEnabledChanged,
    this.generationState,
    this.onRetry,
    this.onGenerate,
    this.onEdit,
  });

  final String label;
  final String promptFragment;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final GenerationPartState? generationState;
  final VoidCallback? onRetry;
  final VoidCallback? onGenerate;
  final VoidCallback? onEdit;

  String _statusLabel(GenerationPartState state) {
    return switch (state.phase) {
      GenerationPartPhase.submitting => 'جارٍ إرسال المهمة…',
      GenerationPartPhase.queued => 'في قائمة الانتظار',
      GenerationPartPhase.running => 'جارٍ التوليد',
      GenerationPartPhase.success => 'اكتمل',
      GenerationPartPhase.failed => 'فشل',
      GenerationPartPhase.cancelled => 'أُلغي',
    };
  }

  double _progress(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final state = generationState;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onEnabledChanged,
            title: Text(label),
            subtitle: Text(
              promptFragment,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            secondary: const Icon(Icons.drag_handle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل Prompt'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: enabled && state?.isActive != true
                      ? onGenerate
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('توليد هذا الجزء'),
                ),
              ],
            ),
          ),
          if (state != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_statusLabel(state))),
                      if (state.isFailure && onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة'),
                        ),
                    ],
                  ),
                  if (state.isActive &&
                      state.phase != GenerationPartPhase.submitting)
                    LinearProgressIndicator(
                      value: _progress(state.progress),
                    ),
                  if (state.errorCode != null && state.isFailure)
                    Text(
                      'الخطأ: ${state.errorCode}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
