# COMPARTS orders, delivery and reviews

The configured Android build supports cash on delivery and Xendit Test Mode,
private delivery-address snapshots, seller dispatch, buyer receipt confirmation,
and verified-purchase star ratings with written review notes.

## Sample accounts

Open [the local demo login file](../dist/COMPARTS_DEMO_ACCOUNTS.txt) for passwords.
This file is ignored by version control and is not included in the APK.

| Account | Email | Password | Access |
| --- | --- | --- | --- |
| Sample seller | `comparts-seller@example.com` | `test123` | Account > Seller Center |
| Sample buyer | `comparts-buyer@example.com` | `test123` | Shopping, Orders, receipt and reviews |

Use **Sign in** for these existing accounts. The earlier isolated payment-test
accounts also use `test123`; all five sample-account sign-ins were verified.

These fictional demo accounts are preverified and cannot receive email. The
catalog has at least three listings in every category (32 total). The buyer has a completed Ryzen purchase with
a clearly labeled sample review, and a Keychron keyboard order ready to ship.
The active backend is `qheletzzjnwsjaavbiqc`. Historical orders remain preserved
in the previous development project; they were not copied into this project.

## Supabase sample images and accounts

All five sample/test logins exist in Supabase Authentication, with matching
database profiles. Their avatars are saved in `profiles.avatar_url` and Auth
user metadata. The two sample shop records have `seller_profiles.logo_url`.

The public Storage bucket is **comparts-sample-media**:

- `categories/`: ten category illustrations covering every sample category.
- `avatars/`: seller and buyer avatars used by the five sample accounts.
- `branding/`: the COMPARTS shop logo.

The 13 current images were fetched without authentication, checked as PNG files,
and matched against the source SHA-256 hashes. Object names contain a content
hash, so the bucket can retain older revisions without serving stale artwork.
All 32 hosted sample product records now have Storage image URLs and an
illustration flag. The configured APK reads those hosted records; the separate
offline preview fixture remains available only when backend configuration is
omitted.

Sample account sign-ins, profile avatars and public shop logos were verified
through Supabase. Anonymous and buyer attempts to upload media were rejected;
restrictive Storage policies also prevent client replacement or deletion.
Service keys are used only by provisioning scripts, never by the APK.

To check this in the dashboard, open Authentication > Users, Table Editor >
profiles / seller_profiles / products, and Storage > comparts-sample-media.
For a reproducible audit, run `node scripts/sample-media.mjs verify`. Source
artwork and rendering/upload instructions are in
[assets/sample-media/README.md](../assets/sample-media/README.md).

## Try the ready-to-ship order

1. Sign out of the current account from Account.
2. Sign in as the sample seller using the login file above.
3. Open Account > Seller Center, then the Keychron keyboard order marked To ship.
4. Tap Mark out for delivery. Enter `Demo Courier` and a sample waybill such as
   `CP-DEMO-001`, then submit. The buyer now sees Out for delivery and tracking.
5. Sign out, then sign in as the sample buyer.
6. Open Orders and that keyboard purchase. Tap Mark as received. For COD, this
   confirmation also acknowledges that the buyer paid cash to the courier.
7. Choose 1–5 stars, write review notes, and submit. The seller can read the
   feedback; the product listing shows it as a verified-purchase review.

Use sample dispatch/receipt updates only while demonstrating this sample order.
For an actual parcel, enter the real tracking details and confirm receipt only
after the item arrives and any COD amount is paid.

## Place a fresh order

Sign in as the buyer, choose a listing and tap Buy now. Enter recipient name,
contact number, complete street/barangay, city/province and a four-digit postal
code. Select Cash on delivery or Online payment and review the total. Delivery
is currently free. A checkout contains one listing with up to 20 units.

The demo buyer has a saved sample address: Sample Buyer, 09171234567,
123 Sample Street, Barangay Demo, Quezon City, Metro Manila, 1100.
**Use current address** selects the account's saved address; **Update address**
opens the editable fields and **Save delivery address** stores the changes.
This selects a saved delivery address, rather than device GPS. Saved addresses
are private to their owner. Previous orders keep their original address snapshot.

The payment option is labeled **Online payment**. A separate **Paid** badge appears
only when the backend reports a confirmed payment, independently of delivery status.
This wording does not change the configured Xendit Test Mode environment or the
labels on Xendit's own hosted checkout page.

After receipt, reviews support **Capture item** (camera) and **Add photo** (gallery),
with up to three JPG/PNG/WebP images, 3 MB each. Photos are public with the review.
Only the buyer of a delivered, paid purchase can upload its review photos; submitted
photos cannot be replaced through the app. A sample storage-item review includes
an explicitly labeled illustration, not a real customer's photo.

COD places a backend order without opening Xendit. Online payments open Xendit
Test Mode and become dispatchable only after provider-confirmed payment. The
seller enters delivery updates manually; there is no live courier integration,
automatic COD collection, seller payout, shipping-rate service or escrow.

COD orders can be cancelled before dispatch by their buyer or seller. A
confirmed cancellation restores reserved stock once. Receipt is available only
after dispatch. Only the buyer of a completed, paid purchase can submit its one
review. Unrelated users cannot read an order, delivery address or event history.

## Deployment and verification

Migrations `202610280007_commerce.sql` and `202610280009_addresses_review_photos.sql`, and the `commerce-order` Edge Function are
deployed in the linked project. `checkout-create` and `order-cancel` were updated.
No privileged database or SMTP credentials are included in the mobile app.

The delivery APK is `dist/comparts-ecommerce-demo.apk`, version `0.4.5+11`.
The current Gmail signup-delivery blocker is recorded in [Auth email status](AUTH_EMAIL_STATUS.md).
Quantity supports minus/plus buttons and direct numeric entry (1–20 items).
See [checkout UI update](CHECKOUT_UI_2026-10-28.md) for the latest styling and checks.
It was installed and launched on the Android emulator. The hosted catalog and
the delivery-address/COD checkout screen were visually checked on that device.
The current build was also visually checked displaying the Supabase-hosted
product illustrations rather than its loading placeholders.

Checks passed:

- 52 Flutter tests, including readable email-delivery errors, quantity entry/buttons and quote refresh,
  saved-address editing/reuse, camera-photo review
  submission, confirmed-payment badges, COD/online checkout, address validation, seller
  action visibility, buyer receipt acknowledgement, and review availability.
- Visible Back buttons work even after checkout replaces the previous route.
  Order details return to Orders or Seller Center as appropriate. Filter and
  dispatch/receipt/cancellation modal Back buttons close without saving drafts
  or submitting an order update.
- Leaving checkout during a pending request does not access a disposed screen
  or unexpectedly redirect after the response arrives.
- The live catalog preserves hosted product image URLs, the illustration label,
  and the seller logo returned by Supabase.
- Nine Deno payment-policy/reconciliation tests and Deno type checks, including
  a guard preventing online payment reconciliation from changing COD orders.
- Hosted end-to-end COD placement, concurrent retry idempotency, stock decrement,
  dispatch, receipt, COD payment acknowledgement, review and public projection.
- Rejection of forged auth, self-purchase, price tampering, invalid shipping,
  cross-account reads, direct status writes, premature receipt/reviews and seller
  attempts to perform buyer-only actions.
- Cancellation and repeat cancellation restored stock once. Concurrent buyers
  competing for one unit produced exactly one order; temporary race records
  were removed after verification.
- Xendit checkout with shipping, checkout retry, provider-confirmed cancellation
  and stock restoration. No new successful online collection/refund is claimed.
- SQL assertions verified RLS and that clients cannot directly write commerce
  tables or call service-only transition functions.

To reprovision or verify the development fixtures:

```powershell
node scripts/commerce-dev.mjs setup
node scripts/catalog-delivery-update.mjs
node scripts/catalog-delivery-update.mjs verify
node scripts/commerce-dev.mjs verify
node scripts/commerce-dev.mjs verify-online
node scripts/commerce-dev.mjs verify-race
npx.cmd --yes supabase db query --linked --file supabase/tests/commerce_permissions.sql
```

`verify` creates sample COD activity and leaves a ready-to-ship order. It uses
the local demo credentials and the earlier isolated payment outsider fixture.
Do not use these development scripts against a production project.
