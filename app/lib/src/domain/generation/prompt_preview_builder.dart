import '../projects/project.dart';
import '../templates/template_part.dart';

final class PromptPreviewBuilder {
  String build(
    Project project,
    TemplatePart part, {
    String? customInstructions,
  }) {
    final label = part.label.trim();
    final fragment = part.promptFragment.trim();

    if (label.isEmpty) {
      throw ArgumentError.value(part.label, 'part.label', 'Must not be blank.');
    }
    if (fragment.isEmpty) {
      throw ArgumentError.value(
        part.promptFragment,
        'part.promptFragment',
        'Must not be blank.',
      );
    }

    final lines = <String>[
      'Generate a clean isolated reference image of the same character.',
      'Identity: ${project.identityPrompt.trim()}',
      'Requested asset: $label',
      'Instruction: $fragment',
    ];

    final custom = customInstructions?.trim();
    if (custom != null && custom.isNotEmpty) {
      lines.add('Additional instruction: $custom');
    }

    lines
      ..add(
        'Preserve identity, proportions, materials, colors, clothing design, '
        'damage, and accessories from the reference image.',
      )
      ..add('Show only the requested asset clearly and completely.');

    return lines.join('\n');
  }
}
