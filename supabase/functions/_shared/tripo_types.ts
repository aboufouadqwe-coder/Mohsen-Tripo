export type TripoTaskStatus =
  | "queued"
  | "running"
  | "success"
  | "failed"
  | "cancelled";

export type TripoCreateTextToImageRequest = {
  prompt: string;
};

export type TripoCreateImageToImageRequest = {
  input: string;
  prompt: string;
};

export type TripoCreateImageToModelRequest = {
  input: string;
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
