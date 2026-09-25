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
  uploadReferenceToProvider: (signedUrl: string) => Promise<string>;
  createImageToImage: (input: { input: string; prompt: string }) => Promise<string>;
  insertJob: (input: Record<string, unknown>) => Promise<string>;
};

export function createGenerateImagePartHandler(
  deps: GenerateImagePartDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
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
        prompt = exactPrompt;
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
      const providerInput = await deps.uploadReferenceToProvider(referenceUrl);
      const providerTaskId = await deps.createImageToImage({
        input: providerInput,
        prompt,
      });

      const jobId = await deps.insertJob({
        project_id: project.id,
        part_key: part.key,
        provider: "tripo",
        operation: "image_to_image",
        provider_task_id: providerTaskId,
        status: "queued",
        progress: 0,
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
  const tripo = new TripoClient();

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
    uploadReferenceToProvider: (signedUrl) => tripo.uploadImageFromUrl(signedUrl),
    createImageToImage: (input) => tripo.createImageToImage(input),
    insertJob: async (input) => {
      const row = await adminInsertOne<{ id: string }>("generation_jobs", input, "id");
      return row.id;
    },
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateImagePartHandler(createDefaultDeps()));
}
