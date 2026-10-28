import { body, response, rpc, serve, user } from "../_shared/backend.ts";
import { quantity, uuid } from "../_shared/policy.ts";
serve(async (req) => {
  const account = await user(req), input = await body(req);
  const quote = await rpc("payment_quote", {
    p_buyer: account.id,
    p_product: uuid(input.product_id),
    p_quantity: quantity(input.quantity),
  });
  return response(quote);
});
