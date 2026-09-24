import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/domain/generation/prompt_preview_builder.dart';
import 'package:mohsen_tripo/src/domain/projects/project.dart';
import 'package:mohsen_tripo/src/domain/templates/template_part.dart';

void main() {
  test('combines identity, part instruction, and custom instruction', () {
    final prompt = PromptPreviewBuilder().build(
      const Project(
        id: 'p1',
        name: 'Patient',
        referenceImagePath: 'u/p1/reference.png',
        identityPrompt: 'Young male patient with old brown hospital clothes.',
      ),
      const TemplatePart(
        key: 'injured_arm',
        label: 'الذراع المصابة',
        promptFragment: 'Generate the injured arm clearly and completely.',
        sortOrder: 0,
      ),
      customInstructions: 'Keep the exact head-bandage visual language.',
    );

    expect(
      prompt,
      equals(
        'Generate a clean isolated reference image of the same character.\n'
        'Identity: Young male patient with old brown hospital clothes.\n'
        'Requested asset: الذراع المصابة\n'
        'Instruction: Generate the injured arm clearly and completely.\n'
        'Additional instruction: Keep the exact head-bandage visual language.\n'
        'Preserve identity, proportions, materials, colors, clothing design, '
        'damage, and accessories from the reference image.\n'
        'Show only the requested asset clearly and completely.',
      ),
    );
  });

  test('omits additional instruction when none is provided', () {
    final prompt = PromptPreviewBuilder().build(
      const Project(
        id: 'p2',
        name: 'Nurse',
        identityPrompt: 'Nurse in an old psychiatric hospital uniform.',
      ),
      const TemplatePart(
        key: 'head',
        label: 'Head',
        promptFragment: 'Generate the complete head from the front.',
        sortOrder: 0,
      ),
    );

    expect(prompt, isNot(contains('Additional instruction:')));
  });

  test('rejects blank part label', () {
    expect(
      () => PromptPreviewBuilder().build(
        const Project(id: 'p3', name: 'Test'),
        const TemplatePart(
          key: 'bad',
          label: '   ',
          promptFragment: 'Generate something.',
          sortOrder: 0,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects blank part prompt fragment', () {
    expect(
      () => PromptPreviewBuilder().build(
        const Project(id: 'p4', name: 'Test'),
        const TemplatePart(
          key: 'bad',
          label: 'Head',
          promptFragment: '   ',
          sortOrder: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
}
