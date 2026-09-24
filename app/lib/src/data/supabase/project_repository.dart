import '../../core/errors/app_failure.dart';
import '../../domain/projects/project.dart';

abstract interface class ProjectRepository {
  Future<List<Project>> listProjects();

  Future<Project> createProject({
    required String name,
    required String identityPrompt,
  });

  Future<Project> setReferenceImage(
    String projectId,
    String storagePath,
  );
}

abstract interface class ProjectDataSource {
  Future<List<Map<String, Object?>>> listForOwner(String ownerId);

  Future<Map<String, Object?>> createForOwner({
    required String ownerId,
    required String name,
    required String identityPrompt,
  });

  Future<Map<String, Object?>> updateReferenceImage({
    required String ownerId,
    required String projectId,
    required String storagePath,
  });
}

final class DefaultProjectRepository implements ProjectRepository {
  const DefaultProjectRepository({
    required this.dataSource,
    required this.currentUserId,
  });

  final ProjectDataSource dataSource;
  final String Function() currentUserId;

  @override
  Future<List<Project>> listProjects() async {
    try {
      final rows = await dataSource.listForOwner(_requiredUserId());
      return rows.map(_projectFromRow).toList(growable: false);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  @override
  Future<Project> createProject({
    required String name,
    required String identityPrompt,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 120) {
      throw AppFailure.validation(
        'Project name must contain between 1 and 120 characters.',
      );
    }

    try {
      final row = await dataSource.createForOwner(
        ownerId: _requiredUserId(),
        name: normalizedName,
        identityPrompt: identityPrompt.trim(),
      );
      return _projectFromRow(row);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  @override
  Future<Project> setReferenceImage(
    String projectId,
    String storagePath,
  ) async {
    if (projectId.trim().isEmpty || storagePath.trim().isEmpty) {
      throw AppFailure.validation(
        'Project id and reference storage path are required.',
      );
    }

    try {
      final row = await dataSource.updateReferenceImage(
        ownerId: _requiredUserId(),
        projectId: projectId.trim(),
        storagePath: storagePath.trim(),
      );
      return _projectFromRow(row);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.data();
    }
  }

  String _requiredUserId() {
    final value = currentUserId().trim();
    if (value.isEmpty) throw AppFailure.authentication();
    return value;
  }

  Project _projectFromRow(Map<String, Object?> row) {
    final id = row['id'];
    final name = row['name'];
    final identityPrompt = row['identity_prompt'];

    if (id is! String || name is! String || identityPrompt is! String) {
      throw AppFailure.data();
    }

    final referenceImagePath = row['reference_image_path'];
    final templateId = row['template_id'];

    if (referenceImagePath != null && referenceImagePath is! String) {
      throw AppFailure.data();
    }
    if (templateId != null && templateId is! String) {
      throw AppFailure.data();
    }

    return Project(
      id: id,
      name: name,
      referenceImagePath: referenceImagePath as String?,
      templateId: templateId as String?,
      identityPrompt: identityPrompt,
    );
  }
}
