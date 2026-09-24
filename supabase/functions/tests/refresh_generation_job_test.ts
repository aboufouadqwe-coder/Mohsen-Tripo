import { assertEquals } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { createRefreshGenerationJobHandler } from "../refresh-generation-job/index.ts";

const secret = "TRIPO_SUPER_SECRET";

function request(body: unknown, authenticated = true): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/refresh-generation-job", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const baseJob = {
  id: "job-1",
  projectId: "project-1",
  partKey: "head",
  provider: "tripo",
  providerTaskId: "task-1",
  operation: "image_to_image",
  status: "running",
};

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
  findOwnedJob: (_userId: string, jobId: string) =>
    Promise.resolve(jobId === "job-1" ? baseJob : null),
  getProviderTask: (_taskId: string) =>
    Promise.resolve({
      taskId: "task-1",
      type: "image_to_image",
      status: "running" as const,
      progress: 40,
    }),
  updateJob: (_jobId: string, _patch: unknown) => Promise.resolve(),
  persistSuccessfulOutput: (_input: unknown) =>
    Promise.resolve({
      assetResultId: "asset-1",
      storagePath: "user-1/project-1/head.png",
      mimeType: "image/png",
    }),
};

Deno.test("refresh-generation-job requires Authorization", async () => {
  const handler = createRefreshGenerationJobHandler(baseDeps);
  const response = await handler(request({ job_id: "job-1" }, false));
  assertEquals(response.status, 401);
});

Deno.test("refresh-generation-job rejects malformed body", async () => {
  const handler = createRefreshGenerationJobHandler(baseDeps);
  const response = await handler(request({ job_id: "" }));
  assertEquals(response.status, 400);
});

Deno.test("refresh-generation-job hides job ownership", async () => {
  const handler = createRefreshGenerationJobHandler(baseDeps);
  const response = await handler(request({ job_id: "other-job" }));
  assertEquals(response.status, 404);
});

Deno.test("refresh-generation-job maps provider failures without leaking secrets", async () => {
  const handler = createRefreshGenerationJobHandler({
    ...baseDeps,
    getProviderTask: () =>
      Promise.reject(
        new ProviderError("provider_rejected", `provider said ${secret}`, 2010),
      ),
  });

  const response = await handler(request({ job_id: "job-1" }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(text.includes(secret), false);
});

Deno.test("refresh-generation-job normalizes running progress", async () => {
  let patch: Record<string, unknown> | undefined;
  const handler = createRefreshGenerationJobHandler({
    ...baseDeps,
    updateJob: (_jobId: string, value: unknown) => {
      patch = value as Record<string, unknown>;
      return Promise.resolve();
    },
  });

  const response = await handler(request({ job_id: "job-1" }));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(patch?.status, "running");
  assertEquals(patch?.progress, 0.4);
  assertEquals(body.status, "running");
});

Deno.test("refresh-generation-job persists successful output before success", async () => {
  const calls: string[] = [];
  const handler = createRefreshGenerationJobHandler({
    ...baseDeps,
    getProviderTask: () =>
      Promise.resolve({
        taskId: "task-1",
        type: "image_to_image",
        status: "success" as const,
        progress: 100,
        output: { image_url: "https://provider.test/generated.png" },
      }),
    persistSuccessfulOutput: (_input: unknown) => {
      calls.push("persist");
      return Promise.resolve({
        assetResultId: "asset-1",
        storagePath: "user-1/project-1/head.png",
        mimeType: "image/png",
      });
    },
    updateJob: (_jobId: string, patch: unknown) => {
      const status = (patch as Record<string, unknown>).status;
      if (status === "success") calls.push("success");
      return Promise.resolve();
    },
  });

  const response = await handler(request({ job_id: "job-1" }));
  assertEquals(response.status, 200);
  assertEquals(calls, ["persist", "success"]);
});

Deno.test("refresh-generation-job marks persistence failure", async () => {
  let patch: Record<string, unknown> | undefined;
  const handler = createRefreshGenerationJobHandler({
    ...baseDeps,
    getProviderTask: () =>
      Promise.resolve({
        taskId: "task-1",
        type: "image_to_image",
        status: "success" as const,
        progress: 100,
        output: { image_url: "https://provider.test/generated.png" },
      }),
    persistSuccessfulOutput: () => Promise.reject(new Error("storage unavailable")),
    updateJob: (_jobId: string, value: unknown) => {
      patch = value as Record<string, unknown>;
      return Promise.resolve();
    },
  });

  const response = await handler(request({ job_id: "job-1" }));

  assertEquals(response.status, 502);
  assertEquals(patch?.status, "failed");
  assertEquals(patch?.error_code, "persistence_failed");
});

Deno.test("refresh-generation-job maps banned provider status to failed", async () => {
  let patch: Record<string, unknown> | undefined;
  const handler = createRefreshGenerationJobHandler({
    ...baseDeps,
    getProviderTask: () =>
      Promise.resolve({
        taskId: "task-1",
        type: "image_to_image",
        status: "banned" as const,
        progress: 0,
      }),
    updateJob: (_jobId: string, value: unknown) => {
      patch = value as Record<string, unknown>;
      return Promise.resolve();
    },
  });

  const response = await handler(request({ job_id: "job-1" }));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(patch?.status, "failed");
  assertEquals(patch?.error_code, "provider_banned");
  assertEquals(body.status, "failed");
});
