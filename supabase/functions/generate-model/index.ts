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
  createSignedObjectUrl,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";

type OwnedAssetResult = {
  id: string;
  projectId: string;
  generationJobId: string;
  partKey: string | null;
  storagePath: string;
  mimeType: string;
};

type OwnedGenerationJob = {
  id: string;
  provider: string;
  providerTaskId: string | null;
  operation: string;
};

type GenerateModelDeps = {
  authenticate: (token: string) => Promise<string>;
  findOwnedAssetResult: (
    userId: string,
    assetResultId: string,
  ) => Promise<OwnedAssetResult | null>;
  findOwnedGenerationJob: (
    userId: string,
    jobId: string,
  ) => Promise<OwnedGenerationJob | null>;
  signGeneratedImageUrl: (path: string) => Promise<string>;
  createImageToModel: (input: {
    input: string;
    model: string;
    faceLimit?: number;
    quad?: boolean;
    geometryQuality?: "standard" | "detailed";
    texture: boolean;
    pbr: boolean;
    enableImageAutofix: boolean;
  }) => Promise<string>;
  insertJob: (input: Record<string, unknown>) => Promise<string>;
};


type QualityPreset = "low_poly" | "standard" | "high";
type Topology = "adaptive" | "triangles" | "quads";

type ModelProviderSettings = {
  model: string;
  faceLimit?: number;
  quad?: boolean;
  geometryQuality?: "standard" | "detailed";
  texture: boolean;
  pbr: boolean;
  enableImageAutofix: boolean;
};

function optionalBoolean(
  body: Record<string, unknown>,
  key: string,
  fallback: boolean,
): boolean {
  const value = body[key];
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "boolean") {
    throw new HttpError(400, "invalid_body", key + " must be a boolean.");
  }
  return value;
}

function optionalInteger(
  body: Record<string, unknown>,
  key: string,
): number | undefined {
  const value = body[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new HttpError(400, "invalid_body", key + " must be an integer.");
  }
  return value;
}

function optionalEnum<T extends string>(
  body: Record<string, unknown>,
  key: string,
  allowed: readonly T[],
  fallback: T,
): T {
  const value = body[key];
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new HttpError(400, "invalid_body", key + " has an unsupported value.");
  }
  return value as T;
}

function defaultFaceLimit(
  preset: QualityPreset,
  topology: Topology,
): number | undefined {
  if (topology === "adaptive") return undefined;
  if (topology === "quads") {
    return preset === "low_poly" ? 10000 : 50000;
  }
  if (preset === "low_poly") return 10000;
  if (preset === "standard") return 100000;
  return 500000;
}

function providerSettingsFromBody(
  body: Record<string, unknown>,
): {
  preset: QualityPreset;
  topology: Topology;
  provider: ModelProviderSettings;
} {
  const preset = optionalEnum<QualityPreset>(
    body,
    "quality_preset",
    ["low_poly", "standard", "high"],
    "high",
  );
  const topology = optionalEnum<Topology>(
    body,
    "topology",
    ["adaptive", "triangles", "quads"],
    "adaptive",
  );
  const texture = optionalBoolean(body, "texture", true);
  const requestedPbr = optionalBoolean(body, "pbr", true);
  const enableImageAutofix = optionalBoolean(
    body,
    "enable_image_autofix",
    false,
  );
  let faceLimit = optionalInteger(body, "face_limit");
  if (topology === "adaptive") {
    faceLimit = undefined;
  } else if (faceLimit === undefined) {
    faceLimit = defaultFaceLimit(preset, topology);
  }

  let model: string;
  let geometryQuality: "standard" | "detailed" | undefined;
  let quad: boolean | undefined;
  let minFaces = 48;
  let maxFaces: number;

  if (preset === "low_poly") {
    if (topology === "quads") {
      model = "P2-20260801";
      quad = true;
      maxFaces = 25000;
    } else {
      model = "P1-20260311";
      quad = false;
      minFaces = 50;
      maxFaces = 20000;
    }
  } else if (preset === "standard") {
    model = "v3.0-20250812";
    geometryQuality = "standard";
    quad = topology === "quads";
    maxFaces = quad ? 150000 : 1000000;
  } else {
    model = "v3.1-20260211";
    geometryQuality = "detailed";
    quad = topology === "quads";
    maxFaces = quad ? 150000 : 2000000;
  }

  if (
    faceLimit !== undefined &&
    (faceLimit < minFaces || faceLimit > maxFaces)
  ) {
    throw new HttpError(
      400,
      "invalid_face_limit",
      "face_limit is outside the supported range for the selected 3D settings.",
    );
  }

  return {
    preset,
    topology,
    provider: {
      model,
      faceLimit,
      quad,
      geometryQuality,
      texture,
      pbr: texture && requestedPbr,
      enableImageAutofix,
    },
  };
}

export function createGenerateModelHandler(
  deps: GenerateModelDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      const userId = await deps.authenticate(token);
      const body = await readJsonObject(request);
      const assetResultId = requiredString(body, "asset_result_id");

      const asset = await deps.findOwnedAssetResult(userId, assetResultId);
      if (asset === null) {
        throw new HttpError(404, "not_found", "Asset result was not found.");
      }
      if (!asset.mimeType.toLowerCase().startsWith("image/")) {
        throw new HttpError(400, "invalid_asset_type", "Only image results can generate a model.");
      }

      const sourceJob = await deps.findOwnedGenerationJob(userId, asset.generationJobId);
      if (sourceJob === null) {
        throw new HttpError(404, "not_found", "Source generation job was not found.");
      }

      const providerInput = sourceJob.provider === "tripo" &&
          sourceJob.providerTaskId?.trim().length
        ? sourceJob.providerTaskId
        : await deps.signGeneratedImageUrl(asset.storagePath);

      const settings = providerSettingsFromBody(body);
      const providerTaskId = await deps.createImageToModel({
        input: providerInput,
        ...settings.provider,
      });
      const jobId = await deps.insertJob({
        project_id: asset.projectId,
        part_key: asset.partKey,
        provider: "tripo",
        operation: "image_to_model",
        provider_task_id: providerTaskId,
        status: "queued",
        progress: 0,
        request_payload_redacted: {
          source_asset_result_id: asset.id,
          source_provider_task_reused: sourceJob.provider === "tripo" &&
            Boolean(sourceJob.providerTaskId),
          quality_preset: settings.preset,
          topology: settings.topology,
          face_limit: settings.provider.faceLimit ?? null,
          model: settings.provider.model,
          quad: settings.provider.quad ?? false,
          geometry_quality: settings.provider.geometryQuality ?? null,
          texture: settings.provider.texture,
          pbr: settings.provider.pbr,
          enable_image_autofix: settings.provider.enableImageAutofix,
        },
      });

      return jsonResponse({ job_id: jobId }, 202);
    });
}

type AssetRow = {
  id: string;
  project_id: string;
  generation_job_id: string;
  part_key: string | null;
  storage_path: string;
  mime_type: string;
};

type JobRow = {
  id: string;
  project_id: string;
  provider: string;
  provider_task_id: string | null;
  operation: string;
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

function createDefaultDeps(): GenerateModelDeps {
  const tripo = new TripoClient();

  return {
    authenticate: authenticateSupabaseToken,
    findOwnedAssetResult: async (userId, assetResultId) => {
      const row = await adminSelectOne<AssetRow>("asset_results", {
        select: "id,project_id,generation_job_id,part_key,storage_path,mime_type",
        id: `eq.${assetResultId}`,
        limit: "1",
      });
      if (row === null || !(await ownsProject(userId, row.project_id))) return null;

      return {
        id: row.id,
        projectId: row.project_id,
        generationJobId: row.generation_job_id,
        partKey: row.part_key,
        storagePath: row.storage_path,
        mimeType: row.mime_type,
      };
    },
    findOwnedGenerationJob: async (userId, jobId) => {
      const row = await adminSelectOne<JobRow>("generation_jobs", {
        select: "id,project_id,provider,provider_task_id,operation",
        id: `eq.${jobId}`,
        limit: "1",
      });
      if (row === null || !(await ownsProject(userId, row.project_id))) return null;

      return {
        id: row.id,
        provider: row.provider,
        providerTaskId: row.provider_task_id,
        operation: row.operation,
      };
    },
    signGeneratedImageUrl: (path) => createSignedObjectUrl("generated-images", path),
    createImageToModel: (input) => tripo.createImageToModel(input),
    insertJob: async (input) => {
      const row = await adminInsertOne<{ id: string }>("generation_jobs", input, "id");
      return row.id;
    },
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateModelHandler(createDefaultDeps()));
}
