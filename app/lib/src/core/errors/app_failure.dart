enum AppFailureCategory {
  authentication,
  validation,
  data,
  function,
  storage,
  unknown,
}

final class AppFailure implements Exception {
  const AppFailure({
    required this.category,
    required this.message,
  });

  final AppFailureCategory category;
  final String message;

  factory AppFailure.authentication() => const AppFailure(
        category: AppFailureCategory.authentication,
        message: 'Authentication could not be completed.',
      );

  factory AppFailure.validation(String message) => AppFailure(
        category: AppFailureCategory.validation,
        message: message,
      );

  factory AppFailure.data() => const AppFailure(
        category: AppFailureCategory.data,
        message: 'Project data could not be loaded or saved.',
      );

  factory AppFailure.function() => const AppFailure(
        category: AppFailureCategory.function,
        message: 'Generation service request could not be completed.',
      );

  factory AppFailure.storage() => const AppFailure(
        category: AppFailureCategory.storage,
        message: 'Asset storage request could not be completed.',
      );

  @override
  String toString() => 'AppFailure(${category.name}): $message';
}
