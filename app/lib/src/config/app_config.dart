final class AppConfig {
  AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.posthogApiKey,
    this.posthogHost = 'https://us.i.posthog.com',
  }) {
    if (supabaseUrl.trim().isEmpty || supabasePublishableKey.trim().isEmpty) {
      throw ArgumentError('Supabase configuration is required.');
    }
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String? posthogApiKey;
  final String posthogHost;

  bool get posthogEnabled => posthogApiKey?.trim().isNotEmpty ?? false;

  factory AppConfig.fromEnvironment() {
    const posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');

    return AppConfig(
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey:
          const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      posthogApiKey: posthogApiKey.isEmpty ? null : posthogApiKey,
      posthogHost: const String.fromEnvironment(
        'POSTHOG_HOST',
        defaultValue: 'https://us.i.posthog.com',
      ),
    );
  }
}
