# Tripo Android XAPK — Clean-Room Reference Pack for Mohsen-Tripo

This directory contains metadata and inventories extracted from the user-provided Tripo AI XAPK for architecture/reference only.

## Included

- `xapk_manifest.json` — outer XAPK metadata: package, version, SDK split metadata.
- `arm64_split_file_list.txt` — ARM64 split inventory.
- `native_libraries.txt` — native `.so` inventory.
- `architecture_findings.md` — high-value technical findings relevant to our own implementation.
- `REUSE_DECISION.txt` — explicit clean-room reuse boundary.
- `REFERENCE_SHA256.txt` — hashes of the original extracted reference files.
- `adoption.md` — how Mohsen-Tripo applies the findings.

## Clean-room boundary

Do not copy Tripo's proprietary Dart/AOT code, DEX implementation, images, fonts, 3D scene assets, textures, animations, branding, or private/internal API behavior into Mohsen-Tripo.

Use this directory only to understand architecture/platform requirements and implement original code/UI/assets using documented public APIs and public libraries.
