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
  adminUpdate,
  authenticateSupabaseToken,
  uploadObject,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";
import type { TripoTask } from "../_shared/tripo_types.ts";

type OwnedJob = {
  id: string;
  projectId: string;
  partKey: string | null;
  providerTaskId: string | null;
  operation: string;
  status: string;
};

type PersistedOutput = {
  assetResultId: string;
  storagePath: string;
  mimeType: string;
};

type PersistSuccessfulOutputInput = {
  userId: string;
  job: OwnedJob;
  task: TripoTask;
};

type RefreshGenerationJobDeps = {
  authenticate: (token: string) => Promise<string>;
  findOwnedJob: (userId: string, jobId: string) => Promise<OwnedJob | null>;
  getProviderTask: (taskId: string) => Promise<TripoTask>;
  updateJob: (jobId: string, patch: Record<string, unknown>) => Promise<void>;
  persistSuccessfulOutput: (
    input: PersistSuccessfulOutputInput,
  ) => Promise<PersistedOutput>;
};

function normalizedProgress(progress: number): number {
  return Math.max(0, Math.min(1, progress / 100));
}

export function createRefreshGenerationJobHandler(
  deps: RefreshGenerationJobDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
      const body = await readJsonObject(request);
      const jobId = requiredString(body, "job_id");

      const job = await deps.findOwnedJob(userId, jobId);
      if (job === null) {
        throw new HttpError(404, "not_found", "Generation job was not found.");
      }
      if (!job.providerTaskId) {
        throw new HttpError(409, "invalid_job", "Generation job is missing its provider task.");
      }

      const task = await deps.getProviderTask(job.providerTaskId);
      const progress = normalizedProgress(task.progress);

      if (task.status === "queued" || task.status === "running") {
        await deps.updateJob(job.id, {
          status: task.status,
          progress,
        });
        return jsonResponse({
          job_id: job.id,
          status: task.status,
          progress,
        });
      }

      if (task.status === "failed" || task.status === "cancelled") {
        const completedAt = new Date().toISOString();
        await deps.updateJob(job.id, {
          status: task.status,
          progress,
          error_code: task.errorCode === undefined
            ? `provider_${task.status}`
            : `provider_${task.errorCode}`,
          error_message: "The generation provider reported a terminal failure.",
          completed_at: completedAt,
        });
        return jsonResponse({
          job_id: job.id,
          status: task.status,
          progress,
        });
      }

      let persisted: PersistedOutput;
      try {
        persisted = await deps.persistSuccessfulOutput({ userId, job, task });
      } catch {
        await deps.updateJob(job.id, {
          status: "failed",
          progress: 1,
          error_code: "persistence_failed",
          error_message: "Generated output could not be persisted.",
          completed_at: new Date().toISOString(),
        });
        return jsonResponse(
          {
            error: {
              code: "persistence_failed",
              message: "Generated output could not be persisted.",
            },
          },
          502,
        );
      }

      await deps.updateJob(job.id, {
        status: "success",
        progress: 1,
        error_code: null,
        error_message: null,
        completed_at: new Date().toISOString(),
      });

      return jsonResponse({
        job_id: job.id,
        status: "success",
        progress: 1,
        asset_result_id: persisted.assetResultId,
        storage_path: persisted.storagePath,
        mime_type: persisted.mimeType,
      });
    });
}

type JobRow = {
  id: string;
  project_id: string;
  part_key: string | null;
  provider_task_id: string | null;
  operation: string;
  status: string;
};

async function ownsProject(userId: string, projectId: string): Promise<boolean> {
  const project = await adminSelectOne<{ id: string }>("projects", {
    select: "id",
    id: `eq.${projectId}`,
    owner_id: `eq.${userId}`,
    limit: "1",
  });
  return project !== null;
}

function outputString(output: Record<string, unknown> | undefined, key: string): string | null {
  const value = output?.[key];
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function firstStringFromArray(
  output: Record<string, unknown> | undefined,
  key: string,
): string | null {
  const value = output?.[key];
  if (!Array.isArray(value)) return null;
  for (const item of value) {
    if (typeof item === "string" && item.trim().length > 0) return item;
    if (
      typeof item === "object" &&
      item !== null &&
      !Array.isArray(item) &&
      typeof (item as Record<string, unknown>).url === "string"
    ) {
      return (item as Record<string, unknown>).url as string;
    }
  }
  return null;
}

function providerOutputUrl(job: OwnedJob, task: TripoTask): string {
  if (job.operation === "image_to_model") {
    const modelUrl = outputString(task.output, "model_url");
    if (modelUrl) return modelUrl;
    throw new Error("Tripo model task did not contain model_url.");
  }

  const imageUrl = outputString(task.output, "image_url") ??
    outputString(task.output, "url") ??
    firstStringFromArray(task.output, "image_urls") ??
    firstStringFromArray(task.output, "images");

  if (!imageUrl) {
    throw new Error("Tripo image task did not contain an output image URL.");
  }
  return imageUrl;
}

function normalizedMime(response: Response): string {
  return (response.headers.get("content-type") ?? "")
    .split(";")[0]
    .trim()
    .toLowerCase();
}

function outputTarget(
  operation: string,
  mimeType: string,
): { bucket: string; extension: string } {
  if (operation === "image_to_model") {
    if (
      !["model/gltf-binary", "application/octet-stream", "application/x-binary"].includes(mimeType)
    ) {
      throw new Error("Provider model output MIME type is not allowed.");
    }
    return { bucket: "generated-models", extension: "glb" };
  }

  const extensions: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/webp": "webp",
  };
  const extension = extensions[mimeType];
  if (!extension) {
    throw new Error("Provider image output MIME type is not allowed.");
  }
  return { bucket: "generated-images", extension };
}

async function persistOutput(
  input: PersistSuccessfulOutputInput,
): Promise<PersistedOutput> {
  const url = providerOutputUrl(input.job, input.task);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Provider output download failed with status ${response.status}.`);
  }

  const mimeType = normalizedMime(response);
  const target = outputTarget(input.job.operation, mimeType);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0) {
    throw new Error("Provider output was empty.");
  }

  const storagePath =
    `${input.userId}/${input.job.projectId}/${input.job.id}.${target.extension}`;
  await uploadObject(target.bucket, storagePath, bytes, mimeType);

  const result = await adminInsertOne<{ id: string }>(
    "asset_results",
    {
      project_id: input.job.projectId,
      generation_job_id: input.job.id,
      part_key: input.job.partKey,
      storage_path: storagePath,
      mime_type: mimeType,
      width: null,
      height: null,
    },
    "id",
  );

  return {
    assetResultId: result.id,
    storagePath,
    mimeType,
  };
}

function createDefaultDeps(): RefreshGenerationJobDeps {
  const tripo = new TripoClient();

  return {
    authenticate: authenticateSupabaseToken,
    findOwnedJob: async (userId, jobId) => {
      const row = await adminSelectOne<JobRow>("generation_jobs", {
        select: "id,project_id,part_key,provider_task_id,operation,status",
        id: `eq.${jobId}`,
        limit: "1",
      });
      if (row === null || !(await ownsProject(userId, row.project_id))) return null;

      return {
        id: row.id,
        projectId: row.project_id,
        partKey: row.part_key,
        providerTaskId: row.provider_task_id,
        operation: row.operation,
        status: row.status,
      };
    },
    getProviderTask: (taskId) => tripo.getTask(taskId),
    updateJob: (jobId, patch) =>
      adminUpdate("generation_jobs", { id: `eq.${jobId}` }, patch),
    persistSuccessfulOutput: persistOutput,
  };
}

if (import.meta.main) {
  Deno.serve(createRefreshGenerationJobHandler(createDefaultDeps()));
}
