import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/smart_parts/smart_part.dart';
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
    this.promptMode = PartPromptMode.exact,
    this.hasRegion = false,
    this.onSelectRegion,
    this.onRebuildSmartPrompt,
  });

  final String label;
  final String promptFragment;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final GenerationPartState? generationState;
  final VoidCallback? onRetry;
  final VoidCallback? onGenerate;
  final VoidCallback? onEdit;
  final PartPromptMode promptMode;
  final bool hasRegion;
  final VoidCallback? onSelectRegion;
  final VoidCallback? onRebuildSmartPrompt;

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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(
                    promptMode == PartPromptMode.smart
                        ? Icons.auto_awesome
                        : Icons.text_fields,
                    size: 16,
                  ),
                  label: Text(
                    promptMode == PartPromptMode.smart
                        ? 'Smart Prompt'
                        : 'Exact Prompt',
                  ),
                ),
                if (hasRegion)
                  const Chip(
                    avatar: Icon(Icons.crop, size: 16),
                    label: Text('منطقة محددة'),
                  ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل Prompt'),
                ),
                if (promptMode == PartPromptMode.smart &&
                    onRebuildSmartPrompt != null)
                  TextButton.icon(
                    onPressed: onRebuildSmartPrompt,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('إعادة بناء'),
                  ),
                if (onSelectRegion != null)
                  TextButton.icon(
                    onPressed: onSelectRegion,
                    icon: const Icon(Icons.crop_free),
                    label: Text(hasRegion ? 'تعديل المنطقة' : 'تحديد منطقة'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: enabled && state?.isActive != true
                    ? onGenerate
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('توليد هذا الجزء'),
              ),
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
                  _GenerationElapsedTime(state: state),
                  if (state.isActive &&
                      state.phase != GenerationPartPhase.submitting) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _progress(state.progress),
                    ),
                  ],
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


final class _GenerationElapsedTime extends StatefulWidget {
  const _GenerationElapsedTime({
    required this.state,
  });

  final GenerationPartState state;

  @override
  State<_GenerationElapsedTime> createState() =>
      _GenerationElapsedTimeState();
}

final class _GenerationElapsedTimeState
    extends State<_GenerationElapsedTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _GenerationElapsedTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.state.isActive || widget.state.startedAt == null) return;

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  String _format(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.state.elapsed;
    if (elapsed == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        widget.state.isActive
            ? 'الوقت المنقضي: ${_format(elapsed)}'
            : 'مدة التوليد: ${_format(elapsed)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
