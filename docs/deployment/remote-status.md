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

## Remaining external gates

### 1. Anonymous Sign-Ins

The Flutter startup flow uses `signInAnonymously()`.

Supabase documentation requires Anonymous Sign-Ins to be enabled in the hosted project's Auth provider settings. The connected Supabase MCP currently exposes no Auth-provider configuration mutation, so this setting cannot be changed from the available toolset.

Required dashboard path:

`Supabase Dashboard -> Mohsen-Tripo -> Authentication -> Providers -> Anonymous Sign-Ins -> Enable`

Before public release, also review CAPTCHA/Turnstile and rate limits for anonymous-auth abuse protection.

### 2. Tripo server secret

The Edge Functions intentionally require `TRIPO_API_KEY` from the server environment.

No connected Supabase tool currently exposes secret-setting. Do not place this value in Flutter, GitHub source, Dart defines, or Gradle.

Until this server-side secret is configured, generation calls will fail safely with a provider configuration error.

### 3. Real-device smoke test

The final paid/provider smoke test remains blocked until:

- Anonymous Sign-Ins is enabled remotely.
- `TRIPO_API_KEY` is configured as an Edge Function secret.

No paid Tripo call is required by CI.
