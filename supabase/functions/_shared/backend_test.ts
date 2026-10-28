import { reconcile } from "./backend.ts";

Deno.test("COD orders never consult or accept online payment reconciliation", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw new Error("Unexpected network request");
  };
  try {
    const order = {
      id: "cod-order",
      payment_method: "cod",
      status: "cod_pending",
      payment_session_id: "misrouted-session",
    };
    const result = await reconcile(order, { status: "COMPLETED" });
    if (result !== order || result.status !== "cod_pending" || calls !== 0) {
      throw new Error("Online reconciliation changed COD");
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
async function scenario(paymentStatus: string, wrongBusiness = false) {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_SECRET_KEYS",
    "XENDIT_ENV",
    "XENDIT_SECRET_KEY",
    "XENDIT_BUSINESS_ID",
  ];
  const previous = names.map((name) => Deno.env.get(name));
  const values = [
    "https://fixture.supabase.co",
    "fixture-service-key",
    "{}",
    "test",
    "xnd_development_fixture",
    "merchant",
  ];
  names.forEach((name, i) => Deno.env.set(name, values[i]));
  const originalFetch = globalThis.fetch;
  const states: string[] = [], paths: string[] = [];
  const order: Record<string, any> = {
    id: "order1",
    total_centavos: 10050,
    status: "payment_pending",
    stock_reserved: true,
    payment_session_id: "ps-fixture",
    payment_link_url: "https://dev.xen.to/fixture",
  };
  globalThis.fetch = async (input, init) => {
    const url = new URL(
      typeof input === "string"
        ? input
        : input instanceof URL
        ? input.href
        : input.url,
    );
    paths.push(url.pathname);
    const json = (body: unknown) => Response.json(body);
    if (url.host === "api.xendit.co") {
      if (url.pathname === "/sessions/ps-fixture") {
        return json({
          payment_session_id: "ps-fixture",
          business_id: "merchant",
          reference_id: "order1",
          session_type: "PAY",
          mode: "PAYMENT_LINK",
          currency: "PHP",
          country: "PH",
          amount: 100.5,
          status: "COMPLETED",
          payment_request_id: "pr-fixture",
        });
      }
      if (url.pathname === "/v3/payment_requests/pr-fixture") {
        return json({
          business_id: "merchant",
          payment_request_id: "pr-fixture",
          currency: "PHP",
          request_amount: 100.5,
          status: "AUTHORIZED",
          latest_payment_id: "py-fixture",
        });
      }
      if (url.pathname === "/v3/payments/py-fixture") {
        return json({
          business_id: wrongBusiness ? "other" : "merchant",
          payment_id: "py-fixture",
          payment_request_id: "pr-fixture",
          currency: "PHP",
          request_amount: 100.5,
          capture_method: "AUTOMATIC",
          status: paymentStatus,
          captures: paymentStatus === "SUCCEEDED"
            ? [{ capture_amount: 100.5 }]
            : [],
        });
      }
    }
    if (url.host === "fixture.supabase.co") {
      if (url.pathname === "/rest/v1/payment_attempts") {
        return init?.method === "POST"
          ? new Response(null, { status: 201 })
          : json([]);
      }
      if (url.pathname === "/rest/v1/rpc/payment_apply") {
        const args = JSON.parse(String(init?.body));
        states.push(args.p_state);
        order.status = args.p_state;
        return new Response(null, { status: 204 });
      }
      if (url.pathname === "/rest/v1/orders") {
        return init?.method === "PATCH"
          ? new Response(null, { status: 204 })
          : json([order]);
      }
    }
    throw new Error(`Unexpected network access in test: ${url.pathname}`);
  };
  try {
    return { result: await reconcile({ ...order }), states, paths };
  } finally {
    globalThis.fetch = originalFetch;
    names.forEach((name, i) =>
      previous[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, previous[i]!)
    );
  }
}

Deno.test("reconciliation verifies the collected Payment, not only the authorized Payment Request", async () => {
  const result = await scenario("SUCCEEDED");
  assert(
    result.paths.includes("/v3/payments/py-fixture"),
    "Underlying Payment was not retrieved",
  );
  assert(
    result.result.status === "paid",
    "Canonical capture response did not confirm payment",
  );
  assert(
    result.states.length === 1 && result.states[0] === "paid",
    "Payment was applied more than once",
  );
});
Deno.test("a completed session with an authorized payment remains under review", async () => {
  const result = await scenario("AUTHORIZED");
  assert(
    result.result.status === "payment_review",
    "Authorization was treated as collected payment",
  );
  assert(!result.states.includes("paid"), "Uncollected order was marked paid");
});
Deno.test("a mismatched underlying payment cannot change an order", async () => {
  let rejected = false;
  try {
    await scenario("SUCCEEDED", true);
  } catch {
    rejected = true;
  }
  assert(rejected, "Wrong merchant payment was accepted");
});
