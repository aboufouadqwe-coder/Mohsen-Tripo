import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/core/analytics/analytics.dart';
import 'package:mohsen_tripo/src/core/analytics/noop_analytics.dart';

void main() {
  test('approved event names are accepted', () {
    for (final event in approvedAnalyticsEvents) {
      expect(
        () => validateAnalyticsEvent(
          event,
          const {'part_key': 'head'},
        ),
        returnsNormally,
      );
    }
  });

  test('unknown event name is rejected', () {
    expect(
      () => validateAnalyticsEvent(
        'arbitrary_internal_event',
        const {},
      ),
      throwsArgumentError,
    );
  });

  test('forbidden property keys are rejected', () {
    for (final key in forbiddenAnalyticsKeys) {
      expect(
        () => validateAnalyticsEvent(
          AnalyticsEvents.generationStarted,
          {key: 'secret'},
        ),
        throwsArgumentError,
      );
    }
  });

  test('forbidden keys are matched case-insensitively', () {
    expect(
      () => validateAnalyticsEvent(
        AnalyticsEvents.generationStarted,
        const {'Authorization': 'secret'},
      ),
      throwsArgumentError,
    );
  });

  test('noop analytics accepts a valid event without side effects', () async {
    final analytics = NoopAnalytics();

    await expectLater(
      analytics.capture(
        AnalyticsEvents.projectCreated,
        const {'template_kind': 'character'},
      ),
      completes,
    );
  });
}
