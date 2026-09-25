import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/analytics/analytics.dart';
import '../../data/local/tripo_credential_repository.dart';
import '../../data/supabase/generation_gateway.dart';
import '../../data/supabase/project_repository.dart';
import '../../data/supabase/reference_image_repository.dart';
import '../../data/supabase/results_repository.dart';
import '../../data/supabase/template_repository.dart';
import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';
import '../../domain/generation/model_generation_settings.dart';
import '../../domain/projects/project.dart';
import '../../domain/smart_parts/smart_part.dart';
import '../../domain/templates/asset_template.dart';
import '../../domain/templates/builtin_templates.dart';
import '../results/generated_image_downloader.dart';
import '../results/model_generation_controller.dart';
import '../results/model_generation_settings_panel.dart';
import '../results/results_gallery.dart';
import '../tripo/tripo_account_card.dart';
import '../tripo/tripo_account_controller.dart';
import 'generation_batch_controller.dart';
import 'job_polling_service.dart';
import 'smart_part_planner_panel.dart';
import 'reference_analysis_service.dart';
import 'part_region_picker.dart';
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
    required this.resultsRepository,
    required this.generationGateway,
    required this.currentUserId,
    this.tripoCredentialRepository,
  });

  final String projectId;
  final ProjectRepository projectRepository;
  final TemplateRepository templateRepository;
  final ReferenceImageRepository referenceImageRepository;
  final ResultsRepository resultsRepository;
  final GenerationGateway generationGateway;
  final String Function() currentUserId;
  final TripoCredentialRepository? tripoCredentialRepository;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

final class _WorkspacePageState extends State<WorkspacePage> {
  Project? _project;
  AssetTemplate? _template;
  TemplateEditorController? _templateController;
  GenerationBatchController? _batchController;
  JobPollingService? _modelPollingService;
  ModelGenerationController? _modelController;
  String? _error;
  bool _loading = true;
  int _resultsVersion = 0;
  int _lastBatchTerminalCount = 0;
  String? _lastModelTerminalJobId;
  final GeneratedImageDownloader _imageDownloader =
      const GeneratedImageDownloader();
  ModelGenerationSettings _modelSettings =
      const ModelGenerationSettings();
  TripoCreditBalance? _creditBalance;
  bool _balanceLoading = false;
  TripoAccountController? _tripoAccountController;
  final ReferenceAnalysisService _referenceAnalysisService =
      const MlKitReferenceAnalysisService();
  ReferenceAnalysis? _referenceAnalysis;
  bool _referenceAnalyzing = false;

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
    _modelController
      ?..removeListener(_onModelChanged)
      ..dispose();
    _modelPollingService?.dispose();
    _tripoAccountController?.dispose();
    super.dispose();
  }

  void _onBatchChanged() {
    final controller = _batchController;
    if (controller == null) return;

    final terminalCount = controller.state.values
        .where((part) => !part.isActive)
        .length;
    if (terminalCount > _lastBatchTerminalCount) {
      _resultsVersion += 1;
      unawaited(_refreshCreditBalance());
    }
    _lastBatchTerminalCount = terminalCount;

    if (mounted) setState(() {});
  }

  void _onModelChanged() {
    final controller = _modelController;
    final modelJob = controller?.job;

    if (modelJob?.isTerminal == true &&
        modelJob!.id != _lastModelTerminalJobId) {
      _lastModelTerminalJobId = modelJob.id;
      _resultsVersion += 1;
      unawaited(_refreshCreditBalance());
    }

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

      final analytics = AnalyticsBinding.maybeCurrent;
      if (analytics != null) {
        unawaited(
          captureAnalyticsSafely(
            analytics,
            AnalyticsEvents.templateSelected,
            {
              'template_kind': template.isBuiltin ? 'builtin' : 'custom',
              'part_count': template.parts.length,
            },
          ),
        );
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
      final modelPollingService = JobPollingService(
        gateway: widget.generationGateway,
      );
      final modelController = ModelGenerationController(
        gateway: widget.generationGateway,
        pollUntilTerminal: modelPollingService.pollUntilTerminal,
        pollUntilTerminalWithUpdates:
            modelPollingService.pollUntilTerminalWithUpdates,
      );
      final credentialRepository = widget.tripoCredentialRepository;
      final validationGateway = widget.generationGateway;
      final tripoAccountController =
          credentialRepository != null &&
                  validationGateway is TripoCredentialValidationGateway
              ? TripoAccountController(
                  repository: credentialRepository,
                  validator:
                      validationGateway as TripoCredentialValidationGateway,
                  readClipboardText: TripoAccountCard.readClipboardText,
                  openConsole: TripoAccountCard.openConsoleInChrome,
                )
              : null;

      batchController.addListener(_onBatchChanged);
      modelController.addListener(_onModelChanged);

      if (!mounted) {
        templateController.dispose();
        batchController.dispose();
        modelPollingService.dispose();
        modelController.dispose();
        return;
      }

      setState(() {
        _project = project;
        _template = template;
        _templateController = templateController;
        _batchController = batchController;
        _modelPollingService = modelPollingService;
        _modelController = modelController;
        _tripoAccountController = tripoAccountController;
        _loading = false;
      });

      unawaited(
        _resumeActiveJobs(
          project.id,
          batchController,
          modelController,
        ),
      );
      unawaited(_refreshCreditBalance());
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
    ModelGenerationController modelController,
  ) async {
    final gateway = widget.generationGateway;
    if (gateway is! ActiveGenerationJobsGateway) return;

    try {
      final activeGateway = gateway as ActiveGenerationJobsGateway;
      final jobs = await activeGateway.listActiveJobs(projectId);
      if (!mounted) return;

      final partJobs = jobs
          .where((job) => job.operation == GenerationOperation.imageToImage)
          .toList(growable: false);
      final modelJobs = jobs
          .where((job) => job.operation == GenerationOperation.imageToModel)
          .toList(growable: false);

      final futures = <Future<void>>[
        controller.resumeJobs(partJobs),
      ];
      if (modelJobs.isNotEmpty) {
        futures.add(modelController.resumeJob(modelJobs.last));
      }
      await Future.wait(futures);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر استعادة مهام التوليد النشطة.'),
        ),
      );
    }
  }

  Future<void> _refreshCreditBalance() async {
    final generationGateway = widget.generationGateway;
    if (generationGateway is! CreditBalanceGateway || _balanceLoading) return;
    final balanceGateway = generationGateway as CreditBalanceGateway;

    if (mounted) {
      setState(() => _balanceLoading = true);
    }

    try {
      final balance = await balanceGateway.getCreditBalance();
      if (!mounted) return;
      setState(() {
        _creditBalance = balance;
        _balanceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _balanceLoading = false);
    }
  }

  String _creditText(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _setReferencePath(String path) async {
    final project = _project;
    if (project == null) return;

    try {
      final updated = await widget.projectRepository.setReferenceImage(
        project.id,
        path,
      );
      if (!mounted) return;
      setState(() {
        _project = updated;
        _referenceAnalysis = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الصورة المرجعية.')),
      );
    }
  }

  Future<void> _analyzeReference() async {
    final project = _project;
    final path = project?.referenceImagePath;
    final repository = widget.referenceImageRepository;
    if (project == null ||
        path == null ||
        repository is! ReferenceImageBytesReader ||
        _referenceAnalyzing) {
      return;
    }

    setState(() => _referenceAnalyzing = true);
    try {
      final reader = repository as ReferenceImageBytesReader;
      final bytes = await reader.downloadReference(path);
      final analysis = await _referenceAnalysisService.analyze(bytes);
      if (!mounted) return;
      setState(() {
        _referenceAnalysis = analysis;
        _referenceAnalyzing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _referenceAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحليل الصورة تلقائيًا. يمكنك إضافة الأجزاء يدويًا.'),
        ),
      );
    }
  }

  void _applySmartSuggestions(List<SuggestedPart> suggestions) {
    final controller = _templateController;
    if (controller == null) return;
    controller.replaceWithSuggestions(suggestions);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تطبيق اقتراحات التقسيم الذكي.')),
    );
  }

  Future<void> _selectPartRegion(EditableTemplatePart part) async {
    final project = _project;
    final referencePath = project?.referenceImagePath;
    final repository = widget.referenceImageRepository;
    if (project == null ||
        referencePath == null ||
        repository is! ReferenceImageBytesReader) {
      return;
    }

    try {
      final reader = repository as ReferenceImageBytesReader;
      final bytes = await reader.downloadReference(referencePath);
      if (!mounted) return;
      final region = await showDialog<NormalizedRegion>(
        context: context,
        builder: (context) => PartRegionPickerDialog(
          imageBytes: bytes,
          initialRegion: part.region,
        ),
      );
      if (region != null && mounted) {
        _templateController?.setRegion(part.key, region);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح محدد منطقة الجزء.')),
      );
    }
  }

  bool _isWholeImageRegion(NormalizedRegion region) {
    return region.left <= 0.01 &&
        region.top <= 0.01 &&
        region.right >= 0.99 &&
        region.bottom >= 0.99;
  }

  Future<GenerationPartRequest?> _buildPartRequest(
    EditableTemplatePart part,
  ) async {
    final project = _project;
    final referencePath = project?.referenceImagePath;
    if (project == null || referencePath == null) return null;

    String? partReferencePath;
    final region = part.region;
    if (region != null && !_isWholeImageRegion(region)) {
      final repository = widget.referenceImageRepository;
      if (repository is! PartReferenceCropper) return null;
      try {
        partReferencePath = await (repository as PartReferenceCropper)
            .createPartReferenceCrop(
          userId: widget.currentUserId(),
          projectId: project.id,
          partKey: part.key,
          sourcePath: referencePath,
          region: region,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تعذر تجهيز قص الجزء: ${part.label}'),
            ),
          );
        }
        return null;
      }
    }

    return GenerationPartRequest(
      key: part.key,
      label: part.label,
      prompt: part.promptFragment,
      referenceStoragePath: partReferencePath,
    );
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
      final analytics = AnalyticsBinding.maybeCurrent;
      if (analytics != null) {
        unawaited(
          captureAnalyticsSafely(
            analytics,
            AnalyticsEvents.referenceImageAdded,
            const {'source': 'generated', 'format': 'png'},
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اعتماد الصورة المولدة كمرجع.')),
      );
    }
  }

  Future<void> _generateAll() async {
    final project = _project;
    final templateController = _templateController;
    final batchController = _batchController;
    if (project == null ||
        templateController == null ||
        batchController == null ||
        project.referenceImagePath == null) {
      return;
    }

    final enabled = templateController.parts
        .where((part) => part.enabled)
        .toList(growable: false);
    if (enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فعّل جزءًا واحدًا على الأقل.')),
      );
      return;
    }

    final requests = <GenerationPartRequest>[];
    for (final part in enabled) {
      final request = await _buildPartRequest(part);
      if (request != null) requests.add(request);
    }
    if (requests.isEmpty || !mounted) return;

    await batchController.generateAll(parts: requests);
  }

  EditableTemplatePart? _partByKey(String partKey) {
    final controller = _templateController;
    if (controller == null) return null;
    for (final part in controller.parts) {
      if (part.key == partKey) return part;
    }
    return null;
  }

  Future<void> _generatePart(String partKey) async {
    final project = _project;
    final batchController = _batchController;
    final part = _partByKey(partKey);
    if (project?.referenceImagePath == null ||
        batchController == null ||
        part == null) {
      return;
    }
    final request = await _buildPartRequest(part);
    if (request == null) return;
    await batchController.generatePart(request);
  }

  Future<void> _retryPart(String partKey) async {
    final project = _project;
    final batchController = _batchController;
    final part = _partByKey(partKey);
    if (project?.referenceImagePath == null ||
        batchController == null ||
        part == null) {
      return;
    }
    final request = await _buildPartRequest(part);
    if (request == null) return;
    await batchController.regeneratePart(request);
  }

  Future<void> _generateModel(AssetResult asset) async {
    final controller = _modelController;
    if (controller == null) return;
    await controller.generateFromImage(
      asset,
      settings: _modelSettings,
    );
  }

  Future<void> _downloadImage(
    AssetResult asset,
    String signedUrl,
  ) async {
    try {
      await _imageDownloader.download(asset, signedUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الصورة في معرض الهاتف.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تنزيل الصورة إلى الهاتف.')),
      );
    }
  }

  Future<void> _downloadModel(
    AssetResult asset,
    String signedUrl,
  ) async {
    try {
      await _imageDownloader.downloadModel(asset, signedUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ المجسم في Downloads/Mohsen-Tripo.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تنزيل المجسم إلى الهاتف.')),
      );
    }
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
    final modelController = _modelController;

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
            const SizedBox(height: 12),
            if (_tripoAccountController != null)
              TripoAccountCard(controller: _tripoAccountController!)
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text(
                    _creditBalance == null
                        ? 'رصيد Tripo'
                        : 'الرصيد: ${_creditText(_creditBalance!.available)}',
                  ),
                  subtitle: _creditBalance == null
                      ? const Text('اضغط تحديث لعرض الرصيد.')
                      : Text(
                          'محجوز للمهام الحالية: '
                          '${_creditText(_creditBalance!.frozen)}',
                        ),
                  trailing: _balanceLoading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'تحديث الرصيد',
                          onPressed: _refreshCreditBalance,
                          icon: const Icon(Icons.refresh),
                        ),
                ),
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
            const SizedBox(height: 16),
            SmartPartPlannerPanel(
              analysis: _referenceAnalysis,
              loading: _referenceAnalyzing,
              enabled: project.referenceImagePath != null,
              onAnalyze: _analyzeReference,
              onApply: _applySmartSuggestions,
            ),
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
                  ? () => unawaited(_generateAll())
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('توليد كل الأجزاء'),
            ),
            const SizedBox(height: 12),
            TemplateEditor(
              controller: _templateController!,
              generationState: batchController?.state ?? const {},
              onRetry: project.referenceImagePath == null
                  ? null
                  : (key) => unawaited(_retryPart(key)),
              onGenerate: project.referenceImagePath == null
                  ? null
                  : (key) => unawaited(_generatePart(key)),
              onSelectRegion: project.referenceImagePath == null
                  ? null
                  : _selectPartRegion,
            ),
            const SizedBox(height: 24),
            ModelGenerationSettingsPanel(
              settings: _modelSettings,
              disabled: modelController?.isBusy ?? false,
              onChanged: (settings) {
                setState(() => _modelSettings = settings);
              },
            ),
            const SizedBox(height: 16),
            ResultsGallery(
              projectId: project.id,
              repository: widget.resultsRepository,
              refreshVersion: _resultsVersion,
              onGenerateModel: _generateModel,
              onDownloadImage: _downloadImage,
              onDownloadModel: _downloadModel,
              modelGenerationBusy: modelController?.isBusy ?? false,
              activeModelAssetResultId:
                  modelController?.activeAssetResultId,
              modelJob: modelController?.job,
            ),
          ],
        ),
      ),
    );
  }
}
