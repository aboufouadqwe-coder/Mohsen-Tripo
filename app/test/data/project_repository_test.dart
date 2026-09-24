import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/project_repository.dart';

final class FakeProjectDataSource implements ProjectDataSource {
  final Map<String, List<Map<String, Object?>>> rowsByOwner = {
    'user-1': [
      {
        'id': 'project-1',
        'name': 'Patient',
        'reference_image_path': null,
        'template_id': 'template-1',
        'identity_prompt': 'Bandaged patient',
      },
    ],
    'user-2': [],
  };

  String? lastOwnerId;

  @override
  Future<List<Map<String, Object?>>> listForOwner(String ownerId) async {
    lastOwnerId = ownerId;
    return rowsByOwner[ownerId] ?? const [];
  }

  @override
  Future<Map<String, Object?>> createForOwner({
    required String ownerId,
    required String name,
    required String identityPrompt,
  }) async {
    lastOwnerId = ownerId;
    return {
      'id': 'project-created',
      'name': name,
      'reference_image_path': null,
      'template_id': null,
      'identity_prompt': identityPrompt,
    };
  }

  @override
  Future<Map<String, Object?>> updateReferenceImage({
    required String ownerId,
    required String projectId,
    required String storagePath,
  }) async {
    lastOwnerId = ownerId;
    return {
      'id': projectId,
      'name': 'Patient',
      'reference_image_path': storagePath,
      'template_id': 'template-1',
      'identity_prompt': 'Bandaged patient',
    };
  }
}

void main() {
  test('lists only projects for the current anonymous identity', () async {
    final source = FakeProjectDataSource();
    var currentUserId = 'user-1';
    final repository = DefaultProjectRepository(
      dataSource: source,
      currentUserId: () => currentUserId,
    );

    final firstSessionProjects = await repository.listProjects();
    expect(firstSessionProjects.map((project) => project.id), ['project-1']);
    expect(source.lastOwnerId, 'user-1');

    currentUserId = 'user-2';
    final newAnonymousSessionProjects = await repository.listProjects();

    expect(newAnonymousSessionProjects, isEmpty);
    expect(source.lastOwnerId, 'user-2');
  });

  test('createProject scopes insert to current user', () async {
    final source = FakeProjectDataSource();
    final repository = DefaultProjectRepository(
      dataSource: source,
      currentUserId: () => 'user-9',
    );

    final project = await repository.createProject(
      name: 'Ward Patient',
      identityPrompt: 'Young patient with head bandages',
    );

    expect(project.id, 'project-created');
    expect(project.name, 'Ward Patient');
    expect(source.lastOwnerId, 'user-9');
  });

  test('setReferenceImage persists storage path for current user', () async {
    final source = FakeProjectDataSource();
    final repository = DefaultProjectRepository(
      dataSource: source,
      currentUserId: () => 'user-1',
    );

    final project = await repository.setReferenceImage(
      'project-1',
      'user-1/project-1/reference.png',
    );

    expect(project.referenceImagePath, 'user-1/project-1/reference.png');
    expect(source.lastOwnerId, 'user-1');
  });
}
