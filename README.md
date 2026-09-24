# Mohsen-Tripo

Android-first AI asset generation app built with Flutter, Supabase, and Tripo API v3.

## MVP direction

A project starts from an imported or AI-generated reference image. The user selects a reusable parts template (head, hands, feet, clothing, accessories, and custom parts), and each enabled part is generated as a **new image** through Tripo image-to-image. Selected image results can then be converted to 3D.

## Security boundary

- The Android app receives only a Supabase publishable key.
- The Tripo API key must never be committed or bundled in the APK.
- Tripo requests will be issued from authenticated Supabase Edge Functions.
- User data will be protected by Row Level Security.

## Local configuration

Pass public Supabase values with Dart defines:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_example
```

Do **not** pass the Tripo API key through Dart defines, Gradle properties, source files, or mobile build configuration.

## Verification

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_test
```

The implementation source of truth is:

- `docs/superpowers/specs/2026-09-24-mohsen-tripo-android-design.md`
- `docs/superpowers/plans/2026-09-24-mohsen-tripo-android-mvp.md`
