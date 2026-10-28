# APK payment integration

Cash on delivery, seller dispatch, receipt confirmation and reviews are now
implemented; see [COMMERCE_DEMO.md](COMMERCE_DEMO.md) for the sample accounts and
complete workflow.

The Android app now has persistent cart entries, Buy Now checkout, quantity/total review,
an order list, checkout reopening, unpaid cancellation and payment refresh on Android
resume. The connected build uses the linked Supabase development project. There is
no separate shopping website. Checkout opens Xendit's hosted page; the customer
returns to the APK manually. HTTPS App Links and automatic return are not implemented.

## Deployed backend

Project: `qheletzzjnwsjaavbiqc` (`argnpln88's Project`, Comparts).

The new account is active in APK `0.4.6+13`. COD flow, online checkout/retry,
Xendit-confirmed cancellation, stock restoration, database permissions, sample
sign-ins, and all 32 catalog images were verified on this project. The scheduled
checker returns 200. Webhook registration and its token are still pending the
owner's Xendit password confirmation; no real collection/refund is claimed.
See [current verification](ACCOUNT_CONNECTION_STATUS.md).

Nine Edge Functions are deployed: `commerce-order`, `checkout-quote`, `checkout-create`,
`checkout-status`, `xendit-webhook`, `payment-reconcile`, `order-cancel`,
`refund-create`, and `payment-admin`.

Migrations `202610270001` through `202610280009` install the foundation, cart,
orders, provider attempts, durable event inbox, refunds, explicit table/function
permissions, and a protected payment checker running every two minutes. Its
credential is encrypted in Supabase Vault. The scheduler's HTTP responses were
verified as 200. Supabase service/secret keys and Xendit secrets stay in the backend.
The sample-media migration also creates the public Storage bucket and blocks
client uploads/replacements/deletions. Sample products, avatars and shop logos
now reference hosted Storage URLs; their public PNG contents were verified.

Each checkout is one listing from one seller, with up to 20 units. New orders
collect a delivery address and support COD or online payment. Legacy pickup
orders are preserved. Courier updates are manual and delivery is currently free;
there are no real seller payouts or escrow. All online payment requests are
PHP/PH, automatic capture and Xendit Test Mode. A live/public/missing key blocks online checkout.
`PAYMENT_RETURN_BASE_URL` is unused and can remain unset for this APK flow.

The backend locks stock and calculates totals. Checkout retries reuse a stored
order. An uncertain create response blocks replacement; it is not evidence of
failure. Provider IDs, when available, are retained for investigation. Only a
matching provider session and collected underlying payment can mark an order paid.
Refund creation requires a trusted payment admin or backend service credential;
refund creation ambiguity also blocks duplicate submissions. Refunds do not
automatically restock physical products.

## Required Xendit dashboard configuration

In **Test Mode → Settings → Webhooks**, register this URL:

```text
https://qheletzzjnwsjaavbiqc.supabase.co/functions/v1/xendit-webhook
```

Use it for Payment Session — Completed, Payment Session — Expired, Payment
Requests v3 payment status updates, and Unified Refunds succeeded/failed. Use
Test & Save. Tokens and merchant IDs must match the values in Supabase secrets.
The webhook acknowledges a verified event only after writing it to the durable
inbox. The checker then fetches authoritative provider state. Unknown references
remain quarantined, including dashboard sample payloads that do not match orders.
Dashboard tests alone do not prove an actual order was paid.

Xendit's dashboard can use a static sample merchant ID in Test & Save. With a
valid callback token, such a payload is durably quarantined and acknowledged with
200; it cannot update an order and is not sent to the payment processor. Incorrect
or missing callback tokens still receive 401. Actual payment processing requires
matching merchant, session, payment references, currency and amount.

## Local configuration and demo accounts

`config/mobile.dev.json` contains only the project URL and publishable key.
`.env.payment-test.json` contains dedicated demo seller/buyer accounts, their
sample passwords and fixture IDs. Both files are ignored by Git. Backend keys
are fetched in memory by the CLI helper and are never stored in those files.
Use the `buyer` credentials in the APK; these demo accounts were created and
confirmed with the Supabase admin API, so they do not test email delivery.
The two published test listings clearly state they are not real products.

```powershell
node scripts/payment-dev.mjs health
node scripts/payment-dev.mjs probe
node scripts/payment-dev.mjs verify
node scripts/payment-dev.mjs race
.\scripts\supabase.ps1 db query --linked --file supabase/tests/payments.sql
npx.cmd --yes deno test --allow-env supabase/functions/_shared
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 apk -Release -Config config/mobile.dev.json
```

The setup command (`node scripts/payment-dev.mjs setup`) configures public mobile
settings and the scheduler, and creates development fixtures. Do not run it
against production. The verification script can create an actual **test** session;
never treat it as a load test or blindly replace an uncertain order.

To grant refund administration, a project owner must insert the intended existing
Auth user ID into `public.payment_admins` through a trusted database operation.
No app user can grant themselves that role. No personal user was given this role
by the setup. `payment-admin` supports a service-authenticated health check,
scheduler setup, session inspection and reconciliation; it exposes no secret values.

## Validation and limits

Flutter tests cover the existing auth/catalog flows and payment error/uncertainty
screens. Deno tests cover amount precision, merchant/session matching, collected
payments, URL validation and callback secrets. Transactional database tests roll
back every artificial paid/refund state, and test reservations, last-unit stock,
retries, immutable final states, refund uniqueness, privileges and cross-user RLS.
Hosted checks reject forged tokens, self-purchase, changed prices, cross-buyer
reads, direct paid writes, payment RPC access and unauthorized refunds. These
checks do not substitute for a real Xendit test payment.

Before claiming an end-to-end successful integration, complete a hosted test
payment, receive its real webhook, confirm the backend reports paid, then test
provider-supported refund success/failure and cancellation/expiry races. Channel
availability and refund permissions depend on the Xendit account. This remains
a development APK signed with the debug certificate; live collection, production
signing, seller management, shipping, multi-item checkout and complete marketplace
features require additional work.

## Historical verification on the previous project

The records below refer to `mosmaxlegakexjutqeaa` and its earlier APKs, unless
the current account-status document explicitly records the check on the new
project. In particular, the earlier saved webhooks do not configure the new account.

- Flutter analysis: clean; 24 Flutter tests passed.
- Eight Deno policy/reconciliation tests passed, including the canonical Xendit
  capture shape (capture entries do not need their own status field).
- Hosted SQL transaction/privilege/RLS tests passed. Artificial paid/refund
  states were rolled back.
- Concurrent requests from different buyers for the last unit produced exactly
  one reservation. Releasing that DB-only reservation twice restored stock once.
- Xendit's authenticated session lookup responded correctly; real PHP 100 Test
  Mode hosted sessions were created with matching merchant, order and amount.
- Hosted endpoint checks passed for idempotency, changed prices, self-purchase,
  cross-buyer data isolation, unauthorized payment writes/RPCs and refunds.
- An unpaid Test Mode session was cancelled through Xendit; the backend confirmed
  `cancelled`, and a repeated cancellation returned the same terminal result.
- The current APK is `dist/comparts-ecommerce-demo.apk`, version `0.4.5+11`, built
  against this development project. It was installed and launched successfully
  on the `Pixel_10_Pro_XL` Android emulator; the home screen loaded the hosted
  test catalog. A physical-phone checkout test has not been completed.

The shop was renamed to COMPARTS on 2026-10-28 in the Android launcher label,
app screens, local Auth email templates and checkout session description. The
checkout-create function was redeployed with the new name. The Android package
and auth callback scheme remain unchanged for update/callback compatibility.
The existing development seller's shop name was also updated to COMPARTS and
verified through the hosted API. The APK passed all 42 Flutter tests, static
analysis and a release build; its packaged launcher label is COMPARTS.
Hosted SMTP and both OTP templates are now saved and verified after reload.
Gmail accepted the sender credentials over STARTTLS. The APK also rejects an
obfuscated duplicate signup response rather than implying a new confirmation
email was sent. A user-authorized password-reset request returned HTTP 200 and
the recipient confirmed receiving a six-digit code. Signup delivery for a fresh
account and completion of password recovery remain separate tests, tracked in
[AUTH_EMAIL_STATUS.md](AUTH_EMAIL_STATUS.md).

Webhook registration was subsequently completed in Xendit's dashboard: session
completed/expired, Payment Request Status, Payment Status and Refund Status were
saved, and authenticated dashboard samples reached the backend. A completed
hosted test payment/refund is still pending verification. No successful
collection or refund is claimed yet.

The 0.4.3 app labels the payment method **Online payment** and shows **Paid**
after server-confirmed collection. These UI labels do not change the Xendit
Test Mode credentials or Xendit's hosted-page labels. Saved delivery addresses
and camera/gallery review photos are described in [COMMERCE_DEMO.md](COMMERCE_DEMO.md).
The initial developer checkout `9b1216ed-46ed-408d-9123-3d46d9237f3d` has an
uncertain creation result from an early checkout-URL validation failure. Its
reservation is intentionally held. Resolve it by finding its session in Xendit
using that order reference, or by receiving its authenticated lifecycle webhook.
Do not reset it or assume a local timer proves it unpaid. A subsequent known
session was recovered after allowing Xendit's actual `dev.xen.to` test domain.

API references: [sessions](https://docs.xendit.co/apidocs/create-session),
[payment requests](https://docs.xendit.co/apidocs/get-payment-request),
[collected payments](https://docs.xendit.co/apidocs/get-payment),
[refund creation](https://docs.xendit.co/apidocs/refund-payment-request), and
[refund retrieval in Xendit's official SDK](https://github.com/xendit/xendit-node/blob/master/docs/Refund.md).
