import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/smart_parts/smart_part.dart';
import 'package:mohsen_tripo/src/domain/templates/builtin_templates.dart';
import 'package:mohsen_tripo/src/features/workspace/template_editor.dart';

void main() {
  test('built-in parts are normalized into stable sort order', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts.reversed.toList(),
      newKey: () => 'unused',
    );

    expect(
      controller.parts.map((part) => part.key),
      [
        'head',
        'right_hand',
        'left_hand',
        'right_foot',
        'left_foot',
        'clothing',
        'accessories',
      ],
    );
  });

  test('toggle disables one part without removing its stable identity', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'unused',
    );

    controller.setEnabled('head', false);

    final head = controller.parts.singleWhere((part) => part.key == 'head');
    expect(head.enabled, isFalse);
    expect(head.label, 'Head');
  });

  test('custom Arabic part can be added with UUID-backed stable key', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'custom-uuid-1',
    );

    final added = controller.addCustomPart(
      label: 'ضمادات الرأس',
      promptFragment: 'Generate the exact head bandages as a separate asset.',
    );

    expect(added, isTrue);
    final custom =
        controller.parts.singleWhere((part) => part.key == 'custom-uuid-1');
    expect(custom.label, 'ضمادات الرأس');
    expect(custom.enabled, isTrue);
  });

  test('blank custom part label is rejected', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'custom-uuid-1',
    );

    expect(
      controller.addCustomPart(
        label: '   ',
        promptFragment: 'Generate bandages.',
      ),
      isFalse,
    );
    expect(
      controller.parts.any((part) => part.key == 'custom-uuid-1'),
      isFalse,
    );
  });

  test('existing part prompt can be edited without changing stable key', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'unused',
    );

    final updated = controller.updatePart(
      key: 'head',
      label: 'Head close-up',
      promptFragment: 'Use my exact custom head prompt.',
    );

    expect(updated, isTrue);
    final head = controller.parts.singleWhere((part) => part.key == 'head');
    expect(head.label, 'Head close-up');
    expect(head.promptFragment, 'Use my exact custom head prompt.');
  });

  test('reorder changes presentation order but preserves stable keys', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'unused',
    );
    final originalKeys = controller.parts.map((part) => part.key).toSet();

    controller.reorder(0, 3);

    expect(controller.parts.first.key, isNot('head'));
    expect(controller.parts.map((part) => part.key).toSet(), originalKeys);
    expect(
      controller.parts.singleWhere((part) => part.label == 'Head').key,
      'head',
    );
  });

  test('smart custom head builds a MetaHuman-ready prompt automatically', () {
    final controller = TemplateEditorController(
      initialParts: const [],
      newKey: () => 'smart-head-1',
    );

    final added = controller.addCustomPart(
      label: 'MetaHuman Head',
      promptFragment: '',
      promptMode: PartPromptMode.smart,
    );

    expect(added, isTrue);
    final part = controller.parts.single;
    expect(part.kind, SmartPartKind.headClean);
    expect(part.promptMode, PartPromptMode.smart);
    expect(part.promptFragment, contains('bald head'));
    expect(part.promptFragment, contains('Remove all hair'));
  });

  test('smart suggestions replace list with detected regions intact', () {
    final controller = TemplateEditorController(
      initialParts: BuiltinTemplates.characterParts.parts,
      newKey: () => 'unused',
    );
    const region = NormalizedRegion(
      left: 0.2,
      top: 0.1,
      right: 0.8,
      bottom: 0.55,
    );

    controller.replaceWithSuggestions(
      const [
        SuggestedPart(
          key: 'head',
          label: 'Head Clean / Bald',
          kind: SmartPartKind.headClean,
          prompt: 'smart head prompt',
          region: region,
        ),
      ],
    );

    expect(controller.parts, hasLength(1));
    expect(controller.parts.single.promptMode, PartPromptMode.smart);
    expect(controller.parts.single.region, same(region));
  });

}
