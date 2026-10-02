# Mohsen-Tripo — Local Tripo Credential + Optional Direct Image-to-3D Design

**Date:** 2026-09-25  
**Branch:** `feature/android-mvp`  
**Status:** Design approved in chat; implementation pending written-spec review.

## 1. Goal

Make Mohsen-Tripo usable without manually opening Supabase whenever the user gets a new Tripo API key.

The intended user flow is:

1. Mohsen-Tripo opens the official Tripo Console in Chrome.
2. The user signs in and completes any email verification manually.
3. The user creates a Tripo API key in the official console and taps **Copy**.
4. The user returns to Mohsen-Tripo.
5. Mohsen-Tripo detects a likely Tripo API key in the clipboard while the app is in the foreground and asks for confirmation before importing it.
6. The app validates the key by querying the Tripo API balance endpoint.
7. If valid, the app stores the key in Android secure storage, gives it a local display name, and makes it the active credential.
8. All later Tripo generation and polling requests use that active/local credential instead of the global Supabase `TRIPO_API_KEY` secret.

The app does **not** create Tripo accounts, automate email verification, or automate repeated trial acquisition. Account creation and activation remain manual in Chrome.

## 2. Current provider trial context

Tripo currently documents a **“free wallet”** flow in an official tutorial as a **14-day trial with 600 credits and no credit card required**. The application must not hard-code 600 credits or assume every account is entitled to the same offer. The real source of truth remains `GET /v3/account/balance`.

The UI may explain that the connected account can use any trial or paid credits Tripo actually grants, but it must display the live provider balance rather than manufacturing a local credit balance.

## 3. Credential architecture

### 3.1 Local-only secret storage

Add a local credential store backed by Android Keystore through a maintained secure-storage package.

Each saved credential contains:

- local credential id
- user-editable display name
- API key secret
- non-secret fingerprint derived from the API key
- created-at timestamp
- last successful balance check
- active/inactive state

The raw API key:

- is never written to Postgres
- is never stored in Supabase project secrets
- is never included in analytics
- is never written to logs
- is never included in generation job request payload snapshots
- is never committed to GitHub

### 3.2 Clipboard import

Mohsen-Tripo checks the clipboard only when the app returns to foreground from the browser or when the user explicitly taps **Import copied key**.

Clipboard behavior:

- do not continuously poll in the background
- ignore empty/unrelated clipboard values
- do not save anything until the user confirms
- validate the candidate key against Tripo before marking it active
- clear the app’s in-memory copy after persistence/validation
- show only a masked form such as `tripo_••••••A91F`

Chrome remains the browser. The app does not scrape Chrome pages or read browser DOM/content.

### 3.3 Passing the key through Supabase without storing it

Supabase stays as the backend for Auth, project data, Storage, job records, and Edge Functions.

For Tripo-backed Edge Function calls, the Flutter client sends the selected Tripo key in a dedicated per-request custom header. Current Supabase Flutter function invocation supports custom request headers.

The Edge Function:

1. authenticates the normal Supabase user JWT as it does today
2. reads the Tripo credential header
3. creates a request-scoped `TripoClient(apiKey: ...)`
4. performs the provider call
5. discards the key after the request

The old `TRIPO_API_KEY` environment-secret path becomes a compatibility fallback during migration only and can be removed once all app flows use local credentials.

## 4. Credential identity for long-running jobs

Changing the active key while a Tripo task is running must not break polling.

Every new Tripo task is associated with the **non-secret credential fingerprint**, never the raw key.

The fingerprint is persisted with the job as redacted metadata. The app keeps the fingerprint-to-secure-credential mapping locally.

When refreshing a job:

1. read the job credential fingerprint
2. resolve the matching local secure credential
3. send that key to `refresh-generation-job`
4. poll the original provider task with the same Tripo account that created it

If the matching local credential was deleted or the app was reinstalled, the job remains visible but cannot be resumed until the user re-imports the corresponding key.

## 5. Credential UX

Add a **Tripo Account** card near the existing credit card.

Primary states:

- **No account connected** — button: `ربط حساب Tripo`
- **Chrome opened** — helper text explaining to sign in manually, create a key, and copy it
- **Copied key detected** — confirmation sheet
- **Checking key…**
- **Connected** — display name + live available/frozen credits
- **Invalid/expired key** — keep the old working active credential unchanged
- **Multiple saved credentials** — allow manual switching and deletion

Actions:

- `فتح Tripo في Chrome`
- `استيراد المفتاح المنسوخ`
- `تحديث الرصيد`
- `تبديل الحساب`
- `حذف الحساب من هذا الجهاز`

No raw secret is shown after initial import.

## 6. Optional direct image-to-3D

The user can already generate 3D from a generated image result. Add a second optional path:

**Choose an existing image from the phone → validate it → generate 3D directly.**

This is optional; normal image-generation → 3D remains unchanged.

### 6.1 Accepted source image

For direct image-to-3D:

- PNG or JPEG in the first implementation because the current Storage/File Upload path already supports these formats
- maximum 20 MB
- recommended at least 256 × 256 px
- local UI guidance: subject clearly visible, clean/minimal background, minimal occlusion

These constraints match the current Tripo image-to-model guidance.

### 6.2 Storage and provider handoff

The selected image is uploaded privately under an owned project path such as:

`<user>/<project>/model-inputs/<uuid>.png`

The Edge Function validates ownership, signs/downloads the private file server-side, uploads it to Tripo `POST /v3/files`, receives a `file_token`, then submits that token to `POST /v3/generation/image-to-model`.

No public URL is required.

### 6.3 API contract

Extend model generation so it accepts exactly one source:

- existing `asset_result_id`, or
- new owned `reference_storage_path` / direct model-input path

If both or neither are supplied, reject the request.

Generated-image results should continue to reuse the original Tripo image `task_id` when available because that avoids another image upload.

Direct local images use a provider `file_token`.

### 6.4 UI placement

Add a small card above the current 3D settings/results section:

**تحويل صورة مباشرة إلى 3D**

- `اختيار صورة`
- thumbnail/filename
- image suitability notes
- current 3D quality/topology controls remain shared
- `توليد 3D`

This route is optional and independent of Smart Part Planner.

## 7. Security and privacy requirements

- The Supabase publishable key remains client-safe and unchanged.
- Supabase secret/service-role credentials remain server-only.
- Tripo API keys are local secure secrets.
- Never log the custom Tripo credential header.
- Provider errors returned to the app must remain redacted as today.
- Saved credential labels/fingerprints may be persisted locally; raw keys may not.
- Clipboard import requires a foreground user action/return-to-app event and explicit confirmation.
- Analytics may record events such as `tripo_credential_connected` but never key material, clipboard content, email, or account identifier.

## 8. Failure handling

### Invalid key
Balance validation fails; do not replace the current active key.

### Insufficient credits
Surface Tripo’s insufficient-credit state without altering the stored credential.

### Account switched during active task
Existing jobs continue using their original credential fingerprint.

### Missing credential for resumed job
Show `مفتاح الحساب الذي بدأ هذه المهمة غير موجود على هذا الجهاز` and do not attempt polling with another key.

### Clipboard contains unrelated text
Ignore it silently.

### Direct image unsuitable
Reject unsupported format/oversize locally. For low resolution or poor subject isolation, warn but let the user decide rather than pretending the app can guarantee semantic suitability.

## 9. Database impact

No table stores raw Tripo keys.

The minimal server-side change is a non-secret credential fingerprint associated with generation jobs. Prefer adding a dedicated nullable column such as:

`provider_credential_fingerprint text null`

rather than hiding identity inside JSON request metadata, because it is operational state needed to resume jobs.

The migration must:

- preserve all existing jobs
- keep the new column nullable for legacy jobs
- not expose any secret
- keep existing RLS/ownership behavior intact

## 10. Edge Function impact

Functions that call Tripo need request-scoped credentials:

- `generate-source-image`
- `generate-image-part`
- `generate-model`
- `refresh-generation-job`
- `tripo-balance`

`TripoClient` already accepts `apiKey`; reuse that injection point instead of creating another provider client.

## 11. Flutter impact

Expected new/changed responsibilities:

- secure Tripo credential repository
- credential manager/controller
- Chrome launcher
- lifecycle/clipboard import coordinator
- request-scoped Tripo-key headers in `SupabaseFunctionInvoker`
- job fingerprint routing
- Tripo account UI
- direct model-input image picker/uploader
- direct image-to-3D controller path
- existing balance and generation UI updated to require a connected credential

## 12. Testing strategy

Implementation will follow TDD.

Required tests include:

### Flutter
- secure store saves/loads masked credential metadata without exposing raw keys
- importing a valid copied key validates before activation
- invalid candidate never replaces active credential
- function invocations attach the selected key header
- job refresh resolves the credential by fingerprint
- switching active key does not change an already-running job’s credential
- direct model image picker rejects unsupported/oversized inputs
- direct model generation submits the owned storage path
- existing generated-image-to-3D flow remains green

### Edge Functions
- missing Tripo credential header is rejected after compatibility fallback is disabled
- supplied request credential reaches `TripoClient`
- credential is never written into redacted job payload
- credential fingerprint is stored
- refresh uses the caller-supplied key and validates job ownership
- direct model path rejects paths outside the authenticated user/project
- direct model image path uploads to Tripo and uses returned `file_token`
- existing task-id reuse remains unchanged

### Integration/CI
- Deno contract suite
- Flutter analyze
- Flutter test
- release APK build

## 13. Non-goals

This change will not:

- create Tripo accounts automatically
- create disposable email accounts
- read verification emails automatically
- scrape Tripo/Chrome pages
- automate repeated free-trial acquisition
- fabricate local credits
- bypass Tripo billing or account restrictions

The app simply makes a manually obtained, legitimate Tripo API key easy to connect and use.

## 14. Acceptance criteria

The feature is complete when:

1. User can tap **Open Tripo**, finish sign-in manually in Chrome, copy a new API key, return, confirm import, and immediately see the real Tripo balance.
2. No Supabase Dashboard visit is required to change the active Tripo key.
3. The raw Tripo key is stored only in Android secure storage and transmitted only when required for a provider request.
4. A running job remains tied to the credential that created it even after the active account changes.
5. User can optionally choose a PNG/JPEG from the phone and generate a 3D model directly with the existing quality/topology settings.
6. Existing Smart Part Planner, generated-image-to-3D, sequential generation, timers, balance display, viewer, and download flows continue to work.
7. Full tests/analyze/release build pass.
