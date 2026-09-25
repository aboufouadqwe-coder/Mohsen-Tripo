import { assertEquals } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { createGenerateModelHandler } from "../generate-model/index.ts";

const secret = "TRIPO_SUPER_SECRET";

function request(body: unknown, authenticated = true): Request {
  const headers = new Headers({ "content-type": "application/json" });
  headers.set("x-tripo-api-key", "tsk_test_key_12345678901234567890");
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/generate-model", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
  findOwnedProject: (_userId: string, projectId: string) =>
    Promise.resolve(projectId === "project-1" ? { id: projectId } : null),
  findOwnedAssetResult: (_userId: string, assetResultId: string) =>
    Promise.resolve(
      assetResultId === "asset-1"
        ? {
          id: assetResultId,
          projectId: "project-1",
          generationJobId: "image-job-1",
          partKey: "head",
          storagePath: "user-1/project-1/head.png",
          mimeType: "image/png",
        }
        : null,
    ),
  findOwnedGenerationJob: (_userId: string, jobId: string) =>
    Promise.resolve(
      jobId === "image-job-1"
        ? {
          id: jobId,
          provider: "tripo",
          providerTaskId: "task-image-1",
          operation: "image_to_image",
          providerCredentialFingerprint: null,
        }
        : null,
    ),
  signGeneratedImageUrl: (_path: string) =>
    Promise.resolve("https://signed.test/head.png"),
  signReferenceImageUrl: (_path: string) =>
    Promise.resolve("https://signed.test/reference.png"),
  uploadImageToProvider: (_apiKey: string, _url: string) =>
    Promise.resolve("file_token_uploaded_1"),
  createImageToModel: (_apiKey: string, _input: {
    input: string;
    model: string;
    faceLimit?: number;
    quad?: boolean;
    geometryQuality?: "standard" | "detailed";
    texture: boolean;
    pbr: boolean;
    enableImageAutofix: boolean;
  }) => Promise.resolve("task-model-1"),
  insertJob: (_input: unknown) => Promise.resolve("job-model-1"),
};

Deno.test("generate-model requires Authorization", async () => {
  const handler = createGenerateModelHandler(baseDeps);
  const response = await handler(request({ asset_result_id: "asset-1" }, false));
  assertEquals(response.status, 401);
});

Deno.test("generate-model rejects malformed body", async () => {
  const handler = createGenerateModelHandler(baseDeps);
  const response = await handler(request({ asset_result_id: "" }));
  assertEquals(response.status, 400);
});

Deno.test("generate-model hides result ownership", async () => {
  const handler = createGenerateModelHandler(baseDeps);
  const response = await handler(request({ asset_result_id: "other-asset" }));
  assertEquals(response.status, 404);
});

Deno.test("generate-model maps provider failures without leaking secrets", async () => {
  const handler = createGenerateModelHandler({
    ...baseDeps,
    createImageToModel: () =>
      Promise.reject(
        new ProviderError("provider_rejected", `provider said ${secret}`, 2010),
      ),
  });

  const response = await handler(request({ asset_result_id: "asset-1" }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(text.includes(secret), false);
});

Deno.test("generate-model prefers prior Tripo image task id", async () => {
  let providerInput = "";
  const handler = createGenerateModelHandler({
    ...baseDeps,
    createImageToModel: (_apiKey: string, input) => {
      providerInput = input.input;
      return Promise.resolve("task-model-1");
    },
  });

  const response = await handler(request({ asset_result_id: "asset-1" }));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body, { job_id: "job-model-1" });
  assertEquals(providerInput, "task-image-1");
});


Deno.test("generate-model maps low-poly quad settings to P2", async () => {
  let providerRequest: Record<string, unknown> = {};
  let inserted: Record<string, unknown> = {};

  const handler = createGenerateModelHandler({
    ...baseDeps,
    createImageToModel: (_apiKey: string, input) => {
      providerRequest = input;
      return Promise.resolve("task-model-quad");
    },
    insertJob: (input) => {
      inserted = input;
      return Promise.resolve("job-model-quad");
    },
  });

  const response = await handler(
    request({
      asset_result_id: "asset-1",
      quality_preset: "low_poly",
      topology: "quads",
      face_limit: 12000,
      texture: true,
      pbr: false,
      enable_image_autofix: true,
    }),
  );

  assertEquals(response.status, 202);
  assertEquals(providerRequest, {
    input: "task-image-1",
    model: "P2-20260801",
    faceLimit: 12000,
    quad: true,
    geometryQuality: undefined,
    texture: true,
    pbr: false,
    enableImageAutofix: true,
  });
  const redacted = inserted.request_payload_redacted as Record<string, unknown>;
  assertEquals(redacted.quality_preset, "low_poly");
  assertEquals(redacted.topology, "quads");
  assertEquals(redacted.face_limit, 12000);
});

Deno.test("generate-model rejects face limit outside selected mode", async () => {
  const handler = createGenerateModelHandler(baseDeps);
  const response = await handler(
    request({
      asset_result_id: "asset-1",
      quality_preset: "low_poly",
      topology: "quads",
      face_limit: 50000,
    }),
  );

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.code, "invalid_face_limit");
});


Deno.test("generate-model accepts an owned direct model input path", async () => {
  let signedPath = "";
  let uploadedUrl = "";
  let providerInput = "";

  const handler = createGenerateModelHandler({
    ...baseDeps,
    findOwnedProject: (_userId: string, projectId: string) =>
      Promise.resolve(projectId === "project-1" ? { id: projectId } : null),
    signReferenceImageUrl: (path: string) => {
      signedPath = path;
      return Promise.resolve("https://signed.test/model-input.png");
    },
    uploadImageToProvider: (
      _apiKey: string,
      url: string,
    ) => {
      uploadedUrl = url;
      return Promise.resolve("file_token_direct_1");
    },
    createImageToModel: (_apiKey: string, input) => {
      providerInput = input.input;
      return Promise.resolve("task-model-direct");
    },
  });

  const response = await handler(
    request({
      project_id: "project-1",
      reference_storage_path:
        "user-1/project-1/model-inputs/model-input-1.png",
    }),
  );

  assertEquals(response.status, 202);
  assertEquals(signedPath, "user-1/project-1/model-inputs/model-input-1.png");
  assertEquals(uploadedUrl, "https://signed.test/model-input.png");
  assertEquals(providerInput, "file_token_direct_1");
});

Deno.test("generate-model rejects direct model input outside owned project", async () => {
  const handler = createGenerateModelHandler({
    ...baseDeps,
    findOwnedProject: (_userId: string, projectId: string) =>
      Promise.resolve(projectId === "project-1" ? { id: projectId } : null),
    signReferenceImageUrl: (_path: string) =>
      Promise.resolve("https://signed.test/model-input.png"),
    uploadImageToProvider: (_apiKey: string, _url: string) =>
      Promise.resolve("file_token_direct_1"),
  });

  const response = await handler(
    request({
      project_id: "project-1",
      reference_storage_path:
        "user-2/project-1/model-inputs/model-input-1.png",
    }),
  );

  assertEquals(response.status, 400);
});
