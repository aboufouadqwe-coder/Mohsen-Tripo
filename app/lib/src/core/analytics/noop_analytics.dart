import 'analytics.dart';

final class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> capture(
    String event,
    Map<String, Object?> properties,
  ) async {
    validateAnalyticsEvent(event, properties);
  }
}
