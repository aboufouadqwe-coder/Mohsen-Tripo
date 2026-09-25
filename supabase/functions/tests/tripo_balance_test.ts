import { assertEquals } from "@std/assert";
import { createTripoBalanceHandler } from "../tripo-balance/index.ts";

function request(authenticated = true): Request {
  const headers = new Headers();
  headers.set("x-tripo-api-key", "tsk_test_key_12345678901234567890");
  if (authenticated) headers.set("authorization", "Bearer user-token");
  return new Request("https://edge.test/tripo-balance", {
    method: "POST",
    headers,
  });
}

const baseDeps = {
  authenticate: (_token: string) => Promise.resolve("user-1"),
  getBalance: () => Promise.resolve({ balance: 1234.5, frozen: 25 }),
};

Deno.test("tripo-balance requires Authorization", async () => {
  const handler = createTripoBalanceHandler(baseDeps);
  const response = await handler(request(false));
  assertEquals(response.status, 401);
});

Deno.test("tripo-balance returns only numeric balance fields", async () => {
  const handler = createTripoBalanceHandler(baseDeps);
  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body, {
    balance: 1234.5,
    frozen: 25,
  });
});
