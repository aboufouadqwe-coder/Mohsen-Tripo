# Mohsen-Tripo

Android-first AI asset generation app built with Flutter, Supabase, and the documented Tripo API v3.

## Product scope

Mohsen-Tripo starts from an imported or AI-generated reference image. A user can:

- create projects under an anonymous Supabase session,
- select or generate a canonical reference image,
- use the built-in Character Parts template or add custom parts,
- generate enabled parts independently with retry/history support,
- preserve successful siblings when another part fails,
- reopen a workspace and resume active jobs,
- browse private persisted results through short-lived signed URLs,
- convert a successful image result to a persisted GLB model plus preview image.

The mobile app is a clean-room implementation. It does not embed Tripo mobile-app code, assets, native binaries, private endpoints, subscriptions, or authentication behavior.

## Architecture

```text
Flutter Android client
        |
        | Supabase publishable key + anonymous JWT
        v
Supabase Auth / Postgres / private Storage
        |
        | authenticated Edge Functions
        v
Tripo public API v3
```

The Tripo API key exists only as a server-side Edge Function secret.

Private Storage buckets:

- `reference-images`
- `generated-images`
- `generated-models`

Generation flow:

```text
submit -> generation_jobs -> poll -> download provider output
       -> private Storage -> asset_results -> UI history
```

## Requirements

- Flutter 3.47 stable
- Android SDK compatible with Flutter 3.47
- Android minSdk 24
- Deno for Edge Function tests
- Supabase CLI + Docker for local database tests

## Android public configuration

The Android client accepts public configuration through Dart defines:

```bash
cd app
flutter run \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_example
```

Only the Supabase URL and publishable key belong in the mobile build.

### Optional PostHog analytics

Analytics is a no-op unless a dedicated Mohsen-Tripo project token is supplied:

```bash
--dart-define=POSTHOG_API_KEY=phc_example \
--dart-define=POSTHOG_HOST=https://us.i.posthog.com
```

The analytics boundary accepts only the approved event taxonomy and rejects sensitive property keys such as:

- `authorization`
- `api_key`
- `token`
- `image_bytes`
- `prompt`

PostHog lifecycle capture and session replay are disabled in this app. Analytics failure never fails the user operation.

## Server secrets

`TRIPO_API_KEY` must be configured only as a Supabase Edge Function secret.

Never place it in:

- Dart defines,
- Flutter source,
- Gradle files,
- GitHub repository files,
- a mobile environment file,
- the APK.

CI scans the Android source and the built release APK for the `TRIPO_API_KEY` marker.

## Local Flutter verification

```bash
cd app
flutter pub get
git diff --exit-code pubspec.lock
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_test
```

The CI release APK is a verification artifact. Production store signing must use a production signing configuration before distribution.

## Local backend verification

From the repository root:

```bash
deno task test
supabase start
supabase db reset
supabase test db
supabase db lint
supabase stop
```

CI never makes real paid Tripo calls. Provider tests inject fake transports.

## Remote deployment gate

Remote Supabase provisioning is deliberately separate from local development.

Before creating a paid Supabase project:

1. choose the Supabase organization,
2. retrieve the exact recurring cost,
3. obtain explicit cost confirmation,
4. create the project,
5. enable Anonymous Sign-Ins,
6. apply migrations,
7. configure `TRIPO_API_KEY` only as an Edge Function secret,
8. deploy the four Edge Functions,
9. run Supabase security/performance advisors,
10. perform the real-device smoke test.

Paid Tripo calls are limited to the manual smoke test.

## Source of truth

- `docs/superpowers/specs/2026-09-24-mohsen-tripo-android-design.md`
- `docs/superpowers/plans/2026-09-24-mohsen-tripo-android-mvp.md`
- `docs/reference/tripo-cleanroom/`

The clean-room reference is architecture input only and is not production code.
