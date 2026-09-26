import '../../core/errors/app_failure.dart';
import '../../domain/templates/asset_template.dart';
import '../../domain/templates/template_part.dart';

abstract interface class TemplateRepository {
  Future<List<AssetTemplate>> listTemplates();
}

abstract interface class TemplateDataSource {
  Future<List<Map<String, Object?>>> listVisibleTemplates();
}

final class DefaultTemplateRepository implements TemplateRepository {
  const DefaultTemplateRepository(this._dataSource);

  final TemplateDataSource _dataSource;

  @override
  Future<List<AssetTemplate>> listTemplates() async {
    try {
      final rows = await _dataSource.listVisibleTemplates();
      return rows.map(_templateFromRow).toList(growable: false);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  AssetTemplate _templateFromRow(Map<String, Object?> row) {
    final id = row['id'];
    final name = row['name'];
    final description = row['description'];
    final isBuiltin = row['is_builtin'];
    final rawParts = row['template_parts'];

    if (id is! String ||
        name is! String ||
        description is! String ||
        isBuiltin is! bool ||
        rawParts is! List) {
      throw AppFailure.data();
    }

    final parts = rawParts
        .map((raw) {
          if (raw is! Map) throw AppFailure.data();
          final part = Map<String, Object?>.from(raw.cast<String, Object?>());
          final key = part['key'];
          final label = part['label'];
          final promptFragment = part['prompt_fragment'];
          final sortOrder = part['sort_order'];
          final enabledByDefault = part['enabled_by_default'];

          if (key is! String ||
              label is! String ||
              promptFragment is! String ||
              sortOrder is! int ||
              enabledByDefault is! bool) {
            throw AppFailure.data();
          }

          return TemplatePart(
            key: key,
            label: label,
            promptFragment: promptFragment,
            sortOrder: sortOrder,
            enabledByDefault: enabledByDefault,
          );
        })
        .toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));

    return AssetTemplate(
      id: id,
      name: name,
      description: description,
      isBuiltin: isBuiltin,
      parts: parts,
    );
  }
}
