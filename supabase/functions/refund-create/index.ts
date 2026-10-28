import {
  admin,
  body,
  db,
  orderFor,
  ProviderError,
  response,
  rpc,
  serve,
  xendit,
} from "../_shared/backend.ts";
import { centavos, HttpError, uuid } from "../_shared/policy.ts";
serve(async (req) => {
  await admin(req);
  const input = await body(req), order = await orderFor(uuid(input.order_id));
  const result = await rpc("payment_refund_begin", { p_order: order.id });
  if (!result.create) return response(result.refund);
  let refund;
  try {
    refund = await xendit("/refunds", "POST", {
      reference_id: result.refund.id,
      payment_request_id: order.payment_request_id,
      currency: "PHP",
      amount: Number(order.total_centavos) / 100,
      reason: "REQUESTED_BY_CUSTOMER",
    });
    if (
      typeof refund.id !== "string" ||
      refund.payment_request_id !== order.payment_request_id ||
      refund.currency !== "PHP" ||
      centavos(refund.amount) !== Number(order.total_centavos)
    ) {
      throw new HttpError(409, "Refund response needs review.");
    }
    await rpc("payment_refund_apply", {
      p_refund: result.refund.id,
      p_status: refund.status === "SUCCEEDED"
        ? "succeeded"
        : refund.status === "FAILED"
        ? "failed"
        : "pending",
      p_provider: refund.id,
    });
    return response({ id: result.refund.id, status: refund.status });
  } catch (error) {
    if (typeof refund?.id === "string") {
      await db().from("refunds").update({ provider_id: refund.id }).eq(
        "id",
        result.refund.id,
      );
    }
    const rejected = error instanceof ProviderError && error.status >= 400 &&
      error.status < 500 && ![408, 409, 429].includes(error.status);
    await rpc("payment_refund_apply", {
      p_refund: result.refund.id,
      p_status: rejected ? "failed" : "unknown",
    });
    return response({
      error:
        "Refund needs administrator review. Do not submit a replacement refund.",
    }, 202);
  }
});
