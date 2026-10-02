import 'asset_template.dart';
import 'template_part.dart';

abstract final class BuiltinTemplates {
  static final AssetTemplate characterParts = AssetTemplate(
    id: 'character_parts',
    name: 'Character Parts',
    description:
        'Generate consistent character-part reference images from one source.',
    isBuiltin: true,
    parts: const [
      TemplatePart(
        key: 'head',
        label: 'Head',
        promptFragment:
            'Generate the complete head clearly from the front, preserving face, hair, headwear, wounds, and bandages.',
        sortOrder: 0,
      ),
      TemplatePart(
        key: 'right_hand',
        label: 'Right Hand',
        promptFragment:
            'Generate the complete right hand clearly, preserving skin, damage, gloves, jewelry, and proportions.',
        sortOrder: 1,
      ),
      TemplatePart(
        key: 'left_hand',
        label: 'Left Hand',
        promptFragment:
            'Generate the complete left hand clearly, preserving skin, damage, gloves, jewelry, and proportions.',
        sortOrder: 2,
      ),
      TemplatePart(
        key: 'right_foot',
        label: 'Right Foot',
        promptFragment:
            'Generate the complete right foot clearly, including the exact footwear or visible foot design.',
        sortOrder: 3,
      ),
      TemplatePart(
        key: 'left_foot',
        label: 'Left Foot',
        promptFragment:
            'Generate the complete left foot clearly, including the exact footwear or visible foot design.',
        sortOrder: 4,
      ),
      TemplatePart(
        key: 'clothing',
        label: 'Clothing',
        promptFragment:
            'Generate the character clothing as a clear reference, preserving material, wear, stains, tears, and colors.',
        sortOrder: 5,
      ),
      TemplatePart(
        key: 'accessories',
        label: 'Accessories',
        promptFragment:
            'Generate the character accessories as a clear reference, preserving their exact shapes, materials, colors, and placement language.',
        sortOrder: 6,
      ),
    ],
  );
}
