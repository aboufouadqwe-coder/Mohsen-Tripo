import { assertEquals } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { createGenerateModelHandler } from "../generate-model/index.ts";

const secret = "TRIPO_SUPER_SECRET";

function request(body: unknown, authenticated = true): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/generate-model", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
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
        }
        : null,
    ),
  signGeneratedImageUrl: (_path: string) => Promise.resolve("https://signed.test/head.png"),
  createImageToModel: (_input: { input: string }) => Promise.resolve("task-model-1"),
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
    createImageToModel: (input: { input: string }) => {
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
