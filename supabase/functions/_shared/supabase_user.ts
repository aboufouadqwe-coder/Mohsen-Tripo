import { HttpError } from "./http.ts";

type JsonRecord = Record<string, unknown>;

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (value.length === 0) {
    throw new Error(`${name} is required in the Edge Function environment.`);
  }
  return value;
}

function supabaseUrl(): string {
  return requireEnv("SUPABASE_URL").replace(/\/$/, "");
}

function publicKey(): string {
  return (
    Deno.env.get("SUPABASE_ANON_KEY")?.trim() ||
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
    requireEnv("SUPABASE_ANON_KEY")
  );
}

function serviceRoleKey(): string {
  return requireEnv("SUPABASE_SERVICE_ROLE_KEY");
}

function encodedObjectPath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

function adminHeaders(extra: HeadersInit = {}): Headers {
  const key = serviceRoleKey();
  const headers = new Headers(extra);
  headers.set("apikey", key);
  headers.set("authorization", `Bearer ${key}`);
  return headers;
}

async function parseJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new Error("Supabase returned malformed JSON.");
  }
}

export async function authenticateSupabaseToken(token: string): Promise<string> {
  const response = await fetch(`${supabaseUrl()}/auth/v1/user`, {
    headers: {
      apikey: publicKey(),
      authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }

  const decoded = await parseJson(response);
  if (
    typeof decoded !== "object" ||
    decoded === null ||
    Array.isArray(decoded) ||
    typeof (decoded as JsonRecord).id !== "string"
  ) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }

  return (decoded as JsonRecord).id as string;
}

export async function adminSelectOne<T>(
  table: string,
  query: Record<string, string>,
): Promise<T | null> {
  const params = new URLSearchParams(query);
  const response = await fetch(
    `${supabaseUrl()}/rest/v1/${encodeURIComponent(table)}?${params}`,
    { headers: adminHeaders() },
  );

  if (!response.ok) {
    throw new Error(`Supabase select failed with status ${response.status}.`);
  }

  const decoded = await parseJson(response);
  if (!Array.isArray(decoded)) {
    throw new Error("Supabase select returned an unexpected payload.");
  }

  return decoded.length === 0 ? null : decoded[0] as T;
}

export async function adminInsertOne<T>(
  table: string,
  body: Record<string, unknown>,
  select = "id",
): Promise<T> {
  const params = new URLSearchParams({ select });
  const response = await fetch(
    `${supabaseUrl()}/rest/v1/${encodeURIComponent(table)}?${params}`,
    {
      method: "POST",
      headers: adminHeaders({
        "content-type": "application/json",
        prefer: "return=representation",
      }),
      body: JSON.stringify(body),
    },
  );

  if (!response.ok) {
    throw new Error(`Supabase insert failed with status ${response.status}.`);
  }

  const decoded = await parseJson(response);
  if (!Array.isArray(decoded) || decoded.length !== 1) {
    throw new Error("Supabase insert returned an unexpected payload.");
  }

  return decoded[0] as T;
}

export async function adminUpdate(
  table: string,
  filters: Record<string, string>,
  body: Record<string, unknown>,
): Promise<void> {
  const params = new URLSearchParams(filters);
  const response = await fetch(
    `${supabaseUrl()}/rest/v1/${encodeURIComponent(table)}?${params}`,
    {
      method: "PATCH",
      headers: adminHeaders({
        "content-type": "application/json",
        prefer: "return=minimal",
      }),
      body: JSON.stringify(body),
    },
  );

  if (!response.ok) {
    throw new Error(`Supabase update failed with status ${response.status}.`);
  }
}

export async function createSignedObjectUrl(
  bucket: string,
  path: string,
  expiresIn = 120,
): Promise<string> {
  const response = await fetch(
    `${supabaseUrl()}/storage/v1/object/sign/${encodeURIComponent(bucket)}/${encodedObjectPath(path)}`,
    {
      method: "POST",
      headers: adminHeaders({ "content-type": "application/json" }),
      body: JSON.stringify({ expiresIn }),
    },
  );

  if (!response.ok) {
    throw new Error(`Supabase signed URL creation failed with status ${response.status}.`);
  }

  const decoded = await parseJson(response);
  if (
    typeof decoded !== "object" ||
    decoded === null ||
    Array.isArray(decoded) ||
    typeof (decoded as JsonRecord).signedURL !== "string"
  ) {
    throw new Error("Supabase signed URL response was malformed.");
  }

  const signedUrl = (decoded as JsonRecord).signedURL as string;
  return signedUrl.startsWith("http")
    ? signedUrl
    : `${supabaseUrl()}/storage/v1${signedUrl}`;
}

export async function uploadObject(
  bucket: string,
  path: string,
  bytes: Uint8Array,
  mimeType: string,
): Promise<void> {
  const response = await fetch(
    `${supabaseUrl()}/storage/v1/object/${encodeURIComponent(bucket)}/${encodedObjectPath(path)}`,
    {
      method: "POST",
      headers: adminHeaders({
        "content-type": mimeType,
        "x-upsert": "false",
      }),
      body: bytes,
    },
  );

  if (!response.ok) {
    throw new Error(`Supabase storage upload failed with status ${response.status}.`);
  }
}
