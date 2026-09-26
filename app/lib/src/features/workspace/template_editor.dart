import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/smart_parts/smart_part.dart';
import '../../domain/templates/template_part.dart';
import 'part_prompt_profiles.dart';
import 'generation_state.dart';
import 'part_request_tile.dart';

final class EditableTemplatePart {
  const EditableTemplatePart({
    required this.key,
    required this.label,
    required this.promptFragment,
    required this.enabled,
    required this.kind,
    required this.promptMode,
    this.region,
  });

  final String key;
  final String label;
  final String promptFragment;
  final bool enabled;
  final SmartPartKind kind;
  final PartPromptMode promptMode;
  final NormalizedRegion? region;

  EditableTemplatePart copyWith({
    String? label,
    String? promptFragment,
    bool? enabled,
    SmartPartKind? kind,
    PartPromptMode? promptMode,
    NormalizedRegion? region,
    bool clearRegion = false,
  }) {
    return EditableTemplatePart(
      key: key,
      label: label ?? this.label,
      promptFragment: promptFragment ?? this.promptFragment,
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      promptMode: promptMode ?? this.promptMode,
      region: clearRegion ? null : (region ?? this.region),
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
          kind: PartKindClassifier.classify(part.label),
          promptMode: PartPromptMode.exact,
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

  bool updatePart({
    required String key,
    required String label,
    required String promptFragment,
    PartPromptMode? promptMode,
  }) {
    final index = _parts.indexWhere((part) => part.key == key);
    final normalizedLabel = label.trim();
    if (index < 0 || normalizedLabel.isEmpty) return false;
    final selectedMode = promptMode ?? _parts[index].promptMode;
    var normalizedPrompt = promptFragment.trim();

    final kind = PartKindClassifier.classify(normalizedLabel);
    if (selectedMode == PartPromptMode.smart && normalizedPrompt.isEmpty) {
      normalizedPrompt = PartPromptProfiles.build(kind);
    }
    if (normalizedPrompt.isEmpty) return false;

    _parts[index] = _parts[index].copyWith(
      label: normalizedLabel,
      promptFragment: normalizedPrompt,
      kind: kind,
      promptMode: selectedMode,
    );
    notifyListeners();
    return true;
  }

  bool addCustomPart({
    required String label,
    required String promptFragment,
    PartPromptMode promptMode = PartPromptMode.exact,
    SmartPartKind? kind,
    NormalizedRegion? region,
  }) {
    final normalizedLabel = label.trim();
    var normalizedPrompt = promptFragment.trim();
    if (normalizedLabel.isEmpty) return false;

    final resolvedKind = kind ?? PartKindClassifier.classify(normalizedLabel);
    if (promptMode == PartPromptMode.smart) {
      normalizedPrompt = PartPromptProfiles.build(
        resolvedKind,
        userInstructions:
            normalizedPrompt.isEmpty ? null : normalizedPrompt,
      );
    }
    if (normalizedPrompt.isEmpty) return false;

    _parts.add(
      EditableTemplatePart(
        key: _newKey(),
        label: normalizedLabel,
        promptFragment: normalizedPrompt,
        enabled: true,
        kind: resolvedKind,
        promptMode: promptMode,
        region: region,
      ),
    );
    notifyListeners();
    return true;
  }

  void replaceWithSuggestions(Iterable<SuggestedPart> suggestions) {
    _parts
      ..clear()
      ..addAll(
        suggestions.map(
          (part) => EditableTemplatePart(
            key: part.key,
            label: part.label,
            promptFragment: part.prompt,
            enabled: part.enabled,
            kind: part.kind,
            promptMode: PartPromptMode.smart,
            region: part.region,
          ),
        ),
      );
    notifyListeners();
  }

  void setRegion(String key, NormalizedRegion? region) {
    final index = _parts.indexWhere((part) => part.key == key);
    if (index < 0) return;
    _parts[index] = _parts[index].copyWith(
      region: region,
      clearRegion: region == null,
    );
    notifyListeners();
  }

  void rebuildSmartPrompt(String key) {
    final index = _parts.indexWhere((part) => part.key == key);
    if (index < 0) return;
    final part = _parts[index];
    final kind = PartKindClassifier.classify(part.label);
    _parts[index] = part.copyWith(
      kind: kind,
      promptMode: PartPromptMode.smart,
      promptFragment: PartPromptProfiles.build(kind),
    );
    notifyListeners();
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
    this.onGenerate,
    this.onSelectRegion,
    this.onPickManualRegion,
  });

  final TemplateEditorController controller;
  final Map<String, GenerationPartState> generationState;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onGenerate;
  final Future<void> Function(EditableTemplatePart part)? onSelectRegion;
  final Future<NormalizedRegion?> Function(NormalizedRegion? initialRegion)?
      onPickManualRegion;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

final class _TemplateEditorState extends State<TemplateEditor> {
  final _labelController = TextEditingController();
  final _promptController = TextEditingController();
  PartPromptMode _newPartMode = PartPromptMode.smart;
  SmartPartKind? _newPartKind;
  NormalizedRegion? _newPartRegion;
  String? _error;

  static const _manualSmartKinds = <SmartPartKind>[
    SmartPartKind.fullBodyAPose,
    SmartPartKind.headClean,
    SmartPartKind.hairHeadwear,
    SmartPartKind.faceOnly,
    SmartPartKind.torsoFront,
    SmartPartKind.rightArmDetached,
    SmartPartKind.leftArmDetached,
    SmartPartKind.rightHandOpen,
    SmartPartKind.leftHandOpen,
    SmartPartKind.rightLegDetached,
    SmartPartKind.leftLegDetached,
    SmartPartKind.feetShoes,
    SmartPartKind.clothingOutfit,
    SmartPartKind.accessory,
    SmartPartKind.custom,
  ];

  String _arabicKindLabel(SmartPartKind kind) => switch (kind) {
        SmartPartKind.fullBodyAPose => 'جسم كامل',
        SmartPartKind.headClean => 'رأس',
        SmartPartKind.hairHeadwear => 'شعر / غطاء رأس',
        SmartPartKind.faceOnly => 'وجه',
        SmartPartKind.torsoFront => 'جذع',
        SmartPartKind.rightArmDetached => 'ذراع يمنى',
        SmartPartKind.leftArmDetached => 'ذراع يسرى',
        SmartPartKind.rightHandOpen => 'يد يمنى',
        SmartPartKind.leftHandOpen => 'يد يسرى',
        SmartPartKind.rightLegDetached => 'ساق يمنى',
        SmartPartKind.leftLegDetached => 'ساق يسرى',
        SmartPartKind.feetShoes => 'أحذية / قدم',
        SmartPartKind.clothingOutfit => 'ملابس / زي',
        SmartPartKind.accessory => 'إكسسوار',
        SmartPartKind.custom => 'جزء آخر',
      };

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

  Future<void> _editPart(EditableTemplatePart part) async {
    final labelController = TextEditingController(text: part.label);
    final promptController = TextEditingController(text: part.promptFragment);
    var mode = part.promptMode;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الجزء والـPrompt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<PartPromptMode>(
                  segments: const [
                    ButtonSegment(
                      value: PartPromptMode.smart,
                      icon: Icon(Icons.auto_awesome),
                      label: Text('Smart'),
                    ),
                    ButtonSegment(
                      value: PartPromptMode.exact,
                      icon: Icon(Icons.text_fields),
                      label: Text('Exact'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    setDialogState(() => mode = selection.single);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الجزء',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (mode == PartPromptMode.smart)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        final kind = PartKindClassifier.classify(
                          labelController.text,
                        );
                        promptController.text =
                            PartPromptProfiles.build(kind);
                      },
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('بناء Smart Prompt من الاسم'),
                    ),
                  ),
                TextField(
                  controller: promptController,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: mode == PartPromptMode.smart
                        ? 'Smart Prompt — قابل للتعديل'
                        : 'Exact Prompt — سيُرسل كما كتبته',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave == true) {
      widget.controller.updatePart(
        key: part.key,
        label: labelController.text,
        promptFragment: promptController.text,
        promptMode: mode,
      );
    }

    labelController.dispose();
    promptController.dispose();
  }

  Future<void> _pickManualRegion() async {
    final picker = widget.onPickManualRegion;
    if (picker == null) {
      setState(() => _error = 'اختر صورة مرجعية أولًا.');
      return;
    }

    final region = await picker(_newPartRegion);
    if (!mounted || region == null) return;

    setState(() {
      _newPartRegion = region;
      _error = null;
    });
  }

  void _selectManualKind(SmartPartKind kind) {
    setState(() {
      _newPartKind = kind;
      _labelController.text = _arabicKindLabel(kind);
      _error = null;
    });
  }

  void _addPart() {
    if (_newPartRegion == null) {
      setState(() => _error = 'حدد الجزء من الصورة أولًا.');
      return;
    }
    if (_newPartMode == PartPromptMode.smart && _newPartKind == null) {
      setState(() => _error = 'اختر نوع الجزء الذي حددته.');
      return;
    }

    final added = widget.controller.addCustomPart(
      label: _labelController.text,
      promptFragment: _promptController.text,
      promptMode: _newPartMode,
      kind: _newPartKind,
      region: _newPartRegion,
    );
    if (!added) {
      setState(
        () => _error = _newPartMode == PartPromptMode.smart
            ? 'اكتب اسم الجزء، وسيبني Smart Prompt تلقائيًا.'
            : 'اكتب اسم الجزء والـPrompt.',
      );
      return;
    }

    _labelController.clear();
    _promptController.clear();
    setState(() {
      _newPartKind = null;
      _newPartRegion = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.controller.parts.isNotEmpty) ...[
          Text(
            'الأجزاء المختارة',
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
                onGenerate: widget.onGenerate == null
                    ? null
                    : () => widget.onGenerate!(part.key),
                onEdit: () => _editPart(part),
                promptMode: part.promptMode,
                hasRegion: part.region != null,
                onSelectRegion: widget.onSelectRegion == null
                    ? null
                    : () => widget.onSelectRegion!(part),
                onRebuildSmartPrompt: part.promptMode == PartPromptMode.smart
                    ? () => widget.controller.rebuildSmartPrompt(part.key)
                    : null,
                onEnabledChanged: (enabled) {
                  widget.controller.setEnabled(part.key, enabled);
                },
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'إضافة جزء يدوي',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<PartPromptMode>(
          segments: const [
            ButtonSegment(
              value: PartPromptMode.smart,
              icon: Icon(Icons.auto_awesome),
              label: Text('برومبت ذكي'),
            ),
            ButtonSegment(
              value: PartPromptMode.exact,
              icon: Icon(Icons.text_fields),
              label: Text('برومبت مباشر'),
            ),
          ],
          selected: {_newPartMode},
          onSelectionChanged: (selection) {
            setState(() {
              _newPartMode = selection.single;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('manual-region-picker'),
          onPressed: widget.onPickManualRegion == null ? null : _pickManualRegion,
          icon: Icon(
            _newPartRegion == null ? Icons.crop_free : Icons.check_circle_outline,
          ),
          label: Text(
            _newPartRegion == null
                ? 'تحديد الجزء من الصورة'
                : 'تعديل التحديد من الصورة',
          ),
        ),
        if (_newPartRegion != null) ...[
          const SizedBox(height: 8),
          const Text('تم تحديد منطقة من الصورة.'),
          if (_newPartMode == PartPromptMode.smart) ...[
            const SizedBox(height: 10),
            const Text('ما الذي حددته؟ اختر النوع ليُكتب البرومبت المناسب تلقائيًا:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _manualSmartKinds
                  .map(
                    (kind) => ChoiceChip(
                      label: Text(_arabicKindLabel(kind)),
                      selected: _newPartKind == kind,
                      onSelected: (_) => _selectManualKind(kind),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            labelText: 'اسم الجزء',
            hintText: 'مثال: ضمادات الرقبة أو ذراع مع الكتف',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _newPartMode == PartPromptMode.smart
                ? 'تعليمات إضافية (اختياري)'
                : 'البرومبت المباشر — سيُرسل كما كتبته',
            hintText: _newPartMode == PartPromptMode.smart
                ? 'اختياري: أضف تفاصيل خاصة بالجزء'
                : 'اكتب البرومبت كاملًا هنا',
            border: const OutlineInputBorder(),
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
