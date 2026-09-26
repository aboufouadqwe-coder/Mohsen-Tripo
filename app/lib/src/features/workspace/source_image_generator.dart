import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/analytics/analytics.dart';
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
  final Stopwatch _elapsedStopwatch = Stopwatch();
  Timer? _elapsedTimer;

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _elapsedStopwatch.stop();
    _promptController.dispose();
    super.dispose();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedStopwatch
      ..reset()
      ..start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsedStopwatch.stop();
  }

  String _formatElapsed(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';
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

  void _capture(String event, Map<String, Object?> properties) {
    final analytics = AnalyticsBinding.maybeCurrent;
    if (analytics == null) return;
    unawaited(captureAnalyticsSafely(analytics, event, properties));
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
    _startElapsedTimer();

    _capture(
      AnalyticsEvents.generationStarted,
      const {'operation': 'text_to_image'},
    );

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
          _isPersistedImage(terminal)) {
        _capture(
          AnalyticsEvents.generationCompleted,
          const {'operation': 'text_to_image'},
        );
      } else if (terminal?.status == GenerationStatus.success) {
        _capture(
          AnalyticsEvents.generationFailed,
          const {
            'operation': 'text_to_image',
            'error_code': 'persistence_missing',
          },
        );
        setState(() => _error = 'اكتمل التوليد لكن الصورة لم تُحفظ بعد.');
      } else if (terminal?.status == GenerationStatus.failed ||
          terminal?.status == GenerationStatus.cancelled) {
        _capture(
          AnalyticsEvents.generationFailed,
          {
            'operation': 'text_to_image',
            'error_code': terminal?.errorCode ?? 'provider_failed',
          },
        );
        setState(() => _error = 'تعذر إنشاء الصورة المرجعية.');
      }
    } catch (_) {
      _capture(
        AnalyticsEvents.generationFailed,
        const {
          'operation': 'text_to_image',
          'error_code': 'client_request_failed',
        },
      );
      if (mounted) setState(() => _error = 'تعذر إنشاء الصورة المرجعية.');
    } finally {
      _stopElapsedTimer();
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
        if (_busy || _elapsedStopwatch.elapsed > Duration.zero) ...[
          const SizedBox(height: 10),
          Text('الوقت المنقضي: ${_formatElapsed(_elapsedStopwatch.elapsed)}'),
        ],
        if (job != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: !job.isTerminal && job.progress <= 0
                ? null
                : _progressValue(job.progress),
          ),
          const SizedBox(height: 4),
          Text(
            !job.isTerminal && job.progress <= 0
                ? 'التقدم: جارٍ التوليد…'
                : 'التقدم: ${(job.progress * 100).round()}%',
          ),
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
