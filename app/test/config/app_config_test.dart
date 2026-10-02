import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/config/app_config.dart';

void main() {
  test('requires supabase url and publishable key', () {
    expect(
      () => AppConfig(
        supabaseUrl: '',
        supabasePublishableKey: '',
      ),
      throwsArgumentError,
    );
  });

  test('posthog remains disabled without an api key', () {
    final config = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_test',
    );

    expect(config.posthogEnabled, isFalse);
  });
}
