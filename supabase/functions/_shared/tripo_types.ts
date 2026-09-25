export type TripoTaskStatus =
  | "queued"
  | "running"
  | "success"
  | "failed"
  | "cancelled"
  | "unknown"
  | "banned"
  | "expired";

export type TripoCreateTextToImageRequest = {
  prompt: string;
};

export type TripoCreateImageToImageRequest = {
  input: string;
  prompt: string;
};

export type TripoCreateImageToModelRequest = {
  input: string;
  model?: string;
  faceLimit?: number;
  quad?: boolean;
  geometryQuality?: "standard" | "detailed";
  texture?: boolean;
  pbr?: boolean;
  enableImageAutofix?: boolean;
};

export type TripoTask = {
  taskId: string;
  type: string;
  status: TripoTaskStatus;
  progress: number;
  output?: Record<string, unknown>;
  errorCode?: number;
  errorMessage?: string;
};

export type TripoEnvelope = {
  code: number;
  data?: unknown;
  message?: string;
  suggestion?: string;
};
