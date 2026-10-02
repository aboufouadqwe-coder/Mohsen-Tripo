# Architecture findings useful for Mohsen-Tripo

## Platform / runtime

- App type: Flutter/Dart Android application.
- Package seen in XAPK metadata: `ai.holymolly.tripo3daimodel`.
- XAPK version: `1.12.2` (code `161`).
- Minimum Android SDK: 24.
- Target Android SDK: 36.
- ARM64 split is present.

## Native runtime pieces seen

The ARM64 split contains:

- `libapp.so` — Dart AOT application image.
- `libflutter.so` — Flutter engine.
- `libfilament_renderer.so` — native Filament 3D rendering integration.
- `libsqlite3.so` — SQLite runtime.
- `libdartjni.so` and shared support libraries.

### What this tells us

For Mohsen-Tripo, a Flutter Android shell is a valid architecture. A native/native-backed 3D viewer can be added later without changing the rest of the app architecture. We do not copy Tripo's renderer implementation; we use our own GLB/glTF integration through maintained public components.

## High-value design patterns we can reproduce cleanly

1. Flutter Android app shell.
2. Server-side/cloud generation rather than shipping model weights inside the APK.
3. Async task model: submit -> poll -> persist result -> render.
4. Private generated assets stored separately from source/reference assets.
5. A 3D renderer capable of GLB/glTF plus environment lighting.
6. Split architecture where native rendering is optional and generation logic remains provider/backend driven.
7. Android ARM64 support and minSdk 24 baseline.

## What NOT to reuse

- Tripo branding, logos, UI artwork, scene-pack textures/models.
- `libapp.so` / Dart AOT code.
- DEX implementation code.
- Private/internal mobile API endpoints or authentication behavior.
- Subscription/paywall implementation details.

## Direct relevance to current Mohsen-Tripo implementation

Already aligned:

- Flutter Android frontend.
- minSdk 24.
- Server-side Supabase Edge Functions.
- Async generation jobs + polling.
- Private Storage buckets.
- Image generation and image-to-model provider boundary.

Useful for current/future tasks:

- GLB result handling in the results gallery.
- provider-agnostic 3D preview boundary.
- optional environment lighting / IBL support.
- export/download UX.
- native-renderer performance work on Android ARM64.
