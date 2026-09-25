import { assertEquals } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { createGenerateSourceImageHandler } from "../generate-source-image/index.ts";

const secret = "TRIPO_SUPER_SECRET";

function request(body: unknown, authenticated = true): Request {
  const headers = new Headers({ "content-type": "application/json" });\n  headers.set("x-tripo-api-key", "tsk_test_key_12345678901234567890");
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/generate-source-image", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
  findOwnedProject: (_userId: string, projectId: string) =>
    Promise.resolve(projectId === "project-1" ? { id: projectId } : null),
  createTextToImage: (_apiKey: string, _prompt: string) => Promise.resolve("task-source-1"),
  insertJob: (_input: unknown) => Promise.resolve("job-source-1"),
};

Deno.test("generate-source-image requires Authorization", async () => {
  const handler = createGenerateSourceImageHandler(baseDeps);
  const response = await handler(request({ project_id: "project-1", prompt: "patient" }, false));
  assertEquals(response.status, 401);
});

Deno.test("generate-source-image rejects malformed body", async () => {
  const handler = createGenerateSourceImageHandler(baseDeps);
  const response = await handler(request({ project_id: "project-1", prompt: "   " }));
  assertEquals(response.status, 400);
});

Deno.test("generate-source-image hides project ownership", async () => {
  const handler = createGenerateSourceImageHandler(baseDeps);
  const response = await handler(request({ project_id: "other-project", prompt: "patient" }));
  assertEquals(response.status, 404);
});

Deno.test("generate-source-image maps provider failures without leaking secrets", async () => {
  const handler = createGenerateSourceImageHandler({
    ...baseDeps,
    createTextToImage: () =>
      Promise.reject(
        new ProviderError("provider_rejected", `provider said ${secret}`, 2010),
      ),
  });

  const response = await handler(request({ project_id: "project-1", prompt: "patient" }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(text.includes(secret), false);
});

Deno.test("generate-source-image creates an async job", async () => {
  let submittedPrompt = "";
  const handler = createGenerateSourceImageHandler({
    ...baseDeps,
    createTextToImage: (prompt: string) => {
      submittedPrompt = prompt;
      return Promise.resolve("task-source-1");
    },
  });

  const response = await handler(
    request({ project_id: "project-1", prompt: "old hospital patient" }),
  );
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body, { job_id: "job-source-1" });
  assertEquals(submittedPrompt, "old hospital patient");
});
