import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/templates/template_part.dart';
import 'generation_state.dart';
import 'part_request_tile.dart';

final class EditableTemplatePart {
  const EditableTemplatePart({
    required this.key,
    required this.label,
    required this.promptFragment,
    required this.enabled,
  });

  final String key;
  final String label;
  final String promptFragment;
  final bool enabled;

  EditableTemplatePart copyWith({bool? enabled}) {
    return EditableTemplatePart(
      key: key,
      label: label,
      promptFragment: promptFragment,
      enabled: enabled ?? this.enabled,
    );
  }
}

final class TemplateEditorController extends ChangeNotifier {
  TemplateEditorController({
    required List<TemplatePart> initialParts,
    String Function()? newKey,
  }) : _newKey = newKey ?? (() => const Uuid().v4()) {
    final ordered = [...initialParts]
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    _parts.addAll(
      ordered.map(
        (part) => EditableTemplatePart(
          key: part.key,
          label: part.label,
          promptFragment: part.promptFragment,
          enabled: part.enabledByDefault,
        ),
      ),
    );
  }

  final String Function() _newKey;
  final List<EditableTemplatePart> _parts = [];

  List<EditableTemplatePart> get parts => List.unmodifiable(_parts);

  void setEnabled(String key, bool enabled) {
    final index = _parts.indexWhere((part) => part.key == key);
    if (index < 0) return;
    _parts[index] = _parts[index].copyWith(enabled: enabled);
    notifyListeners();
  }

  bool addCustomPart({
    required String label,
    required String promptFragment,
  }) {
    final normalizedLabel = label.trim();
    final normalizedPrompt = promptFragment.trim();
    if (normalizedLabel.isEmpty || normalizedPrompt.isEmpty) return false;

    _parts.add(
      EditableTemplatePart(
        key: _newKey(),
        label: normalizedLabel,
        promptFragment: normalizedPrompt,
        enabled: true,
      ),
    );
    notifyListeners();
    return true;
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _parts.length ||
        newIndex < 0 ||
        newIndex > _parts.length) {
      return;
    }

    final item = _parts.removeAt(oldIndex);
    final targetIndex = newIndex > _parts.length ? _parts.length : newIndex;
    _parts.insert(targetIndex, item);
    notifyListeners();
  }
}

final class TemplateEditor extends StatefulWidget {
  const TemplateEditor({
    super.key,
    required this.controller,
    this.generationState = const {},
    this.onRetry,
  });

  final TemplateEditorController controller;
  final Map<String, GenerationPartState> generationState;
  final ValueChanged<String>? onRetry;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

final class _TemplateEditorState extends State<TemplateEditor> {
  final _labelController = TextEditingController();
  final _promptController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant TemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _labelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _addPart() {
    final added = widget.controller.addCustomPart(
      label: _labelController.text,
      promptFragment: _promptController.text,
    );
    if (!added) {
      setState(() => _error = 'اكتب اسم الجزء ووصفه.');
      return;
    }

    _labelController.clear();
    _promptController.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الأجزاء المطلوبة',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.controller.parts.length,
          onReorderItem: widget.controller.reorder,
          itemBuilder: (context, index) {
            final part = widget.controller.parts[index];
            return PartRequestTile(
              key: ValueKey(part.key),
              label: part.label,
              promptFragment: part.promptFragment,
              enabled: part.enabled,
              generationState: widget.generationState[part.key],
              onRetry: widget.onRetry == null
                  ? null
                  : () => widget.onRetry!(part.key),
              onEnabledChanged: (enabled) {
                widget.controller.setEnabled(part.key, enabled);
              },
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            labelText: 'جزء مخصص',
            hintText: 'مثال: ضمادات الرأس',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'تعليمات الجزء',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addPart,
          icon: const Icon(Icons.add),
          label: const Text('إضافة جزء'),
        ),
      ],
    );
  }
}
