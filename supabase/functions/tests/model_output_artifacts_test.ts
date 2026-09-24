import { assertEquals } from "@std/assert";
import { providerArtifactUrls } from "../refresh-generation-job/index.ts";

Deno.test("model output exposes persisted GLB and preview artifacts", () => {
  assertEquals(
    providerArtifactUrls("image_to_model", {
      model_url: "https://provider.test/model.glb",
      rendered_image_url: "https://provider.test/preview.png",
    }),
    [
      {
        role: "primary",
        bucket: "generated-models",
        url: "https://provider.test/model.glb",
      },
      {
        role: "preview",
        bucket: "generated-images",
        url: "https://provider.test/preview.png",
      },
    ],
  );
});

Deno.test("image output accepts Tripo v3 generated_image_url", () => {
  assertEquals(
    providerArtifactUrls("text_to_image", {
      generated_image_url: "https://provider.test/generated.png",
    }),
    [
      {
        role: "primary",
        bucket: "generated-images",
        url: "https://provider.test/generated.png",
      },
    ],
  );
});
