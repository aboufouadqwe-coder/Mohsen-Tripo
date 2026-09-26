import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/analytics/analytics.dart';
import '../../data/supabase/project_repository.dart';
import '../../domain/projects/project.dart';

final class CreateProjectPage extends StatefulWidget {
  const CreateProjectPage({
    super.key,
    required this.projectRepository,
    required this.onCreated,
  });

  final ProjectRepository projectRepository;
  final ValueChanged<Project> onCreated;

  @override
  State<CreateProjectPage> createState() => _CreateProjectPageState();
}

final class _CreateProjectPageState extends State<CreateProjectPage> {
  final _nameController = TextEditingController();
  final _identityController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _identityController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسمًا للمشروع.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final project = await widget.projectRepository.createProject(
        name: name,
        identityPrompt: _identityController.text.trim(),
      );
      final analytics = AnalyticsBinding.maybeCurrent;
      if (analytics != null) {
        unawaited(
          captureAnalyticsSafely(
            analytics,
            AnalyticsEvents.projectCreated,
            {
              'has_identity_prompt': project.identityPrompt.trim().isNotEmpty,
            },
          ),
        );
      }
      if (!mounted) return;
      widget.onCreated(project);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر إنشاء المشروع.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشروع جديد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم المشروع',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _identityController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'هوية الشخصية أو الأصل',
                hintText: 'مثال: مريض شاب بضمادات رأس وملابس مستشفى قديمة',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}
