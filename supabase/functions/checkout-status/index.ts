import {
  body,
  orderFor,
  publicOrder,
  reconcile,
  response,
  serve,
  user,
} from "../_shared/backend.ts";
import { uuid } from "../_shared/policy.ts";
serve(async (req) => {
  const account = await user(req), input = await body(req);
  let order = await orderFor(uuid(input.order_id), account.id);
  let delayed = false;
  if (
    order.payment_session_id &&
    (!order.last_checked_at ||
      Date.now() - Date.parse(order.last_checked_at) > 10000)
  ) {
    try {
      order = await reconcile(order);
    } catch {
      delayed = true;
    }
  }
  return response({ order: publicOrder(order), refresh_delayed: delayed });
});
