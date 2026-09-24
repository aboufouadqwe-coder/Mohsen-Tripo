import 'package:flutter/material.dart';

import '../../data/supabase/results_repository.dart';
import '../../domain/assets/asset_result.dart';
import '../../domain/generation/generation_job.dart';
import 'asset_result_card.dart';

final class ResultsGallery extends StatefulWidget {
  const ResultsGallery({
    super.key,
    required this.projectId,
    required this.repository,
    this.onGenerateModel,
    this.imagePreviewBuilder,
    this.refreshVersion = 0,
    this.modelGenerationBusy = false,
    this.activeModelAssetResultId,
    this.modelJob,
  });

  final String projectId;
  final ResultsRepository repository;
  final Future<void> Function(AssetResult asset)? onGenerateModel;
  final ResultImagePreviewBuilder? imagePreviewBuilder;
  final int refreshVersion;
  final bool modelGenerationBusy;
  final String? activeModelAssetResultId;
  final GenerationJob? modelJob;

  @override
  State<ResultsGallery> createState() => _ResultsGalleryState();
}

final class _ResultsGalleryState extends State<ResultsGallery> {
  List<ResultHistoryEntry> _entries = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ResultsGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    try {
      final entries = await widget.repository.listHistory(widget.projectId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  double _progressValue(double progress) {
    if (progress < 0) return 0;
    if (progress > 1) return 1;
    return progress;
  }

  @override
  Widget build(BuildContext context) {
    final modelJob = widget.modelJob;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'النتائج',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'تحديث النتائج',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (modelJob != null && !modelJob.isTerminal) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressValue(modelJob.progress),
          ),
          const SizedBox(height: 4),
          Text(
            'تقدم 3D: ' +
                (modelJob.progress * 100).round().toString() +
                '%',
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('تعذر تحميل سجل النتائج.'),
          )
        else if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('لا توجد نتائج بعد.'),
          )
        else
          ..._entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AssetResultCard(
                key: ValueKey('result-' + entry.job.id),
                entry: entry,
                onGenerateModel: widget.onGenerateModel,
                imagePreviewBuilder: widget.imagePreviewBuilder,
                modelGenerationBusy: widget.modelGenerationBusy,
                activeModelAssetResultId:
                    widget.activeModelAssetResultId,
              ),
            ),
          ),
      ],
    );
  }
}
