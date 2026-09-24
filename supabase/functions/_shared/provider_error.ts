export type ProviderErrorCode =
  | "missing_api_key"
  | "http_error"
  | "network_error"
  | "provider_rejected"
  | "malformed_response"
  | "unknown_status";

export class ProviderError extends Error {
  constructor(
    public readonly code: ProviderErrorCode,
    message: string,
    public readonly providerCode?: number,
    public readonly suggestion?: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "ProviderError";
  }
}
