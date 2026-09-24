# Mohsen-Tripo Android MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android-first Flutter application that turns one reference image into a structured set of newly generated image assets through Tripo v3, persists results in Supabase, and can convert a selected generated image into a 3D model.

**Architecture:** Flutter is the Android client. Supabase provides anonymous auth, Postgres, Storage, and authenticated Edge Functions. Tripo v3 is called only from Edge Functions using a server-side API key; the Flutter APK never receives the Tripo secret. PostHog is behind an analytics port and remains disabled until a dedicated Mohsen-Tripo project key is configured.

**Tech Stack:** Flutter 3.47 stable; Dart as bundled with Flutter 3.47; `supabase_flutter 2.17.2`; `flutter_riverpod 3.4.3`; `go_router 18.0.1`; `image_picker 1.2.3`; `path_provider 2.1.6`; `uuid 4.6.0`; `mocktail 1.0.5`; Supabase CLI + Postgres + pgTAP; Supabase Edge Functions with Deno/TypeScript; Tripo API v3.

**Spec:** `docs/superpowers/specs/2026-09-24-mohsen-tripo-android-design.md`

## Global Constraints

- Target Android first; no iOS or Windows work in this plan.
- Minimum Android SDK: 24.
- Tripo base URL: `https://openapi.tripo3d.ai/v3`.
- Image generation operation: `POST /v3/generation/image-to-image`.
- Image-to-3D operation: `POST /v3/generation/image-to-model`.
- Task polling operation: `GET /v3/tasks/{task_id}`.
- Pin image generation to `seedream_v5` for the MVP; do not rely on a mutable provider default.
- Pin 3D generation to `tripo-v3.1` for the MVP.
- Never commit or bundle the Tripo API key.
- Never expose a Supabase secret/service-role key to Flutter.
- The Android client may contain only a Supabase publishable key.
- Every exposed user-owned table must have RLS enabled and enforce ownership with `auth.uid()`.
- Authentication is Supabase Anonymous Sign-Ins via `signInAnonymously()`.
- A failed part generation must not discard successful sibling generations.
- CI must not make real paid Tripo requests.
- No proprietary Tripo mobile-app internal endpoints are allowed.

## Review Focus

1. **Anonymous session loss:** clearing app data must not corrupt shared data; the app should simply create a new anonymous user and show no prior projects. Covered in Task 6 auth bootstrap tests.
2. **Cross-user access:** a second authenticated user must be unable to read/update/delete another user's projects, jobs, results, or storage objects. Covered in Task 3 pgTAP/RLS tests.
3. **Partial batch failure:** one failed Tripo job must remain failed while successful sibling jobs remain visible and persisted. Covered in Task 8 controller tests.
4. **Provider output expiration or download failure:** a successful Tripo task whose result cannot be persisted must become a persistence failure without being reported as a successful asset. Covered in Task 5 Edge Function tests.
5. **Provider contract drift:** unexpected Tripo status or malformed payload must map to an explicit provider failure rather than crash or silently succeed. Covered in Task 4 provider-contract tests.

---

## Locked Repository Structure

```text
/
├── app/
│   ├── android/
│   ├── lib/
│   │   ├── main.dart
│   │   └── src/
│   │       ├── app.dart
│   │       ├── config/
│   │       │   └── app_config.dart
│   │       ├── core/
│   │       │   ├── analytics/
│   │       │   ├── errors/
│   │       │   └── routing/
│   │       ├── domain/
│   │       │   ├── assets/
│   │       │   ├── generation/
│   │       │   ├── projects/
│   │       │   └── templates/
│   │       ├── data/
│   │       │   └── supabase/
│   │       └── features/
│   │           ├── bootstrap/
│   │           ├── projects/
│   │           ├── workspace/
│   │           └── results/
│   └── test/
├── supabase/
│   ├── config.toml
│   ├── functions/
│   │   ├── _shared/
│   │   ├── generate-image-part/
│   │   ├── refresh-generation-job/
│   │   ├── generate-model/
│   │   └── tests/
│   ├── migrations/
│   └── tests/
│       └── database/
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── .gitignore
├── README.md
└── LICENSE
```

---

### Task 1: Bootstrap Flutter Android App and CI

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`
- Create: `app/lib/src/app.dart`
- Create: `app/lib/src/config/app_config.dart`
- Create: `app/test/config/app_config_test.dart`
- Create: `app/analysis_options.yaml`
- Create: `.github/workflows/ci.yml`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Produces: `AppConfig` with `supabaseUrl`, `supabasePublishableKey`, optional PostHog configuration.
- Produces: `MohsenTripoApp` root widget.
- Consumes: none.

- [ ] **Step 1: Scaffold Android-only Flutter project**

Run:

```bash
flutter create --platforms=android --org com.mohsentripo app
cd app
flutter pub add supabase_flutter:2.17.2 flutter_riverpod:3.4.3 go_router:18.0.1 image_picker:1.2.3 path_provider:2.1.6 uuid:4.6.0
flutter pub add --dev mocktail:1.0.5
```

Then set Android `minSdk = 24` in the generated Gradle configuration.

- [ ] **Step 2: Write failing configuration tests**

Create `app/test/config/app_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/config/app_config.dart';

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
```

Run:

```bash
cd app
flutter test test/config/app_config_test.dart
```

Expected: FAIL because `AppConfig` does not exist.

- [ ] **Step 3: Implement minimal AppConfig**

Create `app/lib/src/config/app_config.dart`:

```dart
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

  factory AppConfig.fromEnvironment() => AppConfig(
        supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
        supabasePublishableKey:
            const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        posthogApiKey: const String.fromEnvironment('POSTHOG_API_KEY').isEmpty
            ? null
            : const String.fromEnvironment('POSTHOG_API_KEY'),
        posthogHost: const String.fromEnvironment(
          'POSTHOG_HOST',
          defaultValue: 'https://us.i.posthog.com',
        ),
      );
}
```

- [ ] **Step 4: Add root app and main entrypoint**

`app/lib/src/app.dart`:

```dart
import 'package:flutter/material.dart';

class MohsenTripoApp extends StatelessWidget {
  const MohsenTripoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mohsen Tripo',
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(child: Text('Mohsen Tripo')),
      ),
    );
  }
}
```

`app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/app.dart';
import 'src/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  runApp(ProviderScope(child: MohsenTripoApp(key: ValueKey(config.supabaseUrl))));
}
```

- [ ] **Step 5: Add CI**

Create `.github/workflows/ci.yml` with jobs that run:

```bash
flutter pub get
flutter analyze
flutter test
```

from `app/`, plus later Supabase/Deno jobs added by Tasks 3–5.

- [ ] **Step 6: Verify bootstrap**

Run:

```bash
cd app
flutter analyze
flutter test
flutter build apk --debug   --dart-define=SUPABASE_URL=https://example.supabase.co   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_test
```

Expected: PASS and a debug APK is produced.

- [ ] **Step 7: Commit**

```bash
git add app .github/workflows/ci.yml .gitignore README.md
git commit -m "chore: bootstrap Android Flutter app"
```

---

### Task 2: Domain Models, Built-in Character Template, and Prompt Preview

**Files:**
- Create: `app/lib/src/domain/templates/asset_template.dart`
- Create: `app/lib/src/domain/templates/template_part.dart`
- Create: `app/lib/src/domain/templates/builtin_templates.dart`
- Create: `app/lib/src/domain/projects/project.dart`
- Create: `app/lib/src/domain/generation/generation_job.dart`
- Create: `app/lib/src/domain/assets/asset_result.dart`
- Create: `app/lib/src/domain/generation/prompt_preview_builder.dart`
- Create: `app/test/domain/prompt_preview_builder_test.dart`
- Create: `app/test/domain/builtin_templates_test.dart`

**Interfaces:**
- Produces: immutable domain records used by repositories and UI.
- Produces: `PromptPreviewBuilder.build(Project project, TemplatePart part, {String? customInstructions}) -> String`.
- Consumes: none.

- [ ] **Step 1: Write failing tests for the built-in template**

```dart
test('character parts template ships with required defaults', () {
  final template = BuiltinTemplates.characterParts;
  expect(template.parts.map((p) => p.key), containsAll([
    'head',
    'right_hand',
    'left_hand',
    'right_foot',
    'left_foot',
    'clothing',
    'accessories',
  ]));
});
```

Run:

```bash
cd app
flutter test test/domain/builtin_templates_test.dart
```

Expected: FAIL because the template types do not exist.

- [ ] **Step 2: Implement domain records and built-in template**

Use immutable Dart classes. `TemplatePart` must contain:

```dart
final class TemplatePart {
  const TemplatePart({
    required this.key,
    required this.label,
    required this.promptFragment,
    required this.sortOrder,
    this.enabledByDefault = true,
  });

  final String key;
  final String label;
  final String promptFragment;
  final int sortOrder;
  final bool enabledByDefault;
}
```

The built-in template must contain the exact seven MVP parts from Step 1.

- [ ] **Step 3: Write failing prompt-preview tests**

```dart
test('combines identity, part instruction, and custom instruction', () {
  final prompt = PromptPreviewBuilder().build(
    const Project(
      id: 'p1',
      name: 'Patient',
      referenceImagePath: 'u/p1/reference.png',
      identityPrompt: 'Young male patient with old brown hospital clothes.',
    ),
    const TemplatePart(
      key: 'injured_arm',
      label: 'الذراع المصابة',
      promptFragment: 'Generate the injured arm clearly and completely.',
      sortOrder: 0,
    ),
    customInstructions: 'Keep the exact head-bandage visual language.',
  );

  expect(prompt, contains('Young male patient'));
  expect(prompt, contains('injured arm'));
  expect(prompt, contains('head-bandage'));
  expect(prompt, contains('same character'));
});
```

- [ ] **Step 4: Implement PromptPreviewBuilder**

The output must follow this deterministic order:

```text
Generate a clean isolated reference image of the same character.
Identity: {identityPrompt}
Requested asset: {label}
Instruction: {promptFragment}
Additional instruction: {customInstructions when present}
Preserve identity, proportions, materials, colors, clothing design, damage, and accessories from the reference image.
Show only the requested asset clearly and completely.
```

Reject an empty part label or empty prompt fragment with `ArgumentError`.

- [ ] **Step 5: Verify domain layer**

Run:

```bash
cd app
flutter test test/domain/
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/src/domain app/test/domain
git commit -m "feat: add asset generation domain model"
```

---

### Task 3: Supabase Schema, Storage, and RLS Tests

**Files:**
- Create via CLI: `supabase/config.toml`
- Create via CLI: `supabase/migrations/*_initial_schema.sql`
- Create: `supabase/tests/database/schema_test.sql`
- Create: `supabase/tests/database/rls_test.sql`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces tables: `projects`, `asset_templates`, `template_parts`, `generation_jobs`, `asset_results`.
- Produces buckets: `reference-images`, `generated-images`, `generated-models`.
- Consumes Supabase Auth `auth.uid()`.

- [ ] **Step 1: Initialize Supabase and create migration through the CLI**

Run:

```bash
supabase init
supabase migration new initial_schema
```

Use the exact migration filename printed by the CLI. Do not hand-name the migration.

- [ ] **Step 2: Write schema migration**

The migration must create UUID primary keys, timestamps, foreign keys, and these ownership fields:

```sql
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  reference_image_path text,
  template_id uuid,
  identity_prompt text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.asset_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  is_builtin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((is_builtin and owner_id is null) or (not is_builtin and owner_id is not null))
);
```

Add `template_parts`, `generation_jobs`, and `asset_results` matching the design spec. Add the deferred `projects.template_id` foreign key after `asset_templates` exists.

Enable RLS on all five tables.

- [ ] **Step 3: Add least-privilege RLS policies**

For `projects`, use ownership predicates equivalent to:

```sql
create policy "projects_select_own"
on public.projects for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy "projects_insert_own"
on public.projects for insert
to authenticated
with check ((select auth.uid()) = owner_id);

create policy "projects_update_own"
on public.projects for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "projects_delete_own"
on public.projects for delete
to authenticated
using ((select auth.uid()) = owner_id);
```

For built-in templates, authenticated users may read rows where `is_builtin = true`; custom templates require `owner_id = auth.uid()`. Client writes must never mutate built-in templates.

For `template_parts`, authorize through the parent template.

For `generation_jobs` and `asset_results`, authorize through the parent project owner.

- [ ] **Step 4: Create private buckets and storage policies**

Insert the three buckets with `public = false`. Storage object paths must start with `auth.uid()::text`.

A user may read/write only objects where:

```sql
(storage.foldername(name))[1] = (select auth.uid())::text
```

- [ ] **Step 5: Seed the built-in Character Parts template**

Insert one immutable built-in template plus the seven default parts from Task 2.

- [ ] **Step 6: Write pgTAP schema tests**

`schema_test.sql` must assert:

- all five tables exist,
- RLS is enabled,
- all three buckets exist,
- built-in template has seven expected parts.

- [ ] **Step 7: Write pgTAP cross-user RLS tests**

Create two test users and assert:

```sql
-- owner can see own project
select results_eq(
  $$ select count(*) from public.projects where owner_id = '11111111-1111-1111-1111-111111111111'::uuid $$,
  array[1::bigint],
  'owner sees own project'
);

-- second user cannot see first user's project
select results_eq(
  $$ select count(*) from public.projects where owner_id = '11111111-1111-1111-1111-111111111111'::uuid $$,
  array[0::bigint],
  'other user cannot see project'
);
```

The test must also cover job/result isolation and built-in template visibility.

- [ ] **Step 8: Verify locally**

Run:

```bash
supabase start
supabase db reset
supabase test db
supabase db lint
supabase stop
```

Expected: all pgTAP tests pass and lint reports no blocking schema issues.

- [ ] **Step 9: Add DB test job to CI and commit**

```bash
git add supabase .github/workflows/ci.yml
git commit -m "feat: add Supabase schema and RLS"
```

---

### Task 4: Tripo Provider Contract and Authoritative Prompt Builder

**Files:**
- Create: `supabase/functions/_shared/tripo_client.ts`
- Create: `supabase/functions/_shared/tripo_types.ts`
- Create: `supabase/functions/_shared/prompt_builder.ts`
- Create: `supabase/functions/_shared/provider_error.ts`
- Create: `supabase/functions/tests/tripo_client_test.ts`
- Create: `supabase/functions/tests/prompt_builder_test.ts`
- Create: `supabase/deno.json`

**Interfaces:**
- Produces: `TripoClient.createImageToImage(request)`.
- Produces: `TripoClient.createImageToModel(request)`.
- Produces: `TripoClient.getTask(taskId)`.
- Produces: `buildAssetPrompt(projectIdentity, partLabel, partPrompt, customInstructions)`.
- Consumes: `TRIPO_API_KEY` only from server environment.

- [ ] **Step 1: Write failing contract tests**

Test these cases with mocked `fetch`:

1. HTTP 200 + `code: 0` + `task_id` returns a task id.
2. HTTP 200 + nonzero Tripo `code` throws `ProviderError`.
3. HTTP 200 + missing `task_id` throws `ProviderError('malformed_response')`.
4. Unknown task status throws `ProviderError('unknown_status')`.
5. No API key throws before network access.

Use task statuses exactly:

```ts
export type TripoTaskStatus =
  | "queued"
  | "running"
  | "success"
  | "failed"
  | "cancelled";
```

- [ ] **Step 2: Implement TripoClient**

Use:

```ts
const TRIPO_BASE_URL = "https://openapi.tripo3d.ai/v3";
const IMAGE_MODEL = "seedream_v5";
const MODEL_3D = "tripo-v3.1";
```

Image request:

```ts
await fetch(`${TRIPO_BASE_URL}/generation/image-to-image`, {
  method: "POST",
  headers: {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    input,
    prompt,
    model: IMAGE_MODEL,
    size: "2K",
    output_format: "png",
  }),
});
```

3D request:

```ts
await fetch(`${TRIPO_BASE_URL}/generation/image-to-model`, {
  method: "POST",
  headers: {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    input,
    model: MODEL_3D,
    texture: true,
    pbr: true,
  }),
});
```

For image-generated sources, `input` should be the previous Tripo image-generation `task_id` when available.

- [ ] **Step 3: Implement authoritative server prompt builder**

Use the same semantic order as Task 2. Clamp `customInstructions` to 1000 characters and reject control-only/blank input.

- [ ] **Step 4: Verify provider contract tests**

Run:

```bash
deno task test
deno fmt --check supabase/functions
deno lint supabase/functions
```

Expected: PASS with no real Tripo request.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared supabase/functions/tests supabase/deno.json
git commit -m "feat: add Tripo provider contract"
```

---

### Task 5: Authenticated Edge Functions for Image Generation, Polling, and 3D

**Files:**
- Create: `supabase/functions/generate-image-part/index.ts`
- Create: `supabase/functions/refresh-generation-job/index.ts`
- Create: `supabase/functions/generate-model/index.ts`
- Create: `supabase/functions/_shared/supabase_user.ts`
- Create: `supabase/functions/_shared/http.ts`
- Create: `supabase/functions/tests/generate_image_part_test.ts`
- Create: `supabase/functions/tests/refresh_generation_job_test.ts`
- Create: `supabase/functions/tests/generate_model_test.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- Produces HTTP function `generate-image-part` -> `{ job_id: string }`.
- Produces HTTP function `refresh-generation-job` -> normalized job JSON.
- Produces HTTP function `generate-model` -> `{ job_id: string }`.
- Consumes authenticated user JWT and Task 4 provider client.

- [ ] **Step 1: Write failing authorization tests**

For each function test:

- missing Authorization header -> 401,
- project/result not owned by caller -> 404,
- malformed body -> 400,
- provider nonzero response -> 502 with redacted provider error,
- no response may include the Tripo API key.

- [ ] **Step 2: Implement `generate-image-part`**

Request body:

```ts
type GenerateImagePartBody = {
  project_id: string;
  part_key: string;
  custom_instructions?: string;
};
```

Flow:

1. authenticate caller,
2. load owned project,
3. load part from selected template,
4. create a short-lived signed URL for the private reference image or upload it to Tripo Files API when signed URL routing is unsuitable,
5. build authoritative prompt,
6. call image-to-image,
7. insert `generation_jobs` row with `provider = 'tripo'`, `operation = 'image_to_image'`, and returned task id,
8. return internal job id.

Never store the Authorization header, API key, or unredacted secret material in `request_payload_redacted`.

- [ ] **Step 3: Implement `refresh-generation-job`**

When Tripo status is:

- `queued` or `running`: update status/progress and return.
- `failed` or `cancelled`: persist terminal failure and return.
- `success`: download the provider output, verify MIME is an allowed image/model type, upload to the correct private Supabase bucket, create `asset_results`, mark job successful only after persistence succeeds.

If provider output download/storage upload fails, persist `status = 'failed'` and `error_code = 'persistence_failed'`.

- [ ] **Step 4: Implement `generate-model`**

Input:

```ts
type GenerateModelBody = {
  asset_result_id: string;
};
```

Load the owned image result and its source `generation_job`. For Tripo-generated images, submit the original provider image task id as the `input` to `/generation/image-to-model`. Insert a model-generation job with `operation = 'image_to_model'`.

- [ ] **Step 5: Configure JWT verification**

Keep JWT verification enabled for all three user-facing functions.

- [ ] **Step 6: Verify Edge Functions**

Run:

```bash
deno task test
deno fmt --check supabase/functions
deno lint supabase/functions
```

Expected: PASS.

- [ ] **Step 7: Extend CI and commit**

CI must run Deno tests without `TRIPO_API_KEY`; tests inject a fake provider transport.

```bash
git add supabase/functions supabase/config.toml .github/workflows/ci.yml
git commit -m "feat: add authenticated generation functions"
```

---

### Task 6: Flutter Supabase Bootstrap, Anonymous Auth, and Repositories

**Files:**
- Create: `app/lib/src/features/bootstrap/session_bootstrapper.dart`
- Create: `app/lib/src/data/supabase/supabase_clients.dart`
- Create: `app/lib/src/data/supabase/project_repository.dart`
- Create: `app/lib/src/data/supabase/template_repository.dart`
- Create: `app/lib/src/data/supabase/reference_image_repository.dart`
- Create: `app/lib/src/data/supabase/generation_gateway.dart`
- Create: `app/lib/src/core/errors/app_failure.dart`
- Create: `app/test/features/bootstrap/session_bootstrapper_test.dart`
- Create: `app/test/data/project_repository_test.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Produces: `SessionBootstrapper.ensureSession()`.
- Produces: project/template repositories.
- Produces: `GenerationGateway.generateImagePart`, `refreshJob`, `generateModel`.
- Consumes: Supabase URL/publishable key from Task 1.

- [ ] **Step 1: Write failing anonymous-auth tests**

Use a fake auth port:

```dart
test('creates anonymous session when no session exists', () async {
  final auth = FakeAuthPort(currentUserId: null);
  final bootstrapper = SessionBootstrapper(auth);
  await bootstrapper.ensureSession();
  expect(auth.signInAnonymouslyCalls, 1);
});

test('reuses existing anonymous session', () async {
  final auth = FakeAuthPort(currentUserId: 'user-1');
  final bootstrapper = SessionBootstrapper(auth);
  await bootstrapper.ensureSession();
  expect(auth.signInAnonymouslyCalls, 0);
});
```

- [ ] **Step 2: Implement auth abstraction and bootstrapper**

`ensureSession()` must:

1. return current user id when session exists,
2. otherwise call `supabase.auth.signInAnonymously()`,
3. require returned user id,
4. map auth errors to `AppFailure.authentication`.

- [ ] **Step 3: Initialize Supabase before runApp**

Update `main.dart` to call:

```dart
await Supabase.initialize(
  url: config.supabaseUrl,
  anonKey: config.supabasePublishableKey,
);
```

The identifier remains `anonKey` in the Flutter API even when the configured value is a modern publishable key.

- [ ] **Step 4: Implement repositories**

Repository methods:

```dart
abstract interface class ProjectRepository {
  Future<List<Project>> listProjects();
  Future<Project> createProject({
    required String name,
    required String identityPrompt,
  });
  Future<Project> setReferenceImage(String projectId, String localPath);
}

abstract interface class GenerationGateway {
  Future<String> generateImagePart({
    required String projectId,
    required String partKey,
    String? customInstructions,
  });
  Future<GenerationJob> refreshJob(String jobId);
  Future<String> generateModel(String assetResultId);
}
```

- [ ] **Step 5: Add lost-session behavior test**

Simulate a new anonymous user id and verify repository list returns an empty project list rather than treating old rows as accessible.

- [ ] **Step 6: Verify**

```bash
cd app
flutter test test/features/bootstrap test/data
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/lib app/test
git commit -m "feat: add Supabase auth and repositories"
```

---

### Task 7: Android Project and Workspace UI

**Files:**
- Create: `app/lib/src/core/routing/app_router.dart`
- Create: `app/lib/src/features/projects/project_list_page.dart`
- Create: `app/lib/src/features/projects/create_project_page.dart`
- Create: `app/lib/src/features/workspace/workspace_page.dart`
- Create: `app/lib/src/features/workspace/template_editor.dart`
- Create: `app/lib/src/features/workspace/part_request_tile.dart`
- Create: `app/lib/src/features/workspace/reference_image_picker.dart`
- Create: `app/test/features/projects/project_list_page_test.dart`
- Create: `app/test/features/workspace/template_editor_test.dart`
- Create: `app/test/features/workspace/workspace_page_test.dart`
- Modify: `app/lib/src/app.dart`

**Interfaces:**
- Produces routes `/`, `/projects/new`, `/projects/:id`.
- Consumes repositories from Task 6 and domain types from Task 2.

- [ ] **Step 1: Write failing widget test for project list**

Verify empty state contains an Arabic-friendly primary action and tapping it routes to project creation.

- [ ] **Step 2: Implement routing and project list**

Use `go_router`. Keep the UI Material 3, dark-mode capable, and optimized for portrait Android.

- [ ] **Step 3: Write failing template editor tests**

Test:

- built-in parts appear in stable order,
- toggle disables a part,
- custom part can be added with Arabic label `ضمادات الرأس`,
- blank custom part is rejected,
- reorder changes order only, not stable key identity.

- [ ] **Step 4: Implement TemplateEditor**

Custom part keys are generated as UUIDs; display labels remain user text.

- [ ] **Step 5: Write failing image-picker validation tests**

Reject unsupported or oversized input before upload. For MVP:

- accepted: PNG/JPEG,
- max local upload size: 20 MB,
- show a user-visible validation error.

- [ ] **Step 6: Implement reference-image selection and upload**

Use `image_picker`; upload to:

```text
<user_id>/<project_id>/reference.<ext>
```

Then persist the object path on the project row.

- [ ] **Step 7: Verify widgets**

```bash
cd app
flutter test test/features/projects test/features/workspace
flutter analyze
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/lib/src/features app/lib/src/core/routing app/test/features
git commit -m "feat: add project workspace UI"
```

---

### Task 8: Generate-All Coordinator, Polling, and Partial-Failure Isolation

**Files:**
- Create: `app/lib/src/features/workspace/generation_batch_controller.dart`
- Create: `app/lib/src/features/workspace/job_polling_service.dart`
- Create: `app/lib/src/features/workspace/generation_state.dart`
- Create: `app/test/features/workspace/generation_batch_controller_test.dart`
- Create: `app/test/features/workspace/job_polling_service_test.dart`
- Modify: `app/lib/src/features/workspace/workspace_page.dart`
- Modify: `app/lib/src/features/workspace/part_request_tile.dart`

**Interfaces:**
- Produces: `GenerationBatchController.generateAll()`.
- Produces: `GenerationBatchController.regeneratePart(partKey)`.
- Produces: `JobPollingService.pollUntilTerminal(jobId)`.
- Consumes: `GenerationGateway`.

- [ ] **Step 1: Write failing partial-failure test**

```dart
test('one failed part does not erase successful siblings', () async {
  final gateway = FakeGenerationGateway()
    ..resultByPart = {
      'head': FakeJob.success('head-result'),
      'left_hand': FakeJob.failure('provider_failed'),
      'right_hand': FakeJob.success('right-result'),
    };

  final controller = GenerationBatchController(gateway: gateway);
  await controller.generateAll(parts: const ['head', 'left_hand', 'right_hand']);

  expect(controller.state['head']!.isSuccess, isTrue);
  expect(controller.state['left_hand']!.isFailure, isTrue);
  expect(controller.state['right_hand']!.isSuccess, isTrue);
});
```

- [ ] **Step 2: Implement submission behavior**

Submit enabled parts one by one to create provider tasks quickly; do not wait for one task to finish before submitting the next.

- [ ] **Step 3: Implement shared polling loop**

Poll active jobs with exponential intervals capped at 10 seconds:

```text
1s → 2s → 4s → 8s → 10s → 10s...
```

Stop polling when all jobs are terminal or when the controller is disposed.

- [ ] **Step 4: Add lifecycle-safe resume**

When the app resumes or workspace reopens, load non-terminal jobs from the database and resume polling.

- [ ] **Step 5: Add per-part retry**

Retry creates a new `generation_jobs` row; do not overwrite prior history.

- [ ] **Step 6: Verify**

```bash
cd app
flutter test test/features/workspace/generation_batch_controller_test.dart
flutter test test/features/workspace/job_polling_service_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/lib/src/features/workspace app/test/features/workspace
git commit -m "feat: add batch generation workflow"
```

---

### Task 9: Results Gallery and Image-to-3D Workflow

**Files:**
- Create: `app/lib/src/features/results/results_gallery.dart`
- Create: `app/lib/src/features/results/asset_result_card.dart`
- Create: `app/lib/src/features/results/model_generation_controller.dart`
- Create: `app/test/features/results/results_gallery_test.dart`
- Create: `app/test/features/results/model_generation_controller_test.dart`
- Modify: `app/lib/src/features/workspace/workspace_page.dart`

**Interfaces:**
- Produces: gallery of persisted `AssetResult` records.
- Produces: `ModelGenerationController.generateFromImage(assetResultId)`.
- Consumes: `GenerationGateway.generateModel`.

- [ ] **Step 1: Write failing gallery tests**

Verify:

- only successful persisted results appear as usable assets,
- failed/persistence-failed jobs show status but no usable asset action,
- regenerations show history without deleting older results.

- [ ] **Step 2: Implement gallery**

Images are rendered from short-lived signed Supabase Storage URLs. Do not make generated buckets public.

- [ ] **Step 3: Write failing 3D-generation tests**

Test that:

- model generation is enabled only for image results,
- request uses selected `asset_result_id`,
- repeated taps while a model job is active do not create duplicate jobs.

- [ ] **Step 4: Implement 3D action**

Display model task progress in the same normalized job-state system. When complete, persist GLB result and preview image through Task 5 polling/persistence flow.

- [ ] **Step 5: Verify**

```bash
cd app
flutter test test/features/results
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/src/features/results app/test/features/results app/lib/src/features/workspace/workspace_page.dart
git commit -m "feat: add results and 3D generation"
```

---

### Task 10: Analytics Boundary, Remote Supabase Deployment, End-to-End Verification, and PR

**Files:**
- Create: `app/lib/src/core/analytics/analytics.dart`
- Create: `app/lib/src/core/analytics/noop_analytics.dart`
- Create: `app/lib/src/core/analytics/posthog_analytics.dart`
- Create: `app/test/core/analytics/analytics_privacy_test.dart`
- Modify: `app/pubspec.yaml`
- Modify: `README.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `Analytics.capture(String event, Map<String, Object?> properties)`.
- Produces: optional `PosthogAnalytics` only when dedicated Mohsen-Tripo configuration is present.
- Consumes: event names from the approved design spec.

- [ ] **Step 1: Add PostHog dependency and privacy test**

Run:

```bash
cd app
flutter pub add posthog_flutter:5.43.1
```

Write a test that rejects analytics properties whose keys match:

```dart
const forbiddenAnalyticsKeys = {
  'authorization',
  'api_key',
  'token',
  'image_bytes',
  'prompt',
};
```

- [ ] **Step 2: Implement analytics port**

Without `POSTHOG_API_KEY`, bind `NoopAnalytics`.

With a dedicated Mohsen-Tripo key, bind `PosthogAnalytics` and emit only the approved event taxonomy:

```text
project_created
reference_image_added
template_selected
generation_started
generation_completed
generation_failed
part_regenerated
model_generation_started
model_generation_completed
model_generation_failed
```

- [ ] **Step 3: Provision remote Supabase project only after cost confirmation**

At execution time:

1. list Supabase organizations,
2. ask which organization to use if more than one exists,
3. call the Supabase cost lookup,
4. present the exact recurring cost,
5. obtain the required cost confirmation,
6. create project `Mohsen-Tripo`.

Do not create a paid project before this confirmation.

- [ ] **Step 4: Apply and verify backend remotely**

After project creation:

- enable Anonymous Sign-Ins,
- apply migration,
- set only server-side `TRIPO_API_KEY` as an Edge Function secret,
- deploy all three Edge Functions,
- run Supabase security and performance advisors,
- fix every relevant RLS/security finding before proceeding.

- [ ] **Step 5: Configure Android build values**

Use:

```bash
flutter build apk --release   --dart-define=SUPABASE_URL=<project-url>   --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

The Tripo key must not appear in the command, Dart defines, Gradle files, repository, or APK strings.

- [ ] **Step 6: Run complete verification**

Run:

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release   --dart-define=SUPABASE_URL=https://example.supabase.co   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_test
cd ..
deno task test
supabase start
supabase db reset
supabase test db
supabase db lint
supabase stop
```

Then run a real-device Android smoke test against the configured remote project:

1. first launch creates anonymous session,
2. create project,
3. select reference image,
4. choose Character Parts template,
5. add `ضمادات الرأس`,
6. generate two parts,
7. verify independent job progress,
8. verify one persisted image result,
9. regenerate one part,
10. convert one image result to 3D,
11. close/reopen app and verify project history remains.

Real paid Tripo calls are allowed only in this manual smoke test.

- [ ] **Step 7: Update README**

Document:

- architecture,
- local prerequisites,
- safe configuration,
- test commands,
- how to supply Supabase public config,
- where the Tripo secret belongs,
- how to run the Android app,
- explicit warning never to put Tripo secret in Flutter.

- [ ] **Step 8: Commit final integration**

```bash
git add app .github README.md
git commit -m "feat: complete Mohsen-Tripo Android MVP"
```

- [ ] **Step 9: Open Pull Request and run GH Review Loop**

Create a PR from the implementation branch into `main`. Then run the configured GH Review Loop:

1. fetch actionable review threads,
2. fix all valid findings,
3. run the repository verification profile,
4. push fixes,
5. request re-review,
6. repeat until clean or the configured cap is reached.

Do not merge with unresolved actionable high-confidence defects.

---

## Implementation Order and External-Service Gates

- Tasks 1–9 can be developed and tested locally without creating a paid Supabase project and without a Tripo key.
- Task 10 is the first remote-resource gate.
- A Supabase project requires explicit cost confirmation at execution time.
- A Tripo API key is required only for the manual integration smoke test and must be stored as a backend secret.
- A dedicated PostHog Mohsen-Tripo project is optional for MVP correctness; analytics must remain a no-op until one exists.

## Self-Review Checklist

- Spec scope covered: project creation, reference image, templates, custom parts, image-to-image, independent jobs, retries, persistence, history, and image-to-3D are all mapped to Tasks 2–9.
- Security covered: anonymous auth, RLS, private buckets, backend-only Tripo key, redacted logs, and analytics privacy are mapped to Tasks 3–6 and 10.
- Testing covered: Dart unit tests, widget tests, Deno Edge tests, provider-contract tests, pgTAP RLS tests, CI, and real-device smoke testing are explicitly assigned.
- Provider drift covered: normalized Tripo client rejects malformed/unknown responses.
- No paid provider call is required by CI.
- No on-device AI, Windows, iOS, marketplace, or social scope leaked into MVP.
- Execution method preserved from the user request: native implementation by this assistant, not fictional employees.
