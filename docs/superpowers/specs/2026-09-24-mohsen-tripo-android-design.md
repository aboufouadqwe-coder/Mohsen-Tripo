# Mohsen-Tripo Android — Product & Architecture Design

**Date:** 2026-09-24  
**Status:** Design approved for specification; implementation not yet started  
**Repository:** `aboufouadqwe-coder/Mohsen-Tripo`  
**Target:** Android first

## 1. Product Goal

Mohsen-Tripo is a personal Android application for AI-assisted game-asset creation.

The app will use Tripo's official v3 API as the generation engine instead of reimplementing image generation, 3D generation, rigging, or model conversion.

The primary differentiator is a custom workflow that turns one reference image into a structured set of newly generated asset references, such as:

- head
- right hand
- left hand
- right foot
- left foot
- clothing
- accessories
- user-defined parts such as bandages, keys, tools, masks, or props

These outputs are newly generated images derived from the reference image. They are not pixel crops or PNG cutouts.

## 2. MVP Scope

The first Android release will provide:

1. Create a project.
2. Import a reference image.
3. Select a reusable asset template.
4. Add, rename, reorder, enable, or disable requested parts.
5. Generate each selected part through Tripo image-to-image.
6. Generate all selected parts as a batch from one project screen.
7. Show task state and progress for each generation.
8. Retry or regenerate one failed or unsatisfactory part.
9. Persist generated results to project storage.
10. Convert a selected generated image to a 3D model through Tripo image-to-model.
11. Browse project history and previous generations.

Out of scope for MVP:

- local diffusion image generation
- automatic body-part detection
- full offline mode
- iOS
- Windows
- social/community features
- marketplace
- team collaboration
- direct modification of the proprietary Tripo mobile APK

## 3. Core User Flow

```text
Create Project
    ↓
Import Reference Image
    ↓
Choose Template
    ↓
Edit Requested Parts
    ↓
Generate All
    ↓
Track Tripo Tasks
    ↓
Review Results
    ├── Regenerate Part
    └── Convert Selected Result to 3D
```

Example template:

```text
Character Parts

[x] Head
[x] Right Hand
[x] Left Hand
[x] Right Foot
[x] Left Foot
[x] Clothing
[x] Accessories
[+] Custom Part: Head Bandages
```

## 4. Architecture

### 4.1 Android Client

The client will be built with Flutter and Dart.

Responsibilities:

- project UI
- reference image selection
- template editing
- generation request creation
- job status display
- result gallery
- local lightweight cache
- Android lifecycle handling
- invocation of Supabase Auth, Database, Storage, and Edge Functions
- PostHog event reporting after a dedicated Mohsen-Tripo project is configured

The Android client must never contain the Tripo API key or any other privileged backend secret.

### 4.2 Supabase Backend

Supabase will provide:

- Auth
- Postgres database
- Storage
- Edge Functions
- secret storage for the Tripo API key

The public Android application may contain only a Supabase publishable key. All exposed tables must use Row Level Security.

The Tripo API key must be stored only as a server-side secret available to Edge Functions.

### 4.3 Tripo Integration

Mohsen-Tripo will use the official Tripo v3 API.

Initial operations:

- `textToImage`
- `imageToImage`
- `imageToModel`
- `getTask` / task polling
- file upload when needed

The global API base is:

```text
https://openapi.tripo3d.ai/v3
```

The application will call Tripo only through our backend boundary.

### 4.4 Future On-Device AI Boundary

The architecture will reserve a separate interface for optional Android-local vision inference.

Future candidates include LiteRT / MediaPipe or ONNX Runtime Mobile.

This module may later:

- detect visible semantic regions
- suggest likely asset parts
- derive visual descriptions
- help construct prompts

It will not be required for MVP correctness.

## 5. Asset Generation Model

Each project contains:

- one canonical reference image
- one selected template
- zero or more custom part requests
- generation settings
- result history

Each part request contains:

- stable part id
- display label
- generation prompt fragment
- enabled flag
- ordering
- latest task state
- latest result
- regeneration history

A prompt builder combines:

1. project-level identity instructions
2. reference-image consistency instructions
3. part-specific instructions
4. output composition requirements

Example generated instruction:

```text
Generate a clean isolated reference image of the same character's injured left arm.
Preserve the character identity, proportions, skin condition, bandage design, material,
color palette, and horror-art direction from the reference image.
Show the requested part clearly and completely.
```

## 6. Consistency Strategy

The first version will maximize consistency by:

- reusing the same canonical source image
- storing a project-level identity prompt
- keeping stable generation settings per project
- using reusable templates
- preserving successful outputs and their task metadata
- allowing regeneration from a selected prior result where supported

The app will not promise pixel-identical consistency across separate generative calls.

## 7. Data Model

Initial logical entities:

### Project

- id
- owner_id
- name
- reference_image_path
- template_id
- identity_prompt
- created_at
- updated_at

### AssetTemplate

- id
- owner_id nullable for built-in templates
- name
- description
- is_builtin
- created_at
- updated_at

### TemplatePart

- id
- template_id
- key
- label
- prompt_fragment
- sort_order
- enabled_by_default

### GenerationJob

- id
- project_id
- part_key
- provider
- operation
- provider_task_id
- status
- progress
- request_payload_redacted
- error_code
- error_message
- created_at
- updated_at
- completed_at

### AssetResult

- id
- project_id
- generation_job_id
- part_key
- storage_path
- mime_type
- width
- height
- created_at

All user-owned rows must be protected with RLS.

## 8. Storage Model

Suggested buckets:

```text
reference-images/
generated-images/
generated-models/
```

Object paths must be user-scoped:

```text
<user_id>/<project_id>/...
```

Tripo output URLs must not be treated as permanent storage. Successful outputs should be copied to Supabase Storage when required for project persistence.

## 9. Backend Functions

Initial Edge Function boundary:

### generate-image-part

Input:

- project_id
- part_key
- optional custom instructions

Responsibilities:

- authenticate caller
- verify project ownership
- load project reference
- build the generation request
- submit Tripo image-to-image
- create GenerationJob
- return job id

### refresh-generation-job

Responsibilities:

- authenticate caller
- verify ownership
- query Tripo task status
- update GenerationJob
- persist completed output into Supabase Storage
- create AssetResult

### generate-model

Responsibilities:

- authenticate caller
- verify source AssetResult ownership
- submit Tripo image-to-model
- create a GenerationJob

## 10. Security Rules

Non-negotiable:

1. Never commit Tripo API keys.
2. Never bundle Tripo API keys into the Android package.
3. Never expose Supabase secret/service-role credentials to Flutter.
4. Use a Supabase publishable key in the mobile client.
5. Enable RLS on every table in exposed schemas.
6. Restrict rows by authenticated owner.
7. Validate project and result ownership in backend functions.
8. Do not log secrets or full authorization headers.
9. Do not store raw credentials in PostHog.
10. Do not use proprietary Tripo mobile-app internal endpoints to bypass authorization, billing, or product restrictions.

## 11. Authentication

MVP will use a device-friendly Supabase Auth flow with no custom account system.

The implementation plan must select the simplest supported authenticated-user flow for Android while preserving per-user RLS.

A visible login screen is not required for the first internal build unless the chosen Supabase Auth mode requires one.

## 12. Observability

PostHog will be integrated only after a dedicated Mohsen-Tripo project is available.

Initial event taxonomy:

- project_created
- reference_image_added
- template_selected
- generation_started
- generation_completed
- generation_failed
- part_regenerated
- model_generation_started
- model_generation_completed
- model_generation_failed

No image bytes, prompts containing sensitive user data, authorization tokens, or provider secrets will be sent as analytics properties.

## 13. Error Handling

The client must distinguish:

- local validation error
- upload error
- backend authorization error
- backend validation error
- Tripo provider rejection
- Tripo provider timeout
- Tripo provider task failure
- persistence failure

A failed part generation must not fail or discard successful sibling generations in the same batch.

Retry will be per part.

## 14. Testing Strategy

The implementation will follow TDD where practical.

Required test layers:

- Dart unit tests for prompt building and domain logic
- widget tests for template editing and job-state rendering
- Edge Function unit tests for validation and provider mapping
- backend integration tests for ownership and RLS
- provider-contract tests using mocked Tripo responses
- one manual Android smoke test for every release candidate

No CI test may require a real paid Tripo request by default.

## 15. Repository Direction

Initial expected structure:

```text
/
├── app/
│   └── Flutter Android application
├── supabase/
│   ├── functions/
│   ├── migrations/
│   └── config.toml
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── .github/
│   └── workflows/
├── README.md
└── LICENSE
```

The exact file tree will be finalized in the implementation plan after this specification is approved.

## 16. Delivery Workflow

1. Specification
2. Implementation plan
3. Isolated development branch
4. TDD implementation
5. Verification
6. Pull request
7. GH Review Loop
8. Fix and re-verify
9. Merge after review

The assistant performs the implementation directly; no work is delegated to fictional employees.

## 17. Success Criteria for MVP

The MVP is successful when an Android user can:

1. create a project
2. select one reference image
3. choose or edit a character-parts template
4. generate multiple requested parts as new images
5. see independent progress and failures for each part
6. persist successful results
7. regenerate one part without rerunning all parts
8. convert one successful image result into a 3D generation task
9. reopen the project and see its stored results
10. use the application without any Tripo privileged secret being present in the Android package
