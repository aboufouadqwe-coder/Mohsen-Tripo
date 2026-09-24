import 'template_part.dart';

final class AssetTemplate {
  AssetTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.isBuiltin,
    required List<TemplatePart> parts,
  }) : parts = List<TemplatePart>.unmodifiable(parts);

  final String id;
  final String name;
  final String description;
  final bool isBuiltin;
  final List<TemplatePart> parts;
}
