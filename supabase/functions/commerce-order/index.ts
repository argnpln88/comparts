import {
  body,
  db,
  publicOrder,
  reconcile,
  response,
  rpc,
  serve,
  user,
} from "../_shared/backend.ts";
import { HttpError, quantity, uuid } from "../_shared/policy.ts";

serve(async (req) => {
  const account = await user(req), input = await body(req);
  if (input.action === "create_cod") {
    if (
      !Number.isSafeInteger(input.expected_unit_price_centavos) ||
      Number(input.expected_unit_price_centavos) <= 0
    ) {
      throw new HttpError(400, "Review the current price first.");
    }
    const order = await rpc("commerce_create_cod", {
      p_actor: account.id,
      p_product: uuid(input.product_id),
      p_quantity: quantity(input.quantity),
      p_key: uuid(input.idempotency_key),
      p_expected_unit: input.expected_unit_price_centavos,
      p_shipping: input.shipping_address,
    });
    return response({ order: publicOrder(order) });
  }
  const id = uuid(input.order_id);
  const { data, error } = await db().from("orders").select("*").eq("id", id)
    .or(`buyer_id.eq.${account.id},seller_id.eq.${account.id}`).maybeSingle();
  if (error) throw new Error("Order lookup failed");
  if (!data) throw new HttpError(404, "Order not found.");
  let order = data;
  const seller = order.seller_id === account.id;
  switch (input.action) {
    case "get": {
      let delayed = false;
      if (
        !seller && order.payment_method === "xendit" &&
        order.payment_session_id &&
        ["creating", "creation_unknown", "payment_pending", "payment_review"]
          .includes(order.status) &&
        (!order.last_checked_at ||
          Date.now() - Date.parse(order.last_checked_at) > 10000)
      ) {
        try {
          order = await reconcile(order);
        } catch {
          delayed = true;
        }
      }
      const [events, review] = await Promise.all([
        db().from("order_delivery_events").select("event,note,created_at").eq(
          "order_id",
          id,
        ).order("created_at"),
        db().from("order_reviews").select(
          "rating,review_notes,reviewer_name,photo_paths,created_at",
        ).eq("order_id", id).maybeSingle(),
      ]);
      if (events.error || review.error) {
        throw new Error("Order activity lookup failed");
      }
      return response({
        order: publicOrder(order),
        role: seller ? "seller" : "buyer",
        events: events.data,
        review: review.data,
        refresh_delayed: delayed,
      });
    }
    case "dispatch":
      if (!seller) {
        throw new HttpError(403, "Only the seller can dispatch this order.");
      }
      order = await rpc("commerce_dispatch", {
        p_actor: account.id,
        p_order: id,
        p_courier: input.courier,
        p_tracking: input.tracking_number,
      });
      break;
    case "receive":
      if (seller) {
        throw new HttpError(403, "Only the buyer can confirm receipt.");
      }
      order = await rpc("commerce_receive", {
        p_actor: account.id,
        p_order: id,
      });
      break;
    case "cancel":
      order = await rpc("commerce_cancel_cod", {
        p_actor: account.id,
        p_order: id,
      });
      break;
    case "review":
      if (seller) {
        throw new HttpError(403, "Only the buyer can review this order.");
      }
      if (!Number.isInteger(input.rating)) {
        throw new HttpError(400, "Choose a whole-star rating.");
      }
      if (input.photo_paths !== undefined && (!Array.isArray(input.photo_paths) ||
        input.photo_paths.length > 3 || input.photo_paths.some((p) => typeof p !== "string" || p.length > 200))) {
        throw new HttpError(400, "Review supports up to three item photos.");
      }
      return response({
        review: await rpc("commerce_review", {
          p_actor: account.id,
          p_order: id,
          p_rating: input.rating,
          p_notes: input.review_notes,
          p_photos: input.photo_paths ?? [],
        }),
      });
    default:
      throw new HttpError(400, "Unknown order action.");
  }
  return response({ order: publicOrder(order) });
});
