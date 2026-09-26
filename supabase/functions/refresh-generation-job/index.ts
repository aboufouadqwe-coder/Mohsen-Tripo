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
import { resolveTripoCredential } from "../_shared/tripo_credential.ts";
import type { TripoTask } from "../_shared/tripo_types.ts";

type OwnedJob = {
  id: string;
  projectId: string;
  partKey: string | null;
  provider: string;
  providerTaskId: string | null;
  operation: string;
  status: string;
  providerCredentialFingerprint: string | null;
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
  getProviderTask: (apiKey: string, taskId: string) => Promise<TripoTask>;
  updateJob: (jobId: string, patch: Record<string, unknown>) => Promise<void>;
  persistSuccessfulOutput: (
    input: PersistSuccessfulOutputInput,
  ) => Promise<PersistedOutput>;
};

type ProviderArtifactUrl = {
  role: "primary" | "preview";
  bucket: "generated-images" | "generated-models";
  url: string;
};

function normalizedProgress(progress: number): number {
  return Math.max(0, Math.min(1, progress / 100));
}

function normalizedJobBody(
  job: OwnedJob,
  status: string,
  progress: number,
): Record<string, unknown> {
  return {
    job_id: job.id,
    project_id: job.projectId,
    part_key: job.partKey,
    provider: job.provider,
    operation: job.operation,
    provider_task_id: job.providerTaskId,
    status,
    progress,
    provider_credential_fingerprint: job.providerCredentialFingerprint,
  };
}

export function createRefreshGenerationJobHandler(
  deps: RefreshGenerationJobDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
      const credential = await resolveTripoCredential(request);
      const body = await readJsonObject(request);
      const jobId = requiredString(body, "job_id");

      const job = await deps.findOwnedJob(userId, jobId);
      if (job === null) {
        throw new HttpError(404, "not_found", "Generation job was not found.");
      }
      if (!job.providerTaskId) {
        throw new HttpError(
          409,
          "invalid_job",
          "Generation job is missing its provider task.",
        );
      }
      if (
        job.providerCredentialFingerprint !== null &&
        job.providerCredentialFingerprint !== credential.fingerprint
      ) {
        throw new HttpError(
          409,
          "credential_mismatch",
          "This job must be refreshed with the Tripo key that created it.",
        );
      }

      const task = await deps.getProviderTask(
        credential.apiKey,
        job.providerTaskId,
      );
      const progress = normalizedProgress(task.progress);

      if (
        task.status === "queued" ||
        task.status === "running" ||
        task.status === "unknown"
      ) {
        const jobStatus = task.status === "queued" ? "queued" : "running";
        await deps.updateJob(job.id, {
          status: jobStatus,
          progress,
        });
        return jsonResponse(
          normalizedJobBody(job, jobStatus, progress),
        );
      }

      if (
        task.status === "failed" ||
        task.status === "cancelled" ||
        task.status === "banned" ||
        task.status === "expired"
      ) {
        const completedAt = new Date().toISOString();
        const jobStatus = task.status === "cancelled" ? "cancelled" : "failed";
        await deps.updateJob(job.id, {
          status: jobStatus,
          progress,
          error_code: task.errorCode === undefined
            ? "provider_" + task.status
            : "provider_" + task.errorCode,
          error_message: "The generation provider reported a terminal failure.",
          completed_at: completedAt,
        });
        return jsonResponse(
          normalizedJobBody(job, jobStatus, progress),
        );
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
        ...normalizedJobBody(job, "success", 1),
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
  provider: string;
  provider_task_id: string | null;
  operation: string;
  status: string;
  provider_credential_fingerprint: string | null;
};

async function ownsProject(
  userId: string,
  projectId: string,
): Promise<boolean> {
  const project = await adminSelectOne<{ id: string }>("projects", {
    select: "id",
    id: "eq." + projectId,
    owner_id: "eq." + userId,
    limit: "1",
  });
  return project !== null;
}

function outputString(
  output: Record<string, unknown> | undefined,
  key: string,
): string | null {
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

export function providerArtifactUrls(
  operation: string,
  output: Record<string, unknown> | undefined,
): ProviderArtifactUrl[] {
  if (operation === "image_to_model") {
    const modelUrl = outputString(output, "model_url");
    if (!modelUrl) {
      throw new Error("Tripo model task did not contain model_url.");
    }

    const artifacts: ProviderArtifactUrl[] = [
      {
        role: "primary",
        bucket: "generated-models",
        url: modelUrl,
      },
    ];

    const previewUrl = outputString(output, "rendered_image_url") ??
      outputString(output, "preview_image_url") ??
      firstStringFromArray(output, "rendered_images");

    if (previewUrl) {
      artifacts.push({
        role: "preview",
        bucket: "generated-images",
        url: previewUrl,
      });
    }

    return artifacts;
  }

  const imageUrl = outputString(output, "generated_image_url") ??
    outputString(output, "image_url") ??
    outputString(output, "url") ??
    firstStringFromArray(output, "image_urls") ??
    firstStringFromArray(output, "images");

  if (!imageUrl) {
    throw new Error("Tripo image task did not contain an output image URL.");
  }

  return [
    {
      role: "primary",
      bucket: "generated-images",
      url: imageUrl,
    },
  ];
}

function normalizedMime(response: Response): string {
  return (response.headers.get("content-type") ?? "")
    .split(";")[0]
    .trim()
    .toLowerCase();
}

function isGlb(bytes: ArrayBuffer): boolean {
  if (bytes.byteLength < 4) return false;
  const header = new Uint8Array(bytes, 0, 4);
  return header[0] === 0x67 &&
    header[1] === 0x6c &&
    header[2] === 0x54 &&
    header[3] === 0x46;
}

function isFbx(bytes: ArrayBuffer): boolean {
  const signature = "Kaydara FBX Binary";
  if (bytes.byteLength < signature.length) return false;
  const header = new Uint8Array(bytes, 0, signature.length);
  for (let index = 0; index < signature.length; index += 1) {
    if (header[index] !== signature.charCodeAt(index)) return false;
  }
  return true;
}

export function providerOutputTarget(
  bucket: "generated-images" | "generated-models",
  mimeType: string,
  url = "",
  bytes?: ArrayBuffer,
): { extension: string; mimeType: string } {
  if (bucket === "generated-models") {
    const normalizedUrl = url.toLowerCase();
    const normalizedMime = mimeType.toLowerCase();

    if (
      (bytes !== undefined && isFbx(bytes)) ||
      normalizedUrl.includes(".fbx") ||
      normalizedMime.includes("fbx")
    ) {
      return {
        extension: "fbx",
        mimeType: "application/octet-stream",
      };
    }

    if (
      bytes === undefined ||
      isGlb(bytes) ||
      normalizedUrl.includes(".glb") ||
      normalizedMime === "model/gltf-binary"
    ) {
      return {
        extension: "glb",
        mimeType: "model/gltf-binary",
      };
    }

    throw new Error("Provider model output format is not supported.");
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
  return { extension, mimeType };
}

async function persistOutput(
  input: PersistSuccessfulOutputInput,
): Promise<PersistedOutput> {
  const artifacts = providerArtifactUrls(
    input.job.operation,
    input.task.output,
  );
  let primary: PersistedOutput | null = null;

  for (const artifact of artifacts) {
    try {
      const response = await fetch(artifact.url);
      if (!response.ok) {
        throw new Error(
          "Provider output download failed with status " +
            response.status +
            ".",
        );
      }

      const responseMimeType = normalizedMime(response);
      const bytes = await response.arrayBuffer();
      if (bytes.byteLength === 0) {
        throw new Error("Provider output was empty.");
      }

      const target = providerOutputTarget(
        artifact.bucket,
        responseMimeType,
        artifact.url,
        bytes,
      );

      const suffix = artifact.role === "preview" ? "-preview" : "";
      const storagePath = input.userId +
        "/" +
        input.job.projectId +
        "/" +
        input.job.id +
        suffix +
        "." +
        target.extension;

      await uploadObject(
        artifact.bucket,
        storagePath,
        bytes,
        target.mimeType,
      );

      const result = await adminInsertOne<{ id: string }>(
        "asset_results",
        {
          project_id: input.job.projectId,
          generation_job_id: input.job.id,
          part_key: input.job.partKey,
          storage_path: storagePath,
          mime_type: target.mimeType,
          width: null,
          height: null,
        },
        "id",
      );

      if (artifact.role === "primary") {
        primary = {
          assetResultId: result.id,
          storagePath,
          mimeType: target.mimeType,
        };
      }
    } catch (error) {
      if (artifact.role === "preview" && primary !== null) {
        console.warn(
          "Optional model preview persistence failed.",
          {
            operation: input.job.operation,
            bucket: artifact.bucket,
          },
        );
        continue;
      }
      throw error;
    }
  }

  if (primary === null) {
    throw new Error("Provider output did not contain a primary artifact.");
  }
  return primary;
}

function createDefaultDeps(): RefreshGenerationJobDeps {
  return {
    authenticate: authenticateSupabaseToken,
    findOwnedJob: async (userId, jobId) => {
      const row = await adminSelectOne<JobRow>("generation_jobs", {
        select:
          "id,project_id,part_key,provider,provider_task_id,operation,status,provider_credential_fingerprint",
        id: "eq." + jobId,
        limit: "1",
      });
      if (
        row === null ||
        !(await ownsProject(userId, row.project_id))
      ) {
        return null;
      }

      return {
        id: row.id,
        projectId: row.project_id,
        partKey: row.part_key,
        provider: row.provider,
        providerTaskId: row.provider_task_id,
        operation: row.operation,
        status: row.status,
        providerCredentialFingerprint: row.provider_credential_fingerprint,
      };
    },
    getProviderTask: (apiKey, taskId) =>
      new TripoClient({ apiKey }).getTask(taskId),
    updateJob: (jobId, patch) =>
      adminUpdate(
        "generation_jobs",
        { id: "eq." + jobId },
        patch,
      ),
    persistSuccessfulOutput: persistOutput,
  };
}

if (import.meta.main) {
  Deno.serve(createRefreshGenerationJobHandler(createDefaultDeps()));
}
