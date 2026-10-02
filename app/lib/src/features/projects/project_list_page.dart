import 'package:flutter/material.dart';

import '../../data/supabase/project_repository.dart';
import '../../domain/projects/project.dart';

final class ProjectListPage extends StatelessWidget {
  const ProjectListPage({
    super.key,
    required this.projectRepository,
    required this.onCreateProject,
    required this.onOpenProject,
  });

  final ProjectRepository projectRepository;
  final VoidCallback onCreateProject;
  final ValueChanged<Project> onOpenProject;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mohsen Tripo'),
        actions: [
          IconButton(
            onPressed: onCreateProject,
            icon: const Icon(Icons.add),
            tooltip: 'إنشاء مشروع',
          ),
        ],
      ),
      body: FutureBuilder<List<Project>>(
        future: projectRepository.listProjects(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'تعذر تحميل المشاريع. حاول مرة أخرى.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final projects = snapshot.data ?? const <Project>[];
          if (projects.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد مشاريع بعد',
                      style: TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ابدأ مشروعًا جديدًا لتوليد صور مرجعية وأجزاء متناسقة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onCreateProject,
                      icon: const Icon(Icons.add),
                      label: const Text('إنشاء مشروع'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  subtitle: project.identityPrompt.isEmpty
                      ? null
                      : Text(
                          project.identityPrompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpenProject(project),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
