final class Project {
  const Project({
    required this.id,
    required this.name,
    this.referenceImagePath,
    this.templateId,
    this.identityPrompt = '',
  });

  final String id;
  final String name;
  final String? referenceImagePath;
  final String? templateId;
  final String identityPrompt;
}
