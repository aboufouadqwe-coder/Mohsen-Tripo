abstract interface class Analytics {
  Future<void> capture(
    String event,
    Map<String, Object?> properties,
  );
}

final class AnalyticsEvents {
  const AnalyticsEvents._();

  static const projectCreated = 'project_created';
  static const referenceImageAdded = 'reference_image_added';
  static const templateSelected = 'template_selected';
  static const generationStarted = 'generation_started';
  static const generationCompleted = 'generation_completed';
  static const generationFailed = 'generation_failed';
  static const partRegenerated = 'part_regenerated';
  static const modelGenerationStarted = 'model_generation_started';
  static const modelGenerationCompleted = 'model_generation_completed';
  static const modelGenerationFailed = 'model_generation_failed';
}

const approvedAnalyticsEvents = <String>{
  AnalyticsEvents.projectCreated,
  AnalyticsEvents.referenceImageAdded,
  AnalyticsEvents.templateSelected,
  AnalyticsEvents.generationStarted,
  AnalyticsEvents.generationCompleted,
  AnalyticsEvents.generationFailed,
  AnalyticsEvents.partRegenerated,
  AnalyticsEvents.modelGenerationStarted,
  AnalyticsEvents.modelGenerationCompleted,
  AnalyticsEvents.modelGenerationFailed,
};

const forbiddenAnalyticsKeys = <String>{
  'authorization',
  'api_key',
  'token',
  'image_bytes',
  'prompt',
};

void validateAnalyticsEvent(
  String event,
  Map<String, Object?> properties,
) {
  if (!approvedAnalyticsEvents.contains(event)) {
    throw ArgumentError.value(
      event,
      'event',
      'Analytics event is not in the approved taxonomy.',
    );
  }

  _validatePropertyMap(properties);
}

void _validatePropertyMap(Map<Object?, Object?> properties) {
  for (final entry in properties.entries) {
    final rawKey = entry.key;
    if (rawKey is! String || rawKey.trim().isEmpty) {
      throw ArgumentError('Analytics property keys must be non-empty strings.');
    }

    final normalizedKey = rawKey.trim().toLowerCase();
    if (forbiddenAnalyticsKeys.contains(normalizedKey)) {
      throw ArgumentError.value(
        rawKey,
        'properties',
        'Sensitive analytics property is forbidden.',
      );
    }

    final value = entry.value;
    if (value is Map) {
      _validatePropertyMap(value.cast<Object?, Object?>());
    } else if (value is Iterable) {
      for (final item in value) {
        if (item is Map) {
          _validatePropertyMap(item.cast<Object?, Object?>());
        }
      }
    }
  }
}

final class AnalyticsBinding {
  const AnalyticsBinding._();

  static Analytics? _current;

  static Analytics? get maybeCurrent => _current;

  static Analytics get current {
    final analytics = _current;
    if (analytics == null) {
      throw StateError('Analytics has not been bound.');
    }
    return analytics;
  }

  static void bind(Analytics analytics) {
    _current = analytics;
  }
}

Future<void> captureAnalyticsSafely(
  Analytics analytics,
  String event,
  Map<String, Object?> properties,
) async {
  try {
    await analytics.capture(event, properties);
  } catch (_) {
    // Analytics is never allowed to fail the user operation.
  }
}
