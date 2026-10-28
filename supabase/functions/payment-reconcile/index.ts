import {
  db,
  env,
  processEvent,
  reconcile,
  response,
  rpc,
  serve,
  xendit,
} from "../_shared/backend.ts";
import { centavos, equalSecret, HttpError } from "../_shared/policy.ts";
serve(async (req) => {
  if (
    !await equalSecret(
      req.headers.get("x-job-secret") ?? "",
      env("RECONCILIATION_JOB_SECRET"),
    )
  ) throw new HttpError(401, "Invalid scheduler credential.");
  let processed = 0, refreshed = 0, failures = 0;
  const { data: events, error: inboxError } = await db().from("payment_events")
    .select("*").is("processed_at", null).lte(
      "next_attempt_at",
      new Date().toISOString(),
    ).order("created_at").limit(10);
  if (inboxError) throw new Error("Could not read inbox");
  for (const event of events ?? []) {
    try {
      await processEvent(event);
      processed++;
    } catch {
      failures++;
      await db().from("payment_events").update({
        attempts: event.attempts + 1,
        next_attempt_at: new Date(
          Date.now() +
            Math.min(3600, 15 * 2 ** Math.min(event.attempts, 8)) * 1000,
        ).toISOString(),
        last_error: "Awaiting matching reference or verified provider result",
      }).eq("id", event.id);
    }
  }
  const { data: orders, error } = await db().from("orders").select("*").not(
    "payment_session_id",
    "is",
    null,
  ).in("status", [
    "creating",
    "creation_unknown",
    "payment_pending",
    "payment_review",
    "expired",
    "cancelled",
    "failed",
  ])
    .order("last_checked_at", { nullsFirst: true }).limit(10);
  if (error) throw new Error("Could not read unresolved orders");
  for (const order of orders ?? []) {
    try {
      await reconcile(order);
      refreshed++;
    } catch {
      failures++;
    }
  }
  const { data: interrupted } = await db().from("orders").select("id").eq(
    "status",
    "creating",
  ).is("payment_session_id", null)
    .lt("created_at", new Date(Date.now() - 60000).toISOString()).limit(20);
  for (const order of interrupted ?? []) {
    await rpc("payment_apply", {
      p_order: order.id,
      p_state: "creation_unknown",
      p_error: "Creation interrupted; investigate provider reference",
    });
  }
  const { data: refunds } = await db().from("refunds").select(
    "*,orders!inner(payment_request_id,total_centavos)",
  ).in("status", ["pending", "unknown"]);
  for (const refund of refunds ?? []) {
    if (!refund.provider_id) continue; // Lost creation response requires investigation; never issue a duplicate refund.
    try {
      const result = await xendit(
        `/refunds/${encodeURIComponent(refund.provider_id)}`,
      );
      if (
        result.payment_request_id !== refund.orders.payment_request_id ||
        result.currency !== "PHP" ||
        centavos(result.amount) !== Number(refund.orders.total_centavos)
      ) throw new Error("Refund mismatch");
      await rpc("payment_refund_apply", {
        p_refund: refund.id,
        p_status: result.status === "SUCCEEDED"
          ? "succeeded"
          : result.status === "FAILED"
          ? "failed"
          : "pending",
        p_provider: refund.provider_id,
      });
    } catch {
      failures++;
    }
  }
  return response({ processed, refreshed, failures });
});
