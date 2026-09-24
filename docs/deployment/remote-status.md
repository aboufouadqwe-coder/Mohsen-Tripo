# Mohsen-Tripo Remote Deployment Status

Last updated: 2026-09-25

## Hosted Supabase project

- Project: `Mohsen-Tripo`
- Project ref: `zzsjejluvufjtaxsqjme`
- Region: `eu-central-1`
- Organization: `aboufouadqwe-coder's Org`
- Supabase plan: Free
- Project creation cost: 0/month
- Project status at creation: `ACTIVE_HEALTHY`
- API URL: `https://zzsjejluvufjtaxsqjme.supabase.co`

The mobile app uses the project's public publishable key only. No service-role or provider secret is stored in Flutter, Gradle, GitHub source, or the APK.

## Database

Applied remote migrations:

1. `initial_schema`
2. `add_fk_indexes`

Remote tables:

- `projects`
- `asset_templates`
- `template_parts`
- `generation_jobs`
- `asset_results`

All exposed application tables have RLS enabled.

Seed data:

- 1 built-in Character Parts template
- 7 built-in parts

Storage buckets:

- `reference-images` — private
- `generated-images` — private
- `generated-models` — private

Storage access is scoped by the authenticated user's UID in the first path segment.

## Edge Functions

Deployed and ACTIVE with JWT verification enabled:

- `generate-source-image`
- `generate-image-part`
- `generate-model`
- `refresh-generation-job`

## Advisors

Security Advisor:

- no findings after schema deployment and index migration.

Performance Advisor:

- no missing-FK-index findings remain.
- only `unused_index` informational notices remain, which are expected on a newly created database with no production traffic.

## Android verification

Automated verification completed before remote binding:

- Flutter analyze: pass
- Flutter tests: 47/47 pass
- Android minSdk: 24
- release APK build: pass
- release APK backend-secret marker scan: pass

CI now builds against the hosted free Supabase project and uploads `app-release.apk` as the `mohsen-tripo-android-release` artifact.

## Remote runtime configuration

### Anonymous Sign-Ins

Enabled in the hosted Supabase Auth provider settings.

The Flutter startup flow uses `signInAnonymously()`, so the app can now establish an authenticated anonymous session and satisfy RLS ownership policies.

Before public release, review CAPTCHA/Turnstile and rate limits for anonymous-auth abuse protection.

### Tripo server secret

`TRIPO_API_KEY` has been configured as an Edge Function/server secret in Supabase.

The secret value is intentionally not stored in Flutter, GitHub source, Dart defines, Gradle, or this document.

## Remaining external gate

### Real-device smoke test

The remaining gate is a real Android-device smoke test of the hosted flow:

1. launch the release APK,
2. establish the anonymous Supabase session,
3. create a project,
4. add or generate a reference image,
5. submit one generation request,
6. poll it to terminal state,
7. verify the result is persisted and visible,
8. optionally test image-to-3D only if it can be done without paid usage.

No automatic GitHub Action should be started for this test.
