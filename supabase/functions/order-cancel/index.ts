import {
  body,
  orderFor,
  publicOrder,
  reconcile,
  response,
  rpc,
  serve,
  user,
  xendit,
} from "../_shared/backend.ts";
import { HttpError, uuid } from "../_shared/policy.ts";
serve(async (req) => {
  const account = await user(req), input = await body(req);
  const order = await orderFor(uuid(input.order_id), account.id);
  if (order.payment_method === "cod") {
    return response({
      order: publicOrder(
        await rpc("commerce_cancel_cod", {
          p_actor: account.id,
          p_order: order.id,
        }),
      ),
    });
  }
  if (order.status === "cancelled" || order.status === "expired") {
    return response({ order: publicOrder(order) });
  }
  if (order.status !== "payment_pending" || !order.payment_session_id) {
    throw new HttpError(
      409,
      "This order cannot be cancelled. Paid orders need an administrator refund.",
    );
  }
  await xendit(
    `/sessions/${encodeURIComponent(order.payment_session_id)}/cancel`,
    "POST",
  );
  return response({ order: publicOrder(await reconcile(order)) });
});
