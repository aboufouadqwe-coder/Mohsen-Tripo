import 'package:flutter_test/flutter_test.dart';
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
}
