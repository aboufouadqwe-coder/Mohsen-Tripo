import {
  executeHttp,
  jsonResponse,
  requireBearerToken,
} from "../_shared/http.ts";
import {
  authenticateSupabaseToken,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";
import { resolveTripoCredential } from "../_shared/tripo_credential.ts";

type BalanceDeps = {
  authenticate: (token: string) => Promise<string>;
  getBalance: (apiKey: string) => Promise<{ balance: number; frozen: number }>;
};

export function createTripoBalanceHandler(
  deps: BalanceDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      await deps.authenticate(token);
      const credential = await resolveTripoCredential(request);
      const balance = await deps.getBalance(credential.apiKey);
      return jsonResponse(balance);
    });
}

function createDefaultDeps(): BalanceDeps {
  return {
    authenticate: authenticateSupabaseToken,
    getBalance: (apiKey) => new TripoClient({ apiKey }).getBalance(),
  };
}

if (import.meta.main) {
  Deno.serve(createTripoBalanceHandler(createDefaultDeps()));
}
