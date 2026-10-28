import {
  body,
  config,
  db,
  env,
  ProviderError,
  publicOrder,
  response,
  rpc,
  serve,
  user,
  xendit,
} from "../_shared/backend.ts";
import {
  checkoutUrl,
  HttpError,
  quantity,
  uuid,
  validateSession,
} from "../_shared/policy.ts";
serve(async (req) => {
  const account = await user(req), input = await body(req);
  config(); // Reject missing/live/public credentials before reserving stock.
  if (
    typeof input.expected_unit_price_centavos !== "number" ||
    !Number.isSafeInteger(input.expected_unit_price_centavos) ||
    input.expected_unit_price_centavos <= 0
  ) throw new HttpError(400, "Review a current quote first.");
  const result = await rpc(
    input.shipping_address ? "commerce_reserve_online" : "payment_reserve",
    {
      [input.shipping_address ? "p_actor" : "p_buyer"]: account.id,
      p_product: uuid(input.product_id),
      p_quantity: quantity(input.quantity),
      p_key: uuid(input.idempotency_key),
      p_expected_unit: input.expected_unit_price_centavos,
      ...(input.shipping_address ? { p_shipping: input.shipping_address } : {}),
    },
  );
  const order = result.order;
  if (order.payment_method === "cod") {
    throw new HttpError(
      409,
      "Checkout key was already used for cash on delivery.",
    );
  }
  if (!result.create) return response({ order: publicOrder(order) });
  let session;
  try {
    session = await xendit("/sessions", "POST", {
      reference_id: order.id,
      session_type: "PAY",
      mode: "PAYMENT_LINK",
      capture_method: "AUTOMATIC",
      allow_save_payment_method: "DISABLED",
      currency: "PHP",
      country: "PH",
      amount: Number(order.total_centavos) / 100,
      customer: {
        reference_id: order.id.replaceAll("-", ""),
        type: "INDIVIDUAL",
        email: account.email,
        individual_detail: { given_names: "COMPARTS", surname: "Customer" },
      },
      description:
        `COMPARTS TEST PAYMENT - no real charge - ${order.product_name}`.slice(
          0,
          200,
        ),
      expires_at: new Date(Date.now() + 30 * 60000).toISOString(),
      // No owned website is required: use Xendit's result screen; APK refreshes on resume.
    });
    validateSession(session, order, env("XENDIT_BUSINESS_ID"));
    const url = checkoutUrl(session.payment_link_url);
    await rpc("payment_attach", {
      p_order: order.id,
      p_session: session.payment_session_id,
      p_url: url,
      p_expires: session.expires_at,
    });
    return response({
      order: publicOrder({
        ...order,
        status: "payment_pending",
        payment_session_id: session.payment_session_id,
        payment_link_url: url,
        expires_at: session.expires_at,
      }),
    });
  } catch (error) {
    if (typeof session?.payment_session_id === "string") {
      // Keep a known provider ID even when later validation or persistence fails.
      // It can be investigated/reconciled without creating another session.
      const { error: saveError } = await db().from("orders")
        .update({ payment_session_id: session.payment_session_id }).eq(
          "id",
          order.id,
        ).is("payment_session_id", null);
      if (saveError) {
        console.error("Could not persist known provider reference");
      }
    }
    // A definitive 4xx rejection without any session response can release stock. Never retry ambiguous creates.
    const rejected = !session && error instanceof ProviderError &&
      error.status >= 400 && error.status < 500 &&
      ![408, 409, 429].includes(error.status);
    await rpc("payment_apply", {
      p_order: order.id,
      p_state: rejected ? "failed" : "creation_unknown",
      p_error: error instanceof ProviderError
        ? `Xendit ${error.status}: ${error.code}`
        : error instanceof HttpError
        ? error.message
        : `Uncertain creation response (${
          error instanceof Error ? error.name : "unknown"
        }); investigate before replacement`,
    });
    return response({
      order: publicOrder({
        ...order,
        status: rejected ? "failed" : "creation_unknown",
      }),
      error: rejected
        ? "Xendit rejected checkout. Check the test key permissions and account configuration."
        : "Checkout confirmation is delayed. Check Orders; do not create a replacement payment.",
    }, rejected ? 422 : 202);
  }
});
