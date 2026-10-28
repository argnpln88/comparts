import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import {
  centavos,
  checkoutUrl,
  collected,
  equalSecret,
  HttpError,
  validateSession,
} from "./policy.ts";

export const env = (key: string): string => Deno.env.get(key) ?? "";
function secretKeys(): Record<string, string> {
  try {
    return JSON.parse(env("SUPABASE_SECRET_KEYS") || "{}");
  } catch {
    return {};
  }
}
export const db = () =>
  createClient(
    env("SUPABASE_URL"),
    secretKeys().default || env("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
export type Order = Record<string, any>;
export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export function response(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { ...cors, "Cache-Control": "no-store" },
  });
}
export function serve(handler: (req: Request) => Promise<Response>): void {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });
    if (req.method !== "POST") return response({ error: "Use POST." }, 405);
    try {
      return await handler(req);
    } catch (error) {
      if (error instanceof HttpError) {
        return response({ error: error.message }, error.status);
      }
      // Never log credentials, raw request bodies, or provider customer data.
      console.error(
        "Payment operation failed",
        error instanceof Error ? error.name : "UnknownError",
      );
      return response({
        error:
          "Payment service is temporarily unavailable. Check Orders before trying again.",
      }, 503);
    }
  });
}
export async function body(req: Request): Promise<Record<string, unknown>> {
  const raw = await req.text();
  if (raw.length > 65536) throw new HttpError(413, "Request is too large.");
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error();
    }
    return parsed;
  } catch {
    throw new HttpError(400, "A JSON object is required.");
  }
}
export async function user(req: Request) {
  const bearer = req.headers.get("authorization") ?? "";
  if (!bearer.startsWith("Bearer ")) {
    throw new HttpError(401, "Sign in to continue.");
  }
  const { data, error } = await db().auth.getUser(bearer.slice(7));
  if (error || !data.user || !data.user.email_confirmed_at) {
    throw new HttpError(401, "Sign in with a verified email account.");
  }
  return data.user;
}
export async function isService(req: Request): Promise<boolean> {
  if (
    await equalSecret(
      (req.headers.get("authorization") ?? "").replace(/^Bearer /, ""),
      env("SUPABASE_SERVICE_ROLE_KEY"),
    )
  ) return true;
  for (const key of Object.values(secretKeys())) {
    if (await equalSecret(req.headers.get("apikey") ?? "", key)) return true;
  }
  return false;
}
export async function admin(req: Request): Promise<void> {
  if (await isService(req)) return;
  const account = await user(req);
  const { data, error } = await db().from("payment_admins").select("user_id")
    .eq("user_id", account.id).maybeSingle();
  if (error || !data) {
    throw new HttpError(403, "Payment administrator access is required.");
  }
}
export function config(): void {
  if (
    env("XENDIT_ENV") !== "test" ||
    !env("XENDIT_SECRET_KEY").startsWith("xnd_development_") ||
    !env("XENDIT_BUSINESS_ID")
  ) {
    throw new HttpError(
      503,
      "Configure a Xendit TEST secret key, business ID, and XENDIT_ENV=test in Supabase secrets.",
    );
  }
}
export class ProviderError extends Error {
  constructor(public status: number, public code: string) {
    super("Xendit request failed");
  }
}
export async function xendit(
  path: string,
  method = "GET",
  payload?: unknown,
): Promise<Record<string, any>> {
  config();
  const result = await fetch(`https://api.xendit.co${path}`, {
    method,
    headers: {
      "Authorization": `Basic ${btoa(env("XENDIT_SECRET_KEY") + ":")}`,
      "Content-Type": "application/json",
      "api-version": "2024-11-11",
    },
    body: payload === undefined ? undefined : JSON.stringify(payload),
    signal: AbortSignal.timeout(20000),
  });
  const parsed = await result.json().catch(() => ({}));
  if (!result.ok) {
    throw new ProviderError(
      result.status,
      String(parsed.error_code ?? "PROVIDER_ERROR"),
    );
  }
  return parsed;
}
export async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db().rpc(name, args);
  if (error) {
    const known =
      /Quantity|Listing unavailable|own listing|Insufficient stock|Price changed|Order total|Checkout key|existing checkout|confirmed paid|Shipping|Cash on delivery|Order is not|Order can only|Only the|Only delivered|Review|Rating|Delivery/
        .test(error.message);
    if (known) throw new HttpError(409, error.message);
    throw new Error(`Database operation ${name} failed`);
  }
  return data;
}
export async function orderFor(id: string, buyer?: string): Promise<Order> {
  let query = db().from("orders").select("*").eq("id", id);
  if (buyer) query = query.eq("buyer_id", buyer);
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error("Could not read order");
  if (!data) throw new HttpError(404, "Order not found.");
  return data;
}
export function publicOrder(order: Order): Order {
  const {
    creation_token: _token,
    idempotency_key: _key,
    last_error: _error,
    ...result
  } = order;
  return result;
}
export async function reconcile(
  order: Order,
  knownSession?: Record<string, any>,
): Promise<Order> {
  if (order.payment_method === "cod") return order;
  if (!order.payment_session_id && !knownSession) return order;
  const session = knownSession ??
    await xendit(`/sessions/${encodeURIComponent(order.payment_session_id)}`);
  validateSession(session, order, env("XENDIT_BUSINESS_ID"));
  if (
    !order.payment_session_id ||
    (!order.payment_link_url &&
      ["creating", "creation_unknown", "payment_pending"].includes(
        order.status,
      ))
  ) {
    await rpc("payment_attach", {
      p_order: order.id,
      p_session: session.payment_session_id,
      p_url: checkoutUrl(session.payment_link_url),
      p_expires: session.expires_at,
    });
    order = await orderFor(order.id);
  }
  const { data: attempts, error } = await db().from("payment_attempts").select(
    "payment_request_id",
  ).eq("order_id", order.id);
  if (error) throw new Error("Could not read attempts");
  const ids = new Set<string>(
    (attempts ?? []).map((a) => a.payment_request_id),
  );
  for (
    const id of [
      session.payment_request_id,
      session.latest_payment_request_id,
      order.payment_request_id,
    ]
  ) if (id) ids.add(id);
  let canRelease = true;
  let paid = false;
  for (const id of ids) {
    const request = await xendit(
      `/v3/payment_requests/${encodeURIComponent(id)}`,
    );
    if (
      request.business_id !== env("XENDIT_BUSINESS_ID") ||
      request.payment_request_id !== id || request.currency !== "PHP" ||
      centavos(request.request_amount) !== Number(order.total_centavos)
    ) throw new HttpError(409, "Payment business or reference mismatch.");
    const paymentId = request.latest_payment_id ??
      request.latest_payment?.payment_id ?? session.payment_id;
    const payment = paymentId
      ? await xendit(`/v3/payments/${encodeURIComponent(paymentId)}`)
      : null;
    if (
      payment &&
      (payment.business_id !== env("XENDIT_BUSINESS_ID") ||
        payment.payment_request_id !== id || payment.payment_id !== paymentId)
    ) {
      throw new HttpError(409, "Collected payment reference mismatch.");
    }
    const saved = await db().from("payment_attempts").upsert({
      payment_request_id: id,
      order_id: order.id,
      status: payment?.status ?? request.status,
      updated_at: new Date().toISOString(),
    });
    if (saved.error) throw new Error("Could not record attempt");
    if (payment && collected(payment, Number(order.total_centavos))) {
      await rpc("payment_apply", {
        p_order: order.id,
        p_state: "paid",
        p_request: id,
        p_payment: payment.payment_id,
      });
      paid = true;
    } else if (
      !["FAILED", "EXPIRED", "CANCELED"].includes(request.status) ||
      (payment && !["FAILED", "EXPIRED", "CANCELED"].includes(payment.status))
    ) {
      canRelease = false;
    }
  }
  if (session.status === "COMPLETED" && !paid) {
    // Completed SAVE/authorization/unknown payment is never treated as collected money.
    await rpc("payment_apply", {
      p_order: order.id,
      p_state: "payment_review",
      p_error: "Completed session needs matching collection confirmation",
    });
  } else if (
    !paid && canRelease && ["EXPIRED", "CANCELED"].includes(session.status)
  ) {
    await rpc("payment_apply", {
      p_order: order.id,
      p_state: session.status === "EXPIRED" ? "expired" : "cancelled",
    });
  }
  const updated = await db().from("orders").update({
    last_checked_at: new Date().toISOString(),
  }).eq("id", order.id);
  if (updated.error) throw new Error("Could not record reconciliation");
  return await orderFor(order.id);
}
export async function processEvent(event: Order): Promise<void> {
  const payload = event.payload;
  const data = payload.data ?? {};
  if (payload.business_id !== env("XENDIT_BUSINESS_ID")) {
    throw new Error("Business mismatch");
  }
  if (
    payload.event === "refund.succeeded" || payload.event === "refund.failed"
  ) {
    const { data: refund, error } = await db().from("refunds").select("*").eq(
      "provider_id",
      data.id,
    ).maybeSingle();
    if (error || !refund) throw new Error("Refund reference is not stored yet");
    const provider = await xendit(
      `/refunds/${encodeURIComponent(refund.provider_id)}`,
    );
    const order = await orderFor(refund.order_id);
    if (
      provider.payment_request_id !== order.payment_request_id ||
      provider.currency !== "PHP" ||
      centavos(provider.amount) !== Number(order.total_centavos)
    ) throw new Error("Refund mismatch");
    await rpc("payment_refund_apply", {
      p_refund: refund.id,
      p_status: provider.status === "SUCCEEDED"
        ? "succeeded"
        : provider.status === "FAILED"
        ? "failed"
        : "pending",
      p_provider: refund.provider_id,
    });
  } else {
    const sessionId = data.payment_session_id ??
      (String(payload.event).startsWith("payment_session.") &&
          typeof data.id === "string" && data.id.startsWith("ps-")
        ? data.id
        : null);
    let order: Order | null = null;
    if (sessionId) {
      const session = await xendit(
        `/sessions/${encodeURIComponent(sessionId)}`,
      );
      order = await orderFor(session.reference_id);
      await reconcile(order, session);
    } else if (data.payment_request_id) {
      const { data: attempt } = await db().from("payment_attempts").select(
        "order_id",
      ).eq("payment_request_id", data.payment_request_id).maybeSingle();
      if (attempt) order = await orderFor(attempt.order_id);
      if (!order && typeof data.reference_id === "string") {
        const { data: found } = await db().from("orders").select("*").eq(
          "id",
          data.reference_id,
        ).maybeSingle();
        order = found;
      }
      if (!order) throw new Error("Payment reference is not stored yet");
      await reconcile(order);
    } else throw new Error("Event is missing a usable reference");
  }
  const saved = await db().from("payment_events").update({
    processed_at: new Date().toISOString(),
    last_error: null,
  }).eq("id", event.id);
  if (saved.error) throw new Error("Could not acknowledge event");
}
