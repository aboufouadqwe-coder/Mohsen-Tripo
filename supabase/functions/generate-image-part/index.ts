import {
  executeHttp,
  HttpError,
  jsonResponse,
  optionalString,
  readJsonObject,
  requireBearerToken,
  requiredString,
} from "../_shared/http.ts";
import { buildAssetPrompt } from "../_shared/prompt_builder.ts";
import {
  adminInsertOne,
  adminSelectOne,
  authenticateSupabaseToken,
  createSignedObjectUrl,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";
import { resolveTripoCredential } from "../_shared/tripo_credential.ts";

type OwnedProject = {
  id: string;
  referenceImagePath: string | null;
  templateId: string | null;
  identityPrompt: string;
};

type TemplatePart = {
  key: string;
  label: string;
  promptFragment: string;
};

type GenerateImagePartDeps = {
  authenticate: (token: string) => Promise<string>;
  findOwnedProject: (userId: string, projectId: string) => Promise<OwnedProject | null>;
  findTemplatePart: (
    templateId: string,
    partKey: string,
    userId?: string,
  ) => Promise<TemplatePart | null>;
  signReferenceUrl: (path: string) => Promise<string>;
  uploadReferenceToProvider: (
    apiKey: string,
    signedUrl: string,
  ) => Promise<string>;
  createImageToImage: (
    apiKey: string,
    input: { input: string; prompt: string },
  ) => Promise<string>;
  insertJob: (input: Record<string, unknown>) => Promise<string>;
};


const metaHumanSmartPartKeys = new Set([
  "full_body_apose",
  "head",
  "face_only",
  "hair_headwear",
  "torso",
  "right_arm",
  "left_arm",
  "right_hand",
  "left_hand",
  "right_leg",
  "left_leg",
  "feet_shoes",
  "upper_clothing",
  "lower_clothing",
  "clothing_outfit",
]);

function clippedInstruction(value: string, maxCharacters = 900): string {
  return Array.from(value).slice(0, maxCharacters).join("");
}

function buildMetaHumanSmartPartPrompt(
  partKey: string,
  partLabel: string,
  sourcePrompt: string,
): string {
  const key = partKey.trim().toLowerCase();
  if (!metaHumanSmartPartKeys.has(key)) return sourcePrompt;

  let isolationRule: string;

  if (key === "head" || key === "face_only") {
    isolationRule =
      "ANATOMY ONLY: output the clean character head/face as skin anatomy. Remove all hair, eyelashes, headwear, jewelry, clothing, collars, bandages/wraps, and detachable accessories. Keep facial identity, skin tone, proportions, scars/wounds that belong to skin, neutral expression, eyes open and mouth closed. For head output, keep it bald with ears and a short upper-neck connection.";
  } else if (key === "hair_headwear") {
    isolationRule =
      "SEPARATE WEARABLE ASSET ONLY: output only the hair and/or headwear visible in the reference. Do not render face, scalp skin, neck, torso, or clothing. Treat the body/head only as invisible fit context. Preserve silhouette, material, color, damage and placement.";
  } else if (
    key === "upper_clothing" ||
    key === "lower_clothing" ||
    key === "clothing_outfit"
  ) {
    isolationRule =
      "CLOTHING ASSET ONLY: output only the requested garment(s) as separate empty wearable geometry. Do not render skin, body anatomy, head, hands, feet, hair or unrelated accessories. Preserve the exact garment silhouette, seams, folds, tears, stains, material, color and fit from the reference.";
  } else if (key === "feet_shoes") {
    isolationRule =
      "FOOTWEAR ASSET ONLY: output only the shoes/footwear as separate wearable assets. Do not render feet, leg skin, trousers or other body geometry. Preserve exact shape, sole, laces, wear, stains, damage, material and scale.";
  } else if (key === "right_arm" || key === "left_arm") {
    isolationRule =
      "BARE ANATOMY ONLY: output the complete requested arm from shoulder attachment through fingertips with skin visible. Remove sleeves, gloves, bandages/wraps, jewelry and every clothing/accessory layer. Preserve limb proportions, skin tone and skin-only scars/wounds. Keep the arm isolated from the torso and keep all fingers clearly separated.";
  } else if (key === "right_hand" || key === "left_hand") {
    isolationRule =
      "BARE ANATOMY ONLY: output only the requested bare hand with a short wrist connection. Remove gloves, bandages/wraps, jewelry and clothing. Preserve hand proportions, skin tone and skin-only scars/wounds. Use a relaxed open hand with every finger clearly separated.";
  } else if (key === "right_leg" || key === "left_leg") {
    isolationRule =
      "BARE ANATOMY ONLY: output the complete requested leg as skin anatomy. Remove trousers, socks, shoes, bandages/wraps and every clothing/accessory layer. Preserve proportions, skin tone and skin-only scars/wounds. Keep the leg isolated with a clean readable silhouette.";
  } else {
    isolationRule =
      "BASE BODY ONLY: create a clean unclothed MetaHuman-conform anatomy reference. Remove all clothing, underwear, shoes, gloves, bandages/wraps, jewelry, hair, headwear and detachable accessories. Preserve the character's overall body proportions, silhouette and skin tone. Use a smooth neutral mannequin-like skin surface with no explicit sexual anatomy, no nipples and no genital detail. Front-facing A-pose, arms clearly away from the torso with visible armpit gaps, legs slightly separated, hands visible and all fingers separated, feet fully visible.";
  }

  return [
    "MetaHuman asset-isolation task. The separation rules below override any conflicting request to preserve costume or overlapping accessories.",
    `Requested asset: ${partLabel.trim()}.`,
    isolationRule,
    `Source guidance: ${clippedInstruction(sourcePrompt)}`,
    "Keep the requested asset centered, complete, uncropped and clearly separated on a plain neutral background. Do not include unrelated geometry.",
  ].join("\n");
}

export function createGenerateImagePartHandler(
  deps: GenerateImagePartDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
      const credential = await resolveTripoCredential(request);
      const body = await readJsonObject(request);
      const projectId = requiredString(body, "project_id");
      const partKey = requiredString(body, "part_key");
      const directPartLabel = optionalString(body, "part_label");
      const directPartPrompt = optionalString(body, "part_prompt");
      const customInstructions = optionalString(body, "custom_instructions");
      const requestedReferencePath = optionalString(
        body,
        "reference_storage_path",
      );

      if ((directPartLabel === undefined) !== (directPartPrompt === undefined)) {
        throw new HttpError(
          400,
          "invalid_prompt",
          "part_label and part_prompt must be provided together.",
        );
      }

      const project = await deps.findOwnedProject(userId, projectId);
      if (project === null) {
        throw new HttpError(404, "not_found", "Project was not found.");
      }
      if (!project.referenceImagePath) {
        throw new HttpError(400, "missing_reference", "Project requires a reference image.");
      }

      let referencePath = project.referenceImagePath;
      if (requestedReferencePath !== undefined) {
        const normalizedReferencePath = requestedReferencePath.trim();
        const requiredPrefix = userId + "/" + project.id + "/parts/";
        if (
          normalizedReferencePath.length === 0 ||
          normalizedReferencePath.includes("..") ||
          !normalizedReferencePath.startsWith(requiredPrefix)
        ) {
          throw new HttpError(
            400,
            "invalid_reference",
            "Part reference path is outside the owned project crop area.",
          );
        }
        referencePath = normalizedReferencePath;
      }
      let part: TemplatePart;
      let prompt: string;

      if (directPartLabel !== undefined && directPartPrompt !== undefined) {
        const label = directPartLabel.trim();
        const exactPrompt = directPartPrompt.trim();
        if (label.length === 0 || exactPrompt.length === 0 || exactPrompt.length > 1800) {
          throw new HttpError(
            400,
            "invalid_prompt",
            "Direct part label and prompt must be non-empty and within Tripo's 1800-character image prompt limit.",
          );
        }

        part = {
          key: partKey,
          label,
          promptFragment: exactPrompt,
        };
        prompt = buildMetaHumanSmartPartPrompt(partKey, label, exactPrompt);
      } else {
        if (!project.templateId) {
          throw new HttpError(400, "missing_template", "Project requires an asset template.");
        }

        const templatePart = await deps.findTemplatePart(project.templateId, partKey, userId);
        if (templatePart === null) {
          throw new HttpError(404, "not_found", "Template part was not found.");
        }
        part = templatePart;

        try {
          prompt = buildAssetPrompt({
            projectIdentity: project.identityPrompt,
            partLabel: part.label,
            partPrompt: part.promptFragment,
            customInstructions,
          });
        } catch {
          throw new HttpError(400, "invalid_prompt", "Part generation instructions are invalid.");
        }
      }

      const referenceUrl = await deps.signReferenceUrl(referencePath);
      const providerInput = await deps.uploadReferenceToProvider(
        credential.apiKey,
        referenceUrl,
      );
      const providerTaskId = await deps.createImageToImage(
        credential.apiKey,
        {
          input: providerInput,
          prompt,
        },
      );

      const jobId = await deps.insertJob({
        project_id: project.id,
        part_key: part.key,
        provider: "tripo",
        operation: "image_to_image",
        provider_task_id: providerTaskId,
        status: "queued",
        progress: 0,
        provider_credential_fingerprint: credential.fingerprint,
        request_payload_redacted: {
          part_key: part.key,
          custom_instructions_present: customInstructions !== undefined,
          prompt_source: directPartPrompt === undefined ? "template" : "client_exact",
          provider_input_source: "file_token",
          cropped_reference_used: requestedReferencePath !== undefined,
        },
      });

      return jsonResponse({ job_id: jobId }, 202);
    });
}

type ProjectRow = {
  id: string;
  reference_image_path: string | null;
  template_id: string | null;
  identity_prompt: string;
};

type TemplateRow = {
  id: string;
  owner_id: string | null;
  is_builtin: boolean;
};

type PartRow = {
  key: string;
  label: string;
  prompt_fragment: string;
};

function createDefaultDeps(): GenerateImagePartDeps {
  return {
    authenticate: authenticateSupabaseToken,
    findOwnedProject: async (userId, projectId) => {
      const row = await adminSelectOne<ProjectRow>("projects", {
        select: "id,reference_image_path,template_id,identity_prompt",
        id: `eq.${projectId}`,
        owner_id: `eq.${userId}`,
        limit: "1",
      });
      return row === null ? null : {
        id: row.id,
        referenceImagePath: row.reference_image_path,
        templateId: row.template_id,
        identityPrompt: row.identity_prompt,
      };
    },
    findTemplatePart: async (templateId, partKey, userId) => {
      const template = await adminSelectOne<TemplateRow>("asset_templates", {
        select: "id,owner_id,is_builtin",
        id: `eq.${templateId}`,
        limit: "1",
      });
      if (
        template === null ||
        (!template.is_builtin && template.owner_id !== userId)
      ) {
        return null;
      }

      const part = await adminSelectOne<PartRow>("template_parts", {
        select: "key,label,prompt_fragment",
        template_id: `eq.${templateId}`,
        key: `eq.${partKey}`,
        limit: "1",
      });
      return part === null ? null : {
        key: part.key,
        label: part.label,
        promptFragment: part.prompt_fragment,
      };
    },
    signReferenceUrl: (path) => createSignedObjectUrl("reference-images", path, 600),
    uploadReferenceToProvider: (apiKey, signedUrl) =>
      new TripoClient({ apiKey }).uploadImageFromUrl(signedUrl),
    createImageToImage: (apiKey, input) =>
      new TripoClient({ apiKey }).createImageToImage(input),
    insertJob: async (input) => {
      const row = await adminInsertOne<{ id: string }>("generation_jobs", input, "id");
      return row.id;
    },
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateImagePartHandler(createDefaultDeps()));
}
