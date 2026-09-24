import '../../data/supabase/generation_gateway.dart';
import '../../domain/generation/generation_job.dart';

typedef PollingDelay = Future<void> Function(Duration duration);

final class JobPollingCancelled implements Exception {
  const JobPollingCancelled();

  @override
  String toString() => 'Job polling was cancelled.';
}

final class JobPollingService {
  JobPollingService({
    required this.gateway,
    PollingDelay? delay,
  }) : _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static const _intervals = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ];

  final GenerationGateway gateway;
  final PollingDelay _delay;
  bool _disposed = false;

  Future<GenerationJob> pollUntilTerminal(String jobId) async {
    var intervalIndex = 0;

    while (true) {
      _throwIfDisposed();

      final job = await gateway.refreshJob(jobId);
      if (job.isTerminal) return job;

      final interval = _intervals[
          intervalIndex < _intervals.length
              ? intervalIndex
              : _intervals.length - 1];
      await _delay(interval);
      _throwIfDisposed();

      if (intervalIndex < _intervals.length - 1) {
        intervalIndex += 1;
      }
    }
  }

  void dispose() {
    _disposed = true;
  }

  void _throwIfDisposed() {
    if (_disposed) throw const JobPollingCancelled();
  }
}
