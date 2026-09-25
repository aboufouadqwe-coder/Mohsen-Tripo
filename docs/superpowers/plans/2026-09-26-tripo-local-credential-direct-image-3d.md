# Local Tripo Credentials + Direct Image-to-3D Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Mohsen-Tripo import a manually copied Tripo API key from Chrome into secure local Android storage, use that key for all provider requests, keep running jobs tied to the credential that created them, and optionally generate 3D directly from a user-selected image.

**Architecture:** Keep Supabase for Auth, Storage, job persistence, and Edge Functions, but move the Tripo secret out of Supabase Secrets into Android secure storage. Flutter sends the active/request-matched key per Edge Function invocation; Edge Functions use it only in memory and persist only a SHA-256 fingerprint with the job. Direct image-to-3D uploads an owned private image to Supabase Storage, then the model Edge Function uploads it to Tripo `/v3/files` and submits the resulting file token.

**Tech Stack:** Flutter 3.47, Dart, `flutter_secure_storage`, `url_launcher`, `crypto`, Supabase Flutter 2.17.2, Supabase Edge Functions/Deno, Tripo V3.

**Spec:** `docs/superpowers/specs/2026-09-25-tripo-local-credential-direct-image-3d-design.md`

## Global Constraints

- Raw Tripo API keys must never be stored in Postgres, Supabase Secrets, analytics, logs, or GitHub.
- Account creation/login/email verification remain manual in Chrome.
- Clipboard import requires foreground user action/return and explicit confirmation.
- Live Tripo balance is authoritative; do not manufacture local credits or hard-code trial credits.
- Existing Smart Part Planner, sequential generation, timers, balance, viewer, downloads, and generated-image-to-3D must remain working.
- Direct local image input is PNG/JPEG, max 20 MB.
- Existing and new server-side ownership checks remain fail-closed.

## Review Focus

- App restarts with a saved credential: secure key reloads and balance refresh works without exposing the raw key.
- Active key changes while a job is running: refresh still uses the fingerprint-matched original key.
- Legacy jobs without a fingerprint: remain visible and either use compatibility fallback or surface a precise missing-credential state.
- Clipboard contains unrelated/invalid text: nothing is activated and the current working key is preserved.
- Direct image path traversal/cross-project input: Edge Function rejects it before contacting Tripo.

---

### Task 1: Secure local credential model and request-scoped function headers

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/src/domain/tripo/tripo_credential.dart`
- Create: `app/lib/src/data/local/tripo_credential_repository.dart`
- Modify: `app/lib/src/data/supabase/generation_gateway.dart`
- Modify: `app/lib/src/data/supabase/supabase_clients.dart`
- Test: `app/test/data/tripo_credential_repository_test.dart`
- Test: `app/test/data/generation_gateway_test.dart`

**Interfaces:**
- Produces: `TripoCredential`, `TripoCredentialRepository`, `ActiveTripoCredentialProvider`, and request metadata/header plumbing used by later tasks.
- Consumes: existing `FunctionInvoker`, `GenerationGateway`, Supabase function invocation.

- [ ] **Step 1: Write failing tests** for secure credential save/load, masking/fingerprint, invalid activation preserving the current key, and function invocation receiving a request credential.
- [ ] **Step 2: Run the focused Flutter tests and verify RED.**
- [ ] **Step 3: Add secure-storage/crypto/url-launcher dependencies and implement the credential repository + request-scoped invocation contract.**
- [ ] **Step 4: Run focused tests and verify GREEN.**
- [ ] **Step 5: Commit.**

### Task 2: Tripo account UX, Chrome launch, clipboard import, and live balance validation

**Files:**
- Create: `app/lib/src/features/tripo/tripo_account_controller.dart`
- Create: `app/lib/src/features/tripo/tripo_account_card.dart`
- Modify: `app/lib/src/features/workspace/workspace_page.dart`
- Modify: `app/lib/src/app.dart` as needed for dependency wiring
- Test: `app/test/features/tripo/tripo_account_controller_test.dart`
- Test: `app/test/features/workspace/workspace_page_test.dart`

**Interfaces:**
- Consumes: Task 1 credential repository and credential-aware balance gateway.
- Produces: connected-account UI state, Chrome launch action, clipboard candidate import/confirmation, active credential switching/removal.

- [ ] **Step 1: Write failing controller/widget tests** for Chrome flow state, candidate import, valid-key activation, invalid-key preservation, and masked display.
- [ ] **Step 2: Run focused tests and verify RED.**
- [ ] **Step 3: Implement controller/card and wire it into Workspace.**
- [ ] **Step 4: Run focused tests and verify GREEN.**
- [ ] **Step 5: Commit.**

### Task 3: Server-side per-request Tripo credentials and job fingerprint routing

**Files:**
- Modify: `supabase/functions/_shared/http.ts`
- Modify: `supabase/functions/_shared/tripo_client.ts`
- Modify: `supabase/functions/generate-source-image/index.ts`
- Modify: `supabase/functions/generate-image-part/index.ts`
- Modify: `supabase/functions/generate-model/index.ts`
- Modify: `supabase/functions/refresh-generation-job/index.ts`
- Modify: `supabase/functions/tripo-balance/index.ts`
- Add database column: `generation_jobs.provider_credential_fingerprint text null`
- Test: all affected files in `supabase/functions/tests/`

**Interfaces:**
- Consumes: custom request header carrying the Tripo key and `x-tripo-credential-fingerprint`.
- Produces: jobs persisted with non-secret fingerprint; every Tripo request uses a request-scoped `TripoClient(apiKey: ...)`.

- [ ] **Step 1: Write failing Deno tests** proving request key use, no key leakage, fingerprint persistence, refresh matching, and missing/malformed credential behavior.
- [ ] **Step 2: Run Deno suite and verify RED.**
- [ ] **Step 3: Add nullable fingerprint column with RLS unchanged and implement request-scoped Tripo clients.**
- [ ] **Step 4: Run Deno suite and database/security verification; verify GREEN.**
- [ ] **Step 5: Deploy affected Edge Functions and commit code.**

### Task 4: Optional direct local image-to-3D

**Files:**
- Modify: `app/lib/src/data/supabase/reference_image_repository.dart`
- Modify: `app/lib/src/data/supabase/generation_gateway.dart`
- Create: `app/lib/src/features/results/direct_model_image_picker.dart`
- Modify: `app/lib/src/features/results/model_generation_controller.dart`
- Modify: `app/lib/src/features/workspace/workspace_page.dart`
- Modify: `supabase/functions/generate-model/index.ts`
- Test: `app/test/data/reference_image_repository_test.dart`
- Test: `app/test/features/results/model_generation_controller_test.dart`
- Test: `supabase/functions/tests/generate_model_test.ts`

**Interfaces:**
- Consumes: active local Tripo credential and existing model generation settings.
- Produces: `GenerationGateway.generateModelFromReferencePath(projectId, storagePath, settings: ...)` and owned `model-inputs/` storage path.

- [ ] **Step 1: Write failing Flutter/Deno tests** for PNG/JPEG max-20MB validation, owned model-input path, exactly-one-source validation, Tripo file upload, and file-token model submission.
- [ ] **Step 2: Run focused tests and verify RED.**
- [ ] **Step 3: Implement private model-input upload, picker/card, gateway method, and Edge Function source handling.**
- [ ] **Step 4: Run focused suites and verify GREEN.**
- [ ] **Step 5: Commit.**

### Task 5: Full verification, deploy, and Android release

**Files:**
- Modify: `.github/workflows/build-exact-prompt-once.yml` release notes/name only if needed.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: deployed Edge Functions, verified database schema, successful release APK, GitHub Release page.

- [ ] **Step 1: Run full Deno contract suite; require 0 failures.**
- [ ] **Step 2: Run `flutter analyze`; require no issues.**
- [ ] **Step 3: Run full `flutter test`; require all tests passing.**
- [ ] **Step 4: Build release APK through GitHub Actions.**
- [ ] **Step 5: Verify published release asset and report tag, size, SHA-256, and release page.**
