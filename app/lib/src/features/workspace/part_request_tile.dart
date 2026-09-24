import 'package:flutter/material.dart';

final class PartRequestTile extends StatelessWidget {
  const PartRequestTile({
    super.key,
    required this.label,
    required this.promptFragment,
    required this.enabled,
    required this.onEnabledChanged,
  });

  final String label;
  final String promptFragment;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
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
    );
  }
}
