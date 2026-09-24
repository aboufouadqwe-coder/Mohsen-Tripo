import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/domain/generation/generation_job.dart';
import 'package:mohsen_tripo/src/features/workspace/job_polling_service.dart';

GenerationJob job(GenerationStatus status, {double progress = 0}) {
  return GenerationJob(
    id: 'job-1',
    projectId: 'project-1',
    provider: 'tripo',
    operation: GenerationOperation.imageToImage,
    status: status,
    partKey: 'head',
    progress: progress,
  );
}

final class FakePollingGateway implements GenerationGateway {
  FakePollingGateway(this.jobs);

  final List<GenerationJob> jobs;
  int refreshCalls = 0;

  @override
  Future<GenerationJob> refreshJob(String jobId) async {
    final index = refreshCalls < jobs.length ? refreshCalls : jobs.length - 1;
    refreshCalls += 1;
    return jobs[index];
  }

  @override
  Future<String> generateSourceImage({
    required String projectId,
    required String prompt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? customInstructions,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateModel(String assetResultId) {
    throw UnimplementedError();
  }
}

void main() {
  test('polling uses exponential delays capped at ten seconds', () async {
    final gateway = FakePollingGateway([
      job(GenerationStatus.queued),
      job(GenerationStatus.running, progress: 0.1),
      job(GenerationStatus.running, progress: 0.3),
      job(GenerationStatus.running, progress: 0.6),
      job(GenerationStatus.running, progress: 0.9),
      job(GenerationStatus.success, progress: 1),
    ]);
    final delays = <Duration>[];

    final service = JobPollingService(
      gateway: gateway,
      delay: (duration) async => delays.add(duration),
    );

    final result = await service.pollUntilTerminal('job-1');

    expect(result.status, GenerationStatus.success);
    expect(
      delays,
      const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 10),
      ],
    );
  });

  test('terminal job returns without sleeping again', () async {
    final delays = <Duration>[];
    final service = JobPollingService(
      gateway: FakePollingGateway([
        job(GenerationStatus.success, progress: 1),
      ]),
      delay: (duration) async => delays.add(duration),
    );

    final result = await service.pollUntilTerminal('job-1');

    expect(result.isTerminal, isTrue);
    expect(delays, isEmpty);
  });

  test('dispose stops an active polling loop', () async {
    late final JobPollingService service;
    service = JobPollingService(
      gateway: FakePollingGateway([
        job(GenerationStatus.running, progress: 0.1),
        job(GenerationStatus.success, progress: 1),
      ]),
      delay: (_) async {
        service.dispose();
      },
    );

    await expectLater(
      service.pollUntilTerminal('job-1'),
      throwsA(isA<JobPollingCancelled>()),
    );
  });
}
