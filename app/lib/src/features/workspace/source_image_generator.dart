import 'package:flutter/material.dart';

import '../../data/supabase/generation_gateway.dart';
import '../../domain/generation/generation_job.dart';

final class SourceImageGenerator extends StatefulWidget {
  const SourceImageGenerator({
    super.key,
    required this.projectId,
    required this.gateway,
    required this.onSelectPersistedImage,
    this.pollInterval = const Duration(seconds: 1),
  });

  final String projectId;
  final GenerationGateway gateway;
  final ValueChanged<GenerationJob> onSelectPersistedImage;
  final Duration pollInterval;

  @override
  State<SourceImageGenerator> createState() => _SourceImageGeneratorState();
}

final class _SourceImageGeneratorState extends State<SourceImageGenerator> {
  final _promptController = TextEditingController();
  bool _busy = false;
  String? _error;
  GenerationJob? _job;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  bool _isPersistedImage(GenerationJob? job) {
    return job?.status == GenerationStatus.success &&
        (job?.assetResultId?.isNotEmpty ?? false) &&
        (job?.storagePath?.isNotEmpty ?? false) &&
        (job?.mimeType?.startsWith('image/') ?? false);
  }

  double _progressValue(double progress) {
    if (progress < 0) return 0;
    if (progress > 1) return 1;
    return progress;
  }

  Future<void> _generate() async {
    if (_busy) return;
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'اكتب وصفًا للصورة المرجعية.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _job = null;
    });

    try {
      final jobId = await widget.gateway.generateSourceImage(
        projectId: widget.projectId,
        prompt: prompt,
      );

      while (mounted) {
        final refreshed = await widget.gateway.refreshJob(jobId);
        if (!mounted) return;
        setState(() => _job = refreshed);

        if (refreshed.isTerminal) break;
        await Future<void>.delayed(widget.pollInterval);
      }

      final terminal = _job;
      if (terminal?.status == GenerationStatus.success &&
          !_isPersistedImage(terminal)) {
        setState(() => _error = 'اكتمل التوليد لكن الصورة لم تُحفظ بعد.');
      } else if (terminal?.status == GenerationStatus.failed ||
          terminal?.status == GenerationStatus.cancelled) {
        setState(() => _error = 'تعذر إنشاء الصورة المرجعية.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إنشاء الصورة المرجعية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('source-prompt'),
          controller: _promptController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'وصف الصورة المرجعية',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('إنشاء صورة مرجعية'),
        ),
        if (job != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progressValue(job.progress)),
          const SizedBox(height: 4),
          Text('التقدم: ${(job.progress * 100).round()}%'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_isPersistedImage(job)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => widget.onSelectPersistedImage(job!),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('اعتماد كمرجع'),
          ),
        ],
      ],
    );
  }
}
