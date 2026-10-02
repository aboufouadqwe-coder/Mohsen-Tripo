final class TemplatePart {
  const TemplatePart({
    required this.key,
    required this.label,
    required this.promptFragment,
    required this.sortOrder,
    this.enabledByDefault = true,
  });

  final String key;
  final String label;
  final String promptFragment;
  final int sortOrder;
  final bool enabledByDefault;
}
