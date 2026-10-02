# Mohsen-Tripo adoption of the Tripo clean-room reference

## Status

This reference is adopted as an architecture input only. No Tripo proprietary source, binaries, fonts, imagery, scene assets, or private API behavior are imported into production code.

## Compatibility confirmed

- **Flutter Android shell:** already used by Mohsen-Tripo.
- **Minimum Android SDK 24:** already enforced in `app/android/app/build.gradle.kts`.
- **Cloud generation:** already implemented through authenticated Supabase Edge Functions.
- **Async submit/poll/persist model:** already implemented in the generation pipeline.
- **Private storage separation:** already implemented with `reference-images`, `generated-images`, and `generated-models`.
- **GLB/glTF model result direction:** compatible with the current image-to-3D workflow.
- **ARM64:** compatible with Android release distribution; no Tripo native binary is reused.

## Decisions for the product

1. Do **not** copy `libfilament_renderer.so` from Tripo.
2. Keep the renderer behind a provider-agnostic/model-view boundary.
3. Treat the persisted GLB in `generated-models` as the authoritative 3D artifact.
4. Add a maintained public Flutter/native GLB viewer only after verifying package maintenance, Android compatibility, licensing, and performance.
5. Do not pin Mohsen-Tripo's target SDK merely because the reference app targets 36; use the Flutter/Android toolchain requirement and store-release requirements.
6. Do not reproduce Tripo private/internal endpoints. Only documented public provider APIs remain allowed.

## Immediate use in current work

For MT-09 (Results Gallery + Image-to-3D):

- model results are represented as private persisted GLB artifacts,
- gallery logic remains independent of renderer implementation,
- image-to-3D submission/polling remains backend-driven,
- any model preview component must consume our stored model result, not a private Tripo mobile endpoint.

This keeps the current MVP clean-room, upgradeable, and legally/architecturally independent.
