export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new HttpError(400, "A valid ID is required.");
  }
  return value;
}

export function quantity(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > 20
  ) {
    throw new HttpError(400, "Quantity must be between 1 and 20.");
  }
  return value;
}

export function centavos(amount: unknown): number {
  // Provider amounts are major PHP units. Reject excess precision, NaN, and unsafe ranges.
  if (
    typeof amount !== "number" || !Number.isFinite(amount) || amount < 0 ||
    amount > 100000000
  ) {
    throw new HttpError(409, "Invalid provider amount.");
  }
  const cents = Math.round(amount * 100);
  if (Math.abs(amount * 100 - cents) > 0.00001) {
    throw new HttpError(409, "Invalid provider precision.");
  }
  return cents;
}

export function checkoutUrl(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(502, "Checkout URL is missing.");
  }
  const url = new URL(value);
  if (
    url.protocol !== "https:" || url.username || url.password ||
    !(url.hostname === "xen.to" || url.hostname === "dev.xen.to" ||
      url.hostname.endsWith(".xendit.co"))
  ) {
    throw new HttpError(502, "Unexpected checkout URL.");
  }
  return url.href;
}

export async function equalSecret(
  actual: string,
  expected: string,
): Promise<boolean> {
  if (!actual || !expected) return false;
  const encode = new TextEncoder();
  const [a, b] = await Promise.all(
    [actual, expected].map(async (s) =>
      new Uint8Array(await crypto.subtle.digest("SHA-256", encode.encode(s)))
    ),
  );
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

export function validateSession(
  session: Record<string, unknown>,
  order: Record<string, unknown>,
  business: string,
): void {
  if (
    session.business_id !== business || session.reference_id !== order.id ||
    session.session_type !== "PAY" ||
    session.mode !== "PAYMENT_LINK" || session.currency !== "PHP" ||
    session.country !== "PH" ||
    centavos(session.amount) !== Number(order.total_centavos) ||
    (session.capture_method != null &&
      session.capture_method !== "AUTOMATIC") ||
    (order.payment_session_id &&
      session.payment_session_id !== order.payment_session_id)
  ) {
    throw new HttpError(
      409,
      "Provider session does not match this order. Payment needs review.",
    );
  }
}

export function collected(
  request: Record<string, unknown>,
  total: number,
): boolean {
  if (
    request.capture_method !== "AUTOMATIC" || request.currency !== "PHP" ||
    centavos(request.request_amount) !== total
  ) return false;
  const captures = Array.isArray(request.captures) ? request.captures : [];
  const captured = captures.filter((c) =>
    c.status == null || c.status === "SUCCEEDED"
  ).reduce(
    (sum, c) => sum + centavos(c.capture_amount),
    0,
  );
  return request.status === "SUCCEEDED" &&
    (captured === total || captures.length === 0);
}
