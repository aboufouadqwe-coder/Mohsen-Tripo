import {
  executeHttp,
  jsonResponse,
  requireBearerToken,
} from "../_shared/http.ts";
import {
  authenticateSupabaseToken,
} from "../_shared/supabase_user.ts";
import { TripoClient } from "../_shared/tripo_client.ts";

type BalanceDeps = {
  authenticate: (token: string) => Promise<string>;
  getBalance: () => Promise<{ balance: number; frozen: number }>;
};

export function createTripoBalanceHandler(
  deps: BalanceDeps,
): (request: Request) => Promise<Response> {
  return (request) =>
    executeHttp(async () => {
      const token = requireBearerToken(request);
      await deps.authenticate(token);
      const balance = await deps.getBalance();
      return jsonResponse(balance);
    });
}

function createDefaultDeps(): BalanceDeps {
  const tripo = new TripoClient();
  return {
    authenticate: authenticateSupabaseToken,
    getBalance: () => tripo.getBalance(),
  };
}

if (import.meta.main) {
  Deno.serve(createTripoBalanceHandler(createDefaultDeps()));
}
