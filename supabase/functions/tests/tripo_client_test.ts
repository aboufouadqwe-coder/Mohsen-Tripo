import { assertEquals, assertInstanceOf, assertRejects } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { TripoClient } from "../_shared/tripo_client.ts";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.test("createTextToImage returns task id on code 0", async () => {
  let requestedUrl = "";
  let requestedBody: Record<string, unknown> | undefined;

  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: (input, init) => {
      requestedUrl = String(input);
      requestedBody = JSON.parse(String(init?.body));
      return Promise.resolve(jsonResponse({ code: 0, data: { task_id: "task_image_1" } }));
    },
  });

  const taskId = await client.createTextToImage({ prompt: "abandoned hospital door" });

  assertEquals(taskId, "task_image_1");
  assertEquals(requestedUrl, "https://openapi.tripo3d.ai/v3/generation/text-to-image");
  assertEquals(requestedBody?.model, "seedream_v5");
  assertEquals(requestedBody?.size, "2K");
  assertEquals(requestedBody?.output_format, "png");
  assertEquals(requestedBody?.watermark, false);
});

Deno.test("nonzero provider code throws ProviderError", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: () =>
      Promise.resolve(jsonResponse({
        code: 2010,
        message: "Insufficient credits",
        suggestion: "Please top up your account",
      })),
  });

  const error = await assertRejects(
    () => client.createTextToImage({ prompt: "patient head" }),
  );

  assertInstanceOf(error, ProviderError);
  assertEquals(error.code, "provider_rejected");
  assertEquals(error.providerCode, 2010);
});

Deno.test("missing task id throws malformed_response", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: () => Promise.resolve(jsonResponse({ code: 0, data: {} })),
  });

  const error = await assertRejects(
    () =>
      client.createImageToImage({
        input: "https://example.test/reference.png",
        prompt: "same character head",
      }),
  );

  assertInstanceOf(error, ProviderError);
  assertEquals(error.code, "malformed_response");
});

Deno.test("unknown task status throws unknown_status", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: () =>
      Promise.resolve(jsonResponse({
        code: 0,
        data: {
          task_id: "task_1",
          type: "image_to_image",
          status: "mystery",
          progress: 12,
        },
      })),
  });

  const error = await assertRejects(() => client.getTask("task_1"));

  assertInstanceOf(error, ProviderError);
  assertEquals(error.code, "unknown_status");
});

Deno.test("missing api key fails before network access", async () => {
  let fetchCalls = 0;
  const client = new TripoClient({
    apiKey: "",
    fetcher: () => {
      fetchCalls += 1;
      return Promise.resolve(jsonResponse({ code: 0, data: { task_id: "never" } }));
    },
  });

  const error = await assertRejects(
    () => client.createTextToImage({ prompt: "head" }),
  );

  assertInstanceOf(error, ProviderError);
  assertEquals(error.code, "missing_api_key");
  assertEquals(fetchCalls, 0);
});

Deno.test("image-to-model forwards configurable mesh settings", async () => {
  let requestedBody: Record<string, unknown> | undefined;

  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: (_input, init) => {
      requestedBody = JSON.parse(String(init?.body));
      return Promise.resolve(jsonResponse({ code: 0, data: { task_id: "task_3d" } }));
    },
  });

  const taskId = await client.createImageToModel({
    input: "task_image_1",
    model: "v3.1-20260211",
    faceLimit: 500000,
    quad: false,
    geometryQuality: "detailed",
    texture: true,
    pbr: true,
    enableImageAutofix: true,
  });

  assertEquals(taskId, "task_3d");
  assertEquals(requestedBody?.model, "v3.1-20260211");
  assertEquals(requestedBody?.face_limit, 500000);
  assertEquals(requestedBody?.quad, false);
  assertEquals(requestedBody?.geometry_quality, "detailed");
  assertEquals(requestedBody?.texture, true);
  assertEquals(requestedBody?.pbr, true);
  assertEquals(requestedBody?.enable_image_autofix, true);
});

Deno.test("getTask accepts queued response without progress", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: () =>
      Promise.resolve(jsonResponse({
        code: 0,
        data: {
          task_id: "task_queued",
          type: "image_to_image",
          status: "queued",
        },
      })),
  });

  const task = await client.getTask("task_queued");

  assertEquals(task.status, "queued");
  assertEquals(task.progress, 0);
});

Deno.test("getTask accepts Tripo terminal banned status", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: () =>
      Promise.resolve(jsonResponse({
        code: 0,
        data: {
          task_id: "task_banned",
          type: "image_to_image",
          status: "banned",
        },
      })),
  });

  const task = await client.getTask("task_banned");

  assertEquals(task.status, "banned");
  assertEquals(task.progress, 0);
});


Deno.test("uploadImageFromUrl uploads private image and returns file token", async () => {
  const urls: string[] = [];
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: (input, init) => {
      const url = String(input);
      urls.push(url);
      if (url === "https://signed.test/reference.png") {
        return Promise.resolve(
          new Response(new Uint8Array([1, 2, 3]), {
            status: 200,
            headers: { "content-type": "image/png" },
          }),
        );
      }
      assertEquals(url, "https://openapi.tripo3d.ai/v3/files");
      assertEquals(init?.method, "POST");
      assertEquals(init?.body instanceof FormData, true);
      return Promise.resolve(
        jsonResponse({ code: 0, data: { file_token: "file_reference_1" } }),
      );
    },
  });

  const token = await client.uploadImageFromUrl(
    "https://signed.test/reference.png",
  );

  assertEquals(token, "file_reference_1");
  assertEquals(urls, [
    "https://signed.test/reference.png",
    "https://openapi.tripo3d.ai/v3/files",
  ]);
});

Deno.test("getBalance returns available and frozen decimal credits", async () => {
  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: (input, init) => {
      assertEquals(
        String(input),
        "https://openapi.tripo3d.ai/v3/account/balance",
      );
      assertEquals(init?.method, "GET");
      return Promise.resolve(
        jsonResponse({
          code: 0,
          data: { balance: 1234.5, frozen: 30.25 },
        }),
      );
    },
  });

  const balance = await client.getBalance();

  assertEquals(balance, { balance: 1234.5, frozen: 30.25 });
});
