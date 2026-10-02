import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/templates/builtin_templates.dart';

void main() {
  test('character parts template ships with required defaults', () {
    final template = BuiltinTemplates.characterParts;

    expect(
      template.parts.map((part) => part.key),
      containsAllInOrder(const [
        'head',
        'right_hand',
        'left_hand',
        'right_foot',
        'left_foot',
        'clothing',
        'accessories',
      ]),
    );
    expect(template.parts, hasLength(7));
    expect(template.isBuiltin, isTrue);
  });
}
