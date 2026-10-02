import { ProviderError } from "./provider_error.ts";

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

export function requireBearerToken(request: Request): string {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }

  const token = authorization.slice(7).trim();
  if (token.length === 0) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  return token;
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  let decoded: unknown;
  try {
    decoded = await request.json();
  } catch {
    throw new HttpError(400, "invalid_json", "Request body must be valid JSON.");
  }

  if (typeof decoded !== "object" || decoded === null || Array.isArray(decoded)) {
    throw new HttpError(400, "invalid_body", "Request body must be a JSON object.");
  }

  return decoded as Record<string, unknown>;
}

export function requiredString(
  body: Record<string, unknown>,
  key: string,
): string {
  const value = body[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, "invalid_body", `${key} must be a non-empty string.`);
  }
  return value.trim();
}

export function optionalString(
  body: Record<string, unknown>,
  key: string,
): string | undefined {
  const value = body[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new HttpError(400, "invalid_body", `${key} must be a string.`);
  }
  return value;
}

export async function executeHttp(
  work: () => Promise<Response>,
): Promise<Response> {
  try {
    return await work();
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(
        { error: { code: error.code, message: error.message } },
        error.status,
      );
    }

    if (error instanceof ProviderError) {
      return jsonResponse(
        {
          error: {
            code: "provider_error",
            message: "The generation provider could not complete the request.",
            provider_code: error.providerCode,
          },
        },
        502,
      );
    }

    return jsonResponse(
      {
        error: {
          code: "internal_error",
          message: "The request could not be completed.",
        },
      },
      500,
    );
  }
}
