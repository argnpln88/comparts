import { body, db, env, response, serve } from "../_shared/backend.ts";
import { equalSecret, HttpError } from "../_shared/policy.ts";
serve(async (req) => {
  if (
    !await equalSecret(
      req.headers.get("x-callback-token") ?? "",
      env("XENDIT_CALLBACK_TOKEN"),
    )
  ) throw new HttpError(401, "Invalid webhook token.");
  const payload = await body(req);
  // Xendit's dashboard uses a static sample merchant for Test & Save.
  // Authenticated misrouted/sample events are quarantined and never processed.
  const quarantined = payload.business_id !== env("XENDIT_BUSINESS_ID");
  const supported = [
    "payment_session.completed",
    "payment_session.expired",
    "payment.capture",
    "payment.failure",
    "payment.authorization",
    "payment_request.expiry",
    "refund.succeeded",
    "refund.failed",
  ];
  if (!supported.includes(String(payload.event))) {
    return response({ received: true, ignored: true });
  }
  const data = payload.data as Record<string, unknown>;
  if (!data || typeof data !== "object") {
    throw new HttpError(400, "Missing event data.");
  }
  const resource = data.payment_session_id ?? data.payment_id ??
    data.payment_request_id ?? data.id;
  if (typeof resource !== "string") {
    throw new HttpError(400, "Missing event resource.");
  }
  const key = `${String(payload.business_id)}:${payload.event}:${resource}:${
    data.status ?? ""
  }`;
  const { error } = await db().from("payment_events").upsert({
    dedupe_key: key,
    event_type: payload.event,
    payload,
    session_id: data.payment_session_id ??
      (String(payload.event).startsWith("payment_session.") &&
          typeof data.id === "string" && data.id.startsWith("ps-")
        ? data.id
        : null),
    processed_at: quarantined ? new Date().toISOString() : null,
    last_error: quarantined
      ? "Merchant mismatch; quarantined without changing orders"
      : null,
  }, { onConflict: "dedupe_key", ignoreDuplicates: true });
  if (error) throw new Error("Could not persist webhook");
  // Durable inbox is processed by protected Cron. No untracked promise after acknowledgement.
  return response({ received: true, quarantined });
});
