import { assertEquals, assertRejects } from "@std/assert";
import {
  resolveTripoCredential,
  tripoCredentialFingerprint,
} from "../_shared/tripo_credential.ts";
import { HttpError } from "../_shared/http.ts";

Deno.test("request Tripo credential produces stable non-secret SHA-256 fingerprint", async () => {
  const key = "tsk_test_secret_12345678901234567890";
  const request = new Request("https://edge.test", {
    headers: { "x-tripo-api-key": key },
  });

  const credential = await resolveTripoCredential(request, {
    allowEnvironmentFallback: false,
  });

  assertEquals(credential.apiKey, key);
  assertEquals(
    credential.fingerprint,
    await tripoCredentialFingerprint(key),
  );
  assertEquals(credential.fingerprint.includes("test_secret"), false);
  assertEquals(credential.fingerprint.length, 64);
});

Deno.test("missing request Tripo credential fails closed without fallback", async () => {
  await assertRejects(
    () =>
      resolveTripoCredential(new Request("https://edge.test"), {
        allowEnvironmentFallback: false,
      }),
    HttpError,
    "Tripo API key is required",
  );
});
