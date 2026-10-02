import {
  executeHttp,
  HttpError,
  jsonResponse,
  readJsonObject,
  requireBearerToken,
  requiredString,
} from "../_shared/http.ts";
import {
  adminInsertOne,
  adminSelectOne,
  authenticateSupabaseToken,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";
import { resolveTripoCredential } from "../_shared/tripo_credential.ts";

type OwnedProject = { id: string };

type GenerateSourceImageDeps = {
  authenticate: (token: string) => Promise<string>;
  findOwnedProject: (userId: string, projectId: string) => Promise<OwnedProject | null>;
  createTextToImage: (apiKey: string, prompt: string) => Promise<string>;
  insertJob: (input: Record<string, unknown>) => Promise<string>;
};

function countWords(value: string): number {
  const trimmed = value.trim();
  return trimmed.length === 0 ? 0 : trimmed.split(/\s+/).length;
}

export function createGenerateSourceImageHandler(
  deps: GenerateSourceImageDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
      const credential = await resolveTripoCredential(request);
      const body = await readJsonObject(request);
      const projectId = requiredString(body, "project_id");
      const prompt = requiredString(body, "prompt");

      if (countWords(prompt) > 600) {
        throw new HttpError(400, "prompt_too_long", "Prompt must contain at most 600 words.");
      }

      const project = await deps.findOwnedProject(userId, projectId);
      if (project === null) {
        throw new HttpError(404, "not_found", "Project was not found.");
      }

      const providerTaskId = await deps.createTextToImage(
        credential.apiKey,
        prompt,
      );
      const jobId = await deps.insertJob({
        project_id: project.id,
        part_key: null,
        provider: "tripo",
        operation: "text_to_image",
        provider_task_id: providerTaskId,
        status: "queued",
        progress: 0,
        provider_credential_fingerprint: credential.fingerprint,
        request_payload_redacted: {
          prompt_words: countWords(prompt),
          prompt_characters: Array.from(prompt).length,
        },
      });

      return jsonResponse({ job_id: jobId }, 202);
    });
}

function createDefaultDeps(): GenerateSourceImageDeps {
  return {
    authenticate: authenticateSupabaseToken,
    findOwnedProject: (userId, projectId) =>
      adminSelectOne<OwnedProject>("projects", {
        select: "id",
        id: `eq.${projectId}`,
        owner_id: `eq.${userId}`,
        limit: "1",
      }),
    createTextToImage: (apiKey, prompt) =>
      new TripoClient({ apiKey }).createTextToImage({ prompt }),
    insertJob: async (input) => {
      const row = await adminInsertOne<{ id: string }>("generation_jobs", input, "id");
      return row.id;
    },
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateSourceImageHandler(createDefaultDeps()));
}
