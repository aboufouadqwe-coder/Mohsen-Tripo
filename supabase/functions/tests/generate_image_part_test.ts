import { assertEquals, assertStringIncludes } from "@std/assert";
import { ProviderError } from "../_shared/provider_error.ts";
import { createGenerateImagePartHandler } from "../generate-image-part/index.ts";

const secret = "TRIPO_SUPER_SECRET";

function request(body: unknown, authenticated = true): Request {
  const headers = new Headers({ "content-type": "application/json" });\n  headers.set("x-tripo-api-key", "tsk_test_key_12345678901234567890");
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/generate-image-part", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
  findOwnedProject: (_userId: string, projectId: string) =>
    Promise.resolve(
      projectId === "project-1"
        ? {
          id: projectId,
          referenceImagePath: "user-1/project-1/reference.png",
          templateId: "template-1",
          identityPrompt: "Bandaged hospital patient",
        }
        : null,
    ),
  findTemplatePart: (_templateId: string, partKey: string) =>
    Promise.resolve(
      partKey === "head"
        ? {
          key: "head",
          label: "Head",
          promptFragment: "Generate the complete head.",
        }
        : null,
    ),
  signReferenceUrl: (_path: string) => Promise.resolve("https://signed.test/reference.png"),
  uploadReferenceToProvider: (_apiKey: string, _url: string) => Promise.resolve("file_reference_1"),
  createImageToImage: (_apiKey: string, _input: { input: string; prompt: string }) => Promise.resolve("task-part-1"),
  insertJob: (_input: unknown) => Promise.resolve("job-part-1"),
};

Deno.test("generate-image-part requires Authorization", async () => {
  const handler = createGenerateImagePartHandler(baseDeps);
  const response = await handler(request({ project_id: "project-1", part_key: "head" }, false));
  assertEquals(response.status, 401);
});

Deno.test("generate-image-part rejects malformed body", async () => {
  const handler = createGenerateImagePartHandler(baseDeps);
  const response = await handler(request({ project_id: "", part_key: "head" }));
  assertEquals(response.status, 400);
});

Deno.test("generate-image-part hides project ownership", async () => {
  const handler = createGenerateImagePartHandler(baseDeps);
  const response = await handler(request({ project_id: "other-project", part_key: "head" }));
  assertEquals(response.status, 404);
});

Deno.test("generate-image-part maps provider failures without leaking secrets", async () => {
  const handler = createGenerateImagePartHandler({
    ...baseDeps,
    createImageToImage: () =>
      Promise.reject(
        new ProviderError("provider_rejected", `provider said ${secret}`, 2010),
      ),
  });

  const response = await handler(request({ project_id: "project-1", part_key: "head" }));
  const text = await response.text();

  assertEquals(response.status, 502);
  assertEquals(text.includes(secret), false);
});

Deno.test("generate-image-part uploads private reference and creates job", async () => {
  let uploadedUrl = "";
  let providerInput = "";
  let submittedPrompt = "";
  const handler = createGenerateImagePartHandler({
    ...baseDeps,
    uploadReferenceToProvider: (_apiKey: string, url: string) => {
      uploadedUrl = url;
      return Promise.resolve("file_reference_1");
    },
    createImageToImage: (_apiKey: string, input: { input: string; prompt: string }) => {
      providerInput = input.input;
      submittedPrompt = input.prompt;
      return Promise.resolve("task-part-1");
    },
  });

  const response = await handler(request({
    project_id: "project-1",
    part_key: "head",
    custom_instructions: "Keep exact bandage pattern",
  }));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body, { job_id: "job-part-1" });
  assertEquals(uploadedUrl, "https://signed.test/reference.png");
  assertEquals(providerInput, "file_reference_1");
  assertStringIncludes(submittedPrompt, "Bandaged hospital patient");
  assertStringIncludes(submittedPrompt, "Head");
  assertStringIncludes(submittedPrompt, "Keep exact bandage pattern");
});

Deno.test("generate-image-part accepts exact client-authored prompt for custom part", async () => {
  let lookupCalled = false;
  let submittedPrompt = "";
  const handler = createGenerateImagePartHandler({
    ...baseDeps,
    findTemplatePart: () => {
      lookupCalled = true;
      return Promise.resolve(null);
    },
    createImageToImage: (_apiKey: string, input: { input: string; prompt: string }) => {
      submittedPrompt = input.prompt;
      return Promise.resolve("task-custom-1");
    },
  });

  const response = await handler(request({
    project_id: "project-1",
    part_key: "custom-uuid-1",
    part_label: "Arm with shoulder",
    part_prompt: "A complete arm with shoulder at the same angle as the original image.",
  }));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body, { job_id: "job-part-1" });
  assertEquals(lookupCalled, false);
  assertEquals(
    submittedPrompt,
    "A complete arm with shoulder at the same angle as the original image.",
  );
});

Deno.test("generate-image-part rejects incomplete direct prompt pair", async () => {
  const handler = createGenerateImagePartHandler(baseDeps);
  const response = await handler(request({
    project_id: "project-1",
    part_key: "custom-uuid-1",
    part_label: "Arm",
  }));

  assertEquals(response.status, 400);
});


Deno.test("generate-image-part accepts owned cropped reference path", async () => {
  let signedPath = "";
  const handler = createGenerateImagePartHandler({
    ...baseDeps,
    signReferenceUrl: (path: string) => {
      signedPath = path;
      return Promise.resolve("https://signed.test/crop.png");
    },
  });

  const response = await handler(request({
    project_id: "project-1",
    part_key: "head",
    part_label: "Head Clean",
    part_prompt: "Generate only a clean bald head.",
    reference_storage_path: "user-1/project-1/parts/head.png",
  }));

  assertEquals(response.status, 202);
  assertEquals(signedPath, "user-1/project-1/parts/head.png");
});

Deno.test("generate-image-part rejects crop path outside owned project", async () => {
  const handler = createGenerateImagePartHandler(baseDeps);
  const response = await handler(request({
    project_id: "project-1",
    part_key: "head",
    part_label: "Head Clean",
    part_prompt: "Generate only a clean bald head.",
    reference_storage_path: "user-2/project-1/parts/head.png",
  }));

  assertEquals(response.status, 400);
});
