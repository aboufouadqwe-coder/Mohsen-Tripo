import 'package:posthog_flutter/posthog_flutter.dart';

import 'analytics.dart';
import 'noop_analytics.dart';

final class PosthogAnalytics implements Analytics {
  PosthogAnalytics._(this._client);

  final Posthog _client;

  static Future<PosthogAnalytics> create({
    required String projectToken,
    required String host,
  }) async {
    final token = projectToken.trim();
    if (token.isEmpty) {
      throw ArgumentError.value(
        projectToken,
        'projectToken',
        'PostHog project token is required.',
      );
    }

    final client = Posthog();
    final config = PostHogConfig(token)
      ..host = host.trim()
      ..captureApplicationLifecycleEvents = false
      ..sessionReplay = false
      ..preloadFeatureFlags = false
      ..sendFeatureFlagEvents = false;

    await client.setup(config);
    return PosthogAnalytics._(client);
  }

  @override
  Future<void> capture(
    String event,
    Map<String, Object?> properties,
  ) async {
    validateAnalyticsEvent(event, properties);

    final sanitized = <String, Object>{};
    for (final entry in properties.entries) {
      final value = entry.value;
      if (value == null) continue;
      sanitized[entry.key] = _sanitizeValue(value);
    }

    await _client.capture(
      eventName: event,
      properties: sanitized.isEmpty ? null : sanitized,
    );
  }

  Object _sanitizeValue(Object value) {
    if (value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      final output = <String, Object>{};
      for (final entry in value.entries) {
        final key = entry.key;
        final nestedValue = entry.value;
        if (key is! String || nestedValue == null) continue;
        output[key] = _sanitizeValue(nestedValue);
      }
      return output;
    }
    if (value is Iterable) {
      return value
          .where((item) => item != null)
          .map((item) => _sanitizeValue(item!))
          .toList(growable: false);
    }

    throw ArgumentError.value(
      value,
      'properties',
      'Unsupported analytics property type.',
    );
  }
}

Future<Analytics> createConfiguredAnalytics({
  required String? projectToken,
  required String host,
}) async {
  final token = projectToken?.trim();
  if (token == null || token.isEmpty) {
    return const NoopAnalytics();
  }

  try {
    return await PosthogAnalytics.create(
      projectToken: token,
      host: host,
    );
  } catch (_) {
    return const NoopAnalytics();
  }
}
