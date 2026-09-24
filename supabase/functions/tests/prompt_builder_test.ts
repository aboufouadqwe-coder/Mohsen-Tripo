import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import { buildAssetPrompt } from "../_shared/prompt_builder.ts";

Deno.test("buildAssetPrompt keeps deterministic semantic order", () => {
  const prompt = buildAssetPrompt({
    projectIdentity: "Young male patient with old brown hospital clothes.",
    partLabel: "Injured Left Arm",
    partPrompt: "Generate the injured arm clearly and completely.",
    customInstructions: "Keep the exact bandage visual language.",
  });

  const identityIndex = prompt.indexOf("Identity:");
  const assetIndex = prompt.indexOf("Requested asset:");
  const instructionIndex = prompt.indexOf("Instruction:");
  const customIndex = prompt.indexOf("Additional instruction:");
  const preserveIndex = prompt.indexOf("Preserve identity");

  assertEquals(identityIndex >= 0, true);
  assertEquals(assetIndex > identityIndex, true);
  assertEquals(instructionIndex > assetIndex, true);
  assertEquals(customIndex > instructionIndex, true);
  assertEquals(preserveIndex > customIndex, true);
  assertStringIncludes(prompt, "same character");
});

Deno.test("custom instructions are clamped to 1000 characters", () => {
  const longCustom = "x".repeat(1200);
  const prompt = buildAssetPrompt({
    projectIdentity: "Patient",
    partLabel: "Head",
    partPrompt: "Generate the complete head.",
    customInstructions: longCustom,
  });

  const marker = "Additional instruction: ";
  const start = prompt.indexOf(marker) + marker.length;
  const end = prompt.indexOf("\n", start);
  assertEquals(prompt.slice(start, end).length, 1000);
});

Deno.test("blank part label is rejected", () => {
  assertThrows(
    () =>
      buildAssetPrompt({
        projectIdentity: "Patient",
        partLabel: "   ",
        partPrompt: "Generate the head.",
      }),
    Error,
  );
});

Deno.test("control-only custom instructions are rejected", () => {
  assertThrows(
    () =>
      buildAssetPrompt({
        projectIdentity: "Patient",
        partLabel: "Head",
        partPrompt: "Generate the head.",
        customInstructions: "\u0000\u0001\u0002",
      }),
    Error,
  );
});
