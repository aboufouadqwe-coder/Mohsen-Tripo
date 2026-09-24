import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase/generation_gateway.dart';
import '../../data/supabase/project_repository.dart';
import '../../data/supabase/reference_image_repository.dart';
import '../../data/supabase/template_repository.dart';
import '../../domain/generation/generation_job.dart';
import '../../domain/projects/project.dart';
import '../../domain/templates/asset_template.dart';
import '../../domain/templates/builtin_templates.dart';
import 'generation_batch_controller.dart';
import 'job_polling_service.dart';
import 'reference_image_picker.dart';
import 'source_image_generator.dart';
import 'template_editor.dart';

final class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.projectId,
    required this.projectRepository,
    required this.templateRepository,
    required this.referenceImageRepository,
    required this.generationGateway,
    required this.currentUserId,
  });

  final String projectId;
  final ProjectRepository projectRepository;
  final TemplateRepository templateRepository;
  final ReferenceImageRepository referenceImageRepository;
  final GenerationGateway generationGateway;
  final String Function() currentUserId;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

final class _WorkspacePageState extends State<WorkspacePage> {
  Project? _project;
  AssetTemplate? _template;
  TemplateEditorController? _templateController;
  GenerationBatchController? _batchController;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _templateController?.dispose();
    _batchController
      ?..removeListener(_onBatchChanged)
      ..dispose();
    super.dispose();
  }

  void _onBatchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final projects = await widget.projectRepository.listProjects();
      Project? project;
      for (final candidate in projects) {
        if (candidate.id == widget.projectId) {
          project = candidate;
          break;
        }
      }
      if (project == null) {
        throw StateError('Project not found');
      }

      final templates = await widget.templateRepository.listTemplates();
      AssetTemplate template = BuiltinTemplates.characterParts;
      for (final candidate in templates) {
        if (candidate.id == project.templateId) {
          template = candidate;
          break;
        }
      }
      if (project.templateId == null && templates.isNotEmpty) {
        template = templates.first;
      }

      final templateController = TemplateEditorController(
        initialParts: template.parts,
      );
      final batchController = GenerationBatchController(
        gateway: widget.generationGateway,
        pollingService: JobPollingService(
          gateway: widget.generationGateway,
        ),
        projectId: project.id,
      );
      batchController.addListener(_onBatchChanged);

      if (!mounted) {
        templateController.dispose();
        batchController.dispose();
        return;
      }

      setState(() {
        _project = project;
        _template = template;
        _templateController = templateController;
        _batchController = batchController;
        _loading = false;
      });

      unawaited(_resumeActiveJobs(project.id, batchController));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل مساحة العمل.';
        _loading = false;
      });
    }
  }

  Future<void> _resumeActiveJobs(
    String projectId,
    GenerationBatchController controller,
  ) async {
    final gateway = widget.generationGateway;
    if (gateway is! ActiveGenerationJobsGateway) return;

    try {
      final activeGateway = gateway as ActiveGenerationJobsGateway;
      final jobs = await activeGateway.listActiveJobs(projectId);
      if (!mounted) return;
      await controller.resumeJobs(jobs);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر استعادة مهام التوليد النشطة.'),
        ),
      );
    }
  }

  Future<void> _setReferencePath(String path) async {
    final project = _project;
    if (project == null) return;

    try {
      final updated = await widget.projectRepository.setReferenceImage(
        project.id,
        path,
      );
      if (mounted) setState(() => _project = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الصورة المرجعية.')),
      );
    }
  }

  Future<void> _selectGeneratedReference(GenerationJob job) async {
    final project = _project;
    final generatedPath = job.storagePath;
    final repository = widget.referenceImageRepository;
    if (project == null ||
        generatedPath == null ||
        repository is! GeneratedReferenceCopier) {
      return;
    }

    try {
      final copier = repository as GeneratedReferenceCopier;
      final referencePath = await copier.copyGeneratedReference(
        userId: widget.currentUserId(),
        projectId: project.id,
        generatedPath: generatedPath,
      );
      await _setReferencePath(referencePath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اعتماد الصورة المولدة كمرجع.')),
      );
    }
  }

  void _generateAll() {
    final project = _project;
    final templateController = _templateController;
    final batchController = _batchController;
    if (project == null ||
        templateController == null ||
        batchController == null ||
        project.referenceImagePath == null) {
      return;
    }

    final enabledParts = templateController.parts
        .where((part) => part.enabled)
        .map((part) => part.key)
        .toList(growable: false);

    if (enabledParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فعّل جزءًا واحدًا على الأقل.')),
      );
      return;
    }

    unawaited(batchController.generateAll(parts: enabledParts));
  }

  void _retryPart(String partKey) {
    final project = _project;
    final batchController = _batchController;
    if (project?.referenceImagePath == null || batchController == null) return;
    unawaited(batchController.regeneratePart(partKey));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _project == null || _templateController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('مساحة العمل')),
        body: Center(child: Text(_error ?? 'المشروع غير متاح.')),
      );
    }

    final project = _project!;
    final batchController = _batchController;

    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              project.identityPrompt.isEmpty
                  ? 'لم تُحدد هوية المشروع بعد.'
                  : project.identityPrompt,
            ),
            const SizedBox(height: 20),
            Text(
              'الصورة المرجعية',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ReferenceImagePicker(
              userId: widget.currentUserId(),
              projectId: project.id,
              repository: widget.referenceImageRepository,
              onUploaded: _setReferencePath,
            ),
            if (project.referenceImagePath != null) ...[
              const SizedBox(height: 8),
              Text('المسار: ${project.referenceImagePath}'),
            ],
            const SizedBox(height: 24),
            Text(
              'إنشاء مرجع بالذكاء الاصطناعي',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SourceImageGenerator(
              projectId: project.id,
              gateway: widget.generationGateway,
              onSelectPersistedImage: _selectGeneratedReference,
            ),
            const SizedBox(height: 24),
            Text(
              _template?.name ?? 'Template',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (project.referenceImagePath == null)
              const Text(
                'اختر صورة مرجعية قبل توليد الأجزاء.',
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: project.referenceImagePath != null &&
                      !(batchController?.isBusy ?? false)
                  ? _generateAll
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('توليد كل الأجزاء'),
            ),
            const SizedBox(height: 12),
            TemplateEditor(
              controller: _templateController!,
              generationState: batchController?.state ?? const {},
              onRetry: project.referenceImagePath == null ? null : _retryPart,
            ),
          ],
        ),
      ),
    );
  }
}
