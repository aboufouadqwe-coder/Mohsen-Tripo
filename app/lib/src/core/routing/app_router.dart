import 'package:go_router/go_router.dart';

import '../../data/supabase/generation_gateway.dart';
import '../../data/supabase/project_repository.dart';
import '../../data/supabase/reference_image_repository.dart';
import '../../data/supabase/template_repository.dart';
import '../../domain/projects/project.dart';
import '../../features/projects/create_project_page.dart';
import '../../features/projects/project_list_page.dart';
import '../../features/workspace/workspace_page.dart';

final class AppRouterDependencies {
  const AppRouterDependencies({
    required this.projectRepository,
    required this.templateRepository,
    required this.referenceImageRepository,
    required this.generationGateway,
    required this.currentUserId,
  });

  final ProjectRepository projectRepository;
  final TemplateRepository templateRepository;
  final ReferenceImageRepository referenceImageRepository;
  final GenerationGateway generationGateway;
  final String Function() currentUserId;
}

GoRouter buildAppRouter(AppRouterDependencies dependencies) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => ProjectListPage(
          projectRepository: dependencies.projectRepository,
          onCreateProject: () => context.go('/projects/new'),
          onOpenProject: (Project project) {
            context.go('/projects/${project.id}');
          },
        ),
      ),
      GoRoute(
        path: '/projects/new',
        builder: (context, state) => CreateProjectPage(
          projectRepository: dependencies.projectRepository,
          onCreated: (project) {
            context.go('/projects/${project.id}');
          },
        ),
      ),
      GoRoute(
        path: '/projects/:id',
        builder: (context, state) => WorkspacePage(
          projectId: state.pathParameters['id']!,
          projectRepository: dependencies.projectRepository,
          templateRepository: dependencies.templateRepository,
          referenceImageRepository: dependencies.referenceImageRepository,
          generationGateway: dependencies.generationGateway,
          currentUserId: dependencies.currentUserId,
        ),
      ),
    ],
  );
}
