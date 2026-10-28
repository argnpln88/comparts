import {
  admin,
  body,
  config,
  db,
  env,
  orderFor,
  ProviderError,
  publicOrder,
  reconcile,
  response,
  rpc,
  serve,
  xendit,
} from "../_shared/backend.ts";
serve(async (req) => {
  await admin(req);
  const input = await body(req);
  if (
    input.action === "inspect-session" &&
    typeof input.session_id === "string" &&
    /^ps-[a-f0-9]{24}$/.test(input.session_id)
  ) {
    const session = await xendit(`/sessions/${input.session_id}`);
    return response({
      payment_session_id: session.payment_session_id,
      reference_id: session.reference_id,
      business_matches: session.business_id === env("XENDIT_BUSINESS_ID"),
      payment_link_url: session.payment_link_url,
      status: session.status,
      payment_request_id: session.payment_request_id,
      latest_payment_request_id: session.latest_payment_request_id,
    });
  }
  if (
    input.action === "reconcile-order" && typeof input.order_id === "string"
  ) {
    return response({
      order: publicOrder(await reconcile(await orderFor(input.order_id))),
    });
  }
  if (input.action === "probe") {
    config();
    try {
      await xendit("/sessions/ps-000000000000000000000000");
      return response({ reachable: true });
    } catch (error) {
      if (error instanceof ProviderError) {
        return response({
          reachable: true,
          provider_http: error.status,
          provider_code: error.code,
        });
      }
      return response({
        reachable: false,
        error_type: error instanceof Error ? error.name : "unknown",
      });
    }
  }
  if (input.action === "configure-schedule") {
    await rpc("payment_schedule", {
      p_url: `${env("SUPABASE_URL")}/functions/v1/payment-reconcile`,
      p_secret: env("RECONCILIATION_JOB_SECRET"),
    });
    return response({ scheduled: true, interval_minutes: 2 });
  }
  if (input.action !== "health") {
    return response({ error: "Unknown action." }, 400);
  }
  let configError = null;
  try {
    config();
  } catch (error) {
    configError = error instanceof Error
      ? error.message
      : "Invalid configuration";
  }
  const { count, error } = await db().from("orders").select("id", {
    count: "exact",
    head: true,
  });
  return response({
    environment: env("XENDIT_ENV"),
    test_secret_configured: env("XENDIT_SECRET_KEY").startsWith(
      "xnd_development_",
    ),
    webhook_token_configured: !!env("XENDIT_CALLBACK_TOKEN"),
    business_id_configured: /^[a-f0-9]{24}$/i.test(env("XENDIT_BUSINESS_ID")),
    scheduler_secret_configured: env("RECONCILIATION_JOB_SECRET").length >= 32,
    database_ready: !error,
    order_count: count,
    config_error: configError,
    webhook_url: `${env("SUPABASE_URL")}/functions/v1/xendit-webhook`,
  });
});
