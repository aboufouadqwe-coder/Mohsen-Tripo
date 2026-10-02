import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mohsen_tripo/src/data/supabase/project_repository.dart';
import 'package:mohsen_tripo/src/domain/projects/project.dart';
import 'package:mohsen_tripo/src/features/projects/project_list_page.dart';

final class EmptyProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> listProjects() async => const [];

  @override
  Future<Project> createProject({
    required String name,
    required String identityPrompt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Project> setReferenceImage(
    String projectId,
    String storagePath,
  ) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets(
    'empty project list exposes Arabic create action and navigates to creation',
    (tester) async {
      final repository = EmptyProjectRepository();

      late final GoRouter router;
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => ProjectListPage(
              projectRepository: repository,
              onCreateProject: () => context.go('/projects/new'),
              onOpenProject: (project) =>
                  context.go('/projects/${project.id}'),
            ),
          ),
          GoRoute(
            path: '/projects/new',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('مشروع جديد')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء مشروع'), findsOneWidget);

      await tester.tap(find.text('إنشاء مشروع'));
      await tester.pumpAndSettle();

      expect(find.text('مشروع جديد'), findsOneWidget);
    },
  );
}
