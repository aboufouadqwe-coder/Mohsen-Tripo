import { ProviderError } from "./provider_error.ts";
import type {
  TripoCreateImageToImageRequest,
  TripoCreateImageToModelRequest,
  TripoCreateTextToImageRequest,
  TripoEnvelope,
  TripoTask,
  TripoTaskStatus,
} from "./tripo_types.ts";

const TRIPO_BASE_URL = "https://openapi.tripo3d.ai/v3";
const IMAGE_MODEL = "seedream_v5";
const MODEL_3D = "v3.1-20260211";
const TASK_STATUSES = new Set<TripoTaskStatus>([
  "queued",
  "running",
  "success",
  "failed",
  "cancelled",
  "unknown",
  "banned",
  "expired",
]);

type Fetcher = typeof fetch;

export type TripoClientOptions = {
  apiKey?: string;
  fetcher?: Fetcher;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asEnvelope(value: unknown): TripoEnvelope {
  if (!isRecord(value) || typeof value.code !== "number") {
    throw new ProviderError(
      "malformed_response",
      "Tripo returned a malformed response envelope.",
    );
  }

  return {
    code: value.code,
    data: value.data,
    message: typeof value.message === "string" ? value.message : undefined,
    suggestion: typeof value.suggestion === "string" ? value.suggestion : undefined,
  };
}

export class TripoClient {
  readonly #apiKey: string;
  readonly #fetcher: Fetcher;

  constructor(options: TripoClientOptions = {}) {
    this.#apiKey = options.apiKey ?? Deno.env.get("TRIPO_API_KEY") ?? "";
    this.#fetcher = options.fetcher ?? fetch;
  }

  async createTextToImage(request: TripoCreateTextToImageRequest): Promise<string> {
    return await this.#createTask("/generation/text-to-image", {
      prompt: request.prompt,
      model: IMAGE_MODEL,
      size: "2K",
      output_format: "png",
      watermark: false,
    });
  }

  async uploadImageFromUrl(sourceUrl: string): Promise<string> {
    let source: Response;
    try {
      source = await this.#fetcher(sourceUrl);
    } catch (cause) {
      throw new ProviderError(
        "input_fetch_failed",
        "Unable to read the private reference image before upload.",
        undefined,
        undefined,
        { cause },
      );
    }

    if (!source.ok) {
      throw new ProviderError(
        "input_fetch_failed",
        `Private reference image fetch failed with status ${source.status}.`,
      );
    }

    const mimeType = (source.headers.get("content-type") ?? "")
      .split(";")[0]
      .trim()
      .toLowerCase();
    const extension = mimeType === "image/jpeg"
      ? "jpg"
      : mimeType === "image/png"
      ? "png"
      : null;

    if (extension === null) {
      throw new ProviderError(
        "unsupported_input",
        "Reference image must be PNG or JPEG for Tripo file upload.",
      );
    }

    const bytes = await source.arrayBuffer();
    if (bytes.byteLength === 0) {
      throw new ProviderError(
        "empty_input",
        "Reference image was empty.",
      );
    }

    const form = new FormData();
    form.append(
      "file",
      new Blob([bytes], { type: mimeType }),
      `reference.${extension}`,
    );

    const data = await this.#requestData("/files", {
      method: "POST",
      body: form,
    });

    if (
      !isRecord(data) ||
      typeof data.file_token !== "string" ||
      data.file_token.trim().length === 0
    ) {
      throw new ProviderError(
        "malformed_response",
        "Tripo file upload response is missing file_token.",
      );
    }

    return data.file_token;
  }

  async createImageToImage(request: TripoCreateImageToImageRequest): Promise<string> {
    return await this.#createTask("/generation/image-to-image", {
      input: request.input,
      prompt: request.prompt,
      model: IMAGE_MODEL,
      size: "2K",
      output_format: "png",
    });
  }

  async createImageToModel(request: TripoCreateImageToModelRequest): Promise<string> {
    const body: Record<string, unknown> = {
      input: request.input,
      model: request.model ?? MODEL_3D,
      texture: request.texture ?? true,
      pbr: request.pbr ?? true,
      enable_image_autofix: request.enableImageAutofix ?? false,
    };

    if (request.faceLimit !== undefined) {
      body.face_limit = request.faceLimit;
    }
    if (request.quad !== undefined) {
      body.quad = request.quad;
    }
    if (request.geometryQuality !== undefined) {
      body.geometry_quality = request.geometryQuality;
    }

    return await this.#createTask("/generation/image-to-model", body);
  }

  async getBalance(): Promise<{ balance: number; frozen: number }> {
    const data = await this.#requestData("/account/balance", {
      method: "GET",
    });

    if (
      !isRecord(data) ||
      typeof data.balance !== "number" ||
      !Number.isFinite(data.balance) ||
      typeof data.frozen !== "number" ||
      !Number.isFinite(data.frozen)
    ) {
      throw new ProviderError(
        "malformed_response",
        "Tripo balance response is malformed.",
      );
    }

    return {
      balance: data.balance,
      frozen: data.frozen,
    };
  }

  async getTask(taskId: string): Promise<TripoTask> {
    const data = await this.#requestData(
      `/tasks/${encodeURIComponent(taskId)}`,
      { method: "GET" },
    );

    if (!isRecord(data)) {
      throw new ProviderError(
        "malformed_response",
        "Tripo task response is missing task data.",
      );
    }

    const status = data.status;
    if (typeof status !== "string") {
      throw new ProviderError(
        "malformed_response",
        "Tripo task response is missing status.",
      );
    }
    if (!TASK_STATUSES.has(status as TripoTaskStatus)) {
      throw new ProviderError(
        "unknown_status",
        `Tripo returned unknown task status: ${status}`,
      );
    }

    if (
      typeof data.task_id !== "string" ||
      data.task_id.trim().length === 0 ||
      typeof data.type !== "string" ||
      data.type.trim().length === 0
    ) {
      throw new ProviderError(
        "malformed_response",
        "Tripo task response has invalid required fields.",
      );
    }

    let progress = status === "success" ? 100 : 0;
    if (data.progress !== undefined && data.progress !== null) {
      if (
        typeof data.progress !== "number" ||
        !Number.isFinite(data.progress) ||
        data.progress < 0 ||
        data.progress > 100
      ) {
        throw new ProviderError(
          "malformed_response",
          "Tripo task response has invalid progress.",
        );
      }
      progress = data.progress;
    }

    const output = isRecord(data.output) ? data.output : undefined;

    return {
      taskId: data.task_id,
      type: data.type,
      status: status as TripoTaskStatus,
      progress,
      output,
      errorCode: typeof data.error_code === "number" ? data.error_code : undefined,
      errorMessage: typeof data.error_message === "string" ? data.error_message : undefined,
    };
  }

  async #createTask(path: string, body: Record<string, unknown>): Promise<string> {
    const data = await this.#requestData(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!isRecord(data) || typeof data.task_id !== "string" || data.task_id.trim().length === 0) {
      throw new ProviderError(
        "malformed_response",
        "Tripo create-task response is missing task_id.",
      );
    }

    return data.task_id;
  }

  async #requestData(path: string, init: RequestInit): Promise<unknown> {
    this.#requireApiKey();

    let response: Response;
    try {
      response = await this.#fetcher(`${TRIPO_BASE_URL}${path}`, {
        ...init,
        headers: {
          authorization: `Bearer ${this.#apiKey}`,
          ...init.headers,
        },
      });
    } catch (cause) {
      throw new ProviderError(
        "network_error",
        "Unable to reach the Tripo API.",
        undefined,
        undefined,
        { cause },
      );
    }

    if (!response.ok) {
      throw new ProviderError(
        "http_error",
        `Tripo HTTP request failed with status ${response.status}.`,
      );
    }

    let decoded: unknown;
    try {
      decoded = await response.json();
    } catch (cause) {
      throw new ProviderError(
        "malformed_response",
        "Tripo returned non-JSON response content.",
        undefined,
        undefined,
        { cause },
      );
    }

    const envelope = asEnvelope(decoded);
    if (envelope.code !== 0) {
      throw new ProviderError(
        "provider_rejected",
        envelope.message ?? "Tripo rejected the request.",
        envelope.code,
        envelope.suggestion,
      );
    }

    return envelope.data;
  }

  #requireApiKey(): void {
    if (this.#apiKey.trim().length === 0) {
      throw new ProviderError(
        "missing_api_key",
        "TRIPO_API_KEY is required on the server.",
      );
    }
  }
}
