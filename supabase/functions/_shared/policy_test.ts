import {
  centavos,
  checkoutUrl,
  collected,
  equalSecret,
  quantity,
  validateSession,
} from "./policy.ts";
function assert(value: unknown, message = "Assertion failed") {
  if (!value) throw new Error(message);
}
function rejects(fn: () => unknown) {
  let failed = false;
  try {
    fn();
  } catch {
    failed = true;
  }
  assert(failed);
}
Deno.test("provider money keeps centavo precision and rejects unsafe amounts", () => {
  assert(centavos(1250.5) === 125050);
  assert(centavos(0.29) === 29);
  for (const amount of [NaN, Infinity, -1, 1.001, "100", 100000001]) {
    rejects(() => centavos(amount));
  }
});
Deno.test("session validation rejects wrong merchant, totals, currency and SAVE sessions", () => {
  const order = {
    id: "order1",
    total_centavos: 10050,
    payment_session_id: "ps-1",
  };
  const session = {
    business_id: "merchant",
    reference_id: "order1",
    session_type: "PAY",
    mode: "PAYMENT_LINK",
    currency: "PHP",
    country: "PH",
    amount: 100.5,
    payment_session_id: "ps-1",
    capture_method: "AUTOMATIC",
  };
  validateSession(session, order, "merchant");
  for (
    const patch of [
      { business_id: "other" },
      { amount: 101 },
      { session_type: "SAVE" },
      { currency: "IDR" },
      { capture_method: "MANUAL" },
      { payment_session_id: "ps-2" },
    ]
  ) rejects(() => validateSession({ ...session, ...patch }, order, "merchant"));
});
Deno.test("only collected matching automatic PHP payments are paid", () => {
  const payment = {
    capture_method: "AUTOMATIC",
    currency: "PHP",
    request_amount: 100.5,
    status: "SUCCEEDED",
  };
  assert(collected(payment, 10050));
  assert(!collected({ ...payment, status: "AUTHORIZED" }, 10050));
  assert(!collected({ ...payment, capture_method: "MANUAL" }, 10050));
  assert(!collected({ ...payment, request_amount: 100 }, 10050));
  assert(
    !collected({
      ...payment,
      captures: [{ status: "SUCCEEDED", capture_amount: 50 }],
    }, 10050),
  );
  assert(
    !collected({
      ...payment,
      status: "AUTHORIZED",
      captures: [{ status: "SUCCEEDED", capture_amount: 100.5 }],
    }, 10050),
  );
  assert(
    collected({ ...payment, captures: [{ capture_amount: 100.5 }] }, 10050),
  );
});
Deno.test("checkout cannot launch insecure or unrelated URLs", () => {
  assert(
    checkoutUrl("https://checkout.xendit.co/sessions/ps-1").startsWith(
      "https:",
    ),
  );
  assert(checkoutUrl("https://dev.xen.to/test").startsWith("https:"));
  for (
    const url of [
      "http://xen.to/a",
      "https://xendit.co.attacker.test/a",
      "https://user:pass@xen.to/a",
      "javascript:alert(1)",
    ]
  ) rejects(() => checkoutUrl(url));
  for (const value of [0, 21, 1.5, "1", null]) rejects(() => quantity(value));
});
Deno.test("webhook token comparison rejects absent and different secrets", async () => {
  assert(await equalSecret("correct", "correct"));
  assert(!await equalSecret("wrong", "correct"));
  assert(!await equalSecret("", ""));
});
