import { HttpError } from "./http.ts";

export const TRIPO_API_KEY_HEADER = "x-tripo-api-key";

export type TripoRequestCredential = {
  apiKey: string;
  fingerprint: string;
};

export async function tripoCredentialFingerprint(
  apiKey: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(apiKey.trim()),
  );
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export async function resolveTripoCredential(
  request: Request,
  options: { allowEnvironmentFallback?: boolean } = {},
): Promise<TripoRequestCredential> {
  const allowEnvironmentFallback = options.allowEnvironmentFallback ?? true;
  const requestKey = request.headers.get(TRIPO_API_KEY_HEADER)?.trim() ?? "";
  const environmentKey = allowEnvironmentFallback
    ? Deno.env.get("TRIPO_API_KEY")?.trim() ?? ""
    : "";
  const apiKey = requestKey.length > 0 ? requestKey : environmentKey;

  if (apiKey.length === 0) {
    throw new HttpError(
      400,
      "missing_provider_credential",
      "Tripo API key is required.",
    );
  }

  return {
    apiKey,
    fingerprint: await tripoCredentialFingerprint(apiKey),
  };
}
