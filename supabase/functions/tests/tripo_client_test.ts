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

Deno.test("image-to-model pins exact MVP model", async () => {
  let requestedBody: Record<string, unknown> | undefined;

  const client = new TripoClient({
    apiKey: "test-key",
    fetcher: (_input, init) => {
      requestedBody = JSON.parse(String(init?.body));
      return Promise.resolve(jsonResponse({ code: 0, data: { task_id: "task_3d" } }));
    },
  });

  const taskId = await client.createImageToModel({ input: "task_image_1" });

  assertEquals(taskId, "task_3d");
  assertEquals(requestedBody?.model, "v3.1-20260211");
  assertEquals(requestedBody?.texture, true);
  assertEquals(requestedBody?.pbr, true);
});
