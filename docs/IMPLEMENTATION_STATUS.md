# Implementation status

This delivery is the first Android development build. It is not a completed
marketplace. The original eight-stage scope remains tracked below.

## Implemented in this build

The focused APK payment integration is documented in [PAYMENTS_HANDOFF.md](PAYMENTS_HANDOFF.md).
The broader marketplace stages below remain incomplete.

- Android Flutter project and COMPARTS branding.
- Material 3 theme and five bottom navigation destinations.
- Feature-based presentation, application and repository organization.
- GoRouter routing and Riverpod providers.
- Optional Supabase initialization from public build-time configuration.
- Explicit no-credentials preview mode with 20 sample parts and three sample shop names.
- Ten categories, name search, category/condition filters and price/newest sorting.
- Paginated repository queries, loading placeholders, retry and empty states.
- Product detail/specification screens and code-drawn category illustrations.
- Supabase Auth repository and sign-up, sign-in, resend, reset, password update and sign-out UI.
- Six-digit email OTP screens for sign-up and forgot password, purpose-specific
  verification, recovery-session gating, resend cooldowns, email templates and
  hosted/local setup instructions. Recovery OTP inbox delivery is verified.
- Auth callback intent filter; recovery event routing; allowed post-login destinations.
- Initial profiles/public sellers/categories/products migration with RLS and restricted grants.
- Reproducible Windows run/build/check commands and development APK.
- Persistent cart and single-listing Buy Now with quantity and server quote review.
- Deployed Test Mode payment tables, atomic reservations, serialized checkout,
  durable webhook inbox, protected two-minute reconciliation, unpaid cancellation
  and admin full-refund endpoint.
- Orders, payment-status refresh on resume, manual return from hosted checkout,
  and explicit pending/review states. No separate shopping website is required.
- Cash-on-delivery checkout, validated private delivery addresses, seller order
  management, courier/tracking entry, buyer receipt/COD acknowledgement, delivery
  events, cancellation restocking and verified-purchase ratings/review notes.
- Separate sample seller/buyer accounts and at least two hosted listings per
  category (22 total), private reusable delivery addresses, and camera/gallery
  review photos. See
  [COMMERCE_DEMO.md](COMMERCE_DEMO.md) for credentials and the tested workflow.
- Public Supabase Storage sample illustrations, account avatars and shop logos,
  connected to the hosted product/Auth/profile records with read-only client
  access. The configured catalog never substitutes local sample records.

Auth and live catalog code require real Supabase account configuration and tests.
Local preview listings remain separate from hosted sample seller accounts and
products. Cart, checkout, Orders, Seller Center and reviews use the development
backend. Checkout supports one listing per order, a delivery-address snapshot,
free delivery, COD or Xendit Test Mode. Courier updates and cash collection are
manual; seller payouts and live courier integration are not implemented.

## Remaining stages

- [ ] 1. Foundation/auth completion: real-account validation, full profile editing,
  photos/phone, addresses/default address, deletion requests, and complete
  intended-action persistence across verification and application restarts.
- [ ] 2. Remaining database migrations, transaction functions, full permissions,
  Storage policies/validation, private data projections and authorization tests.
- [ ] 3. Seller onboarding/approval/admin permissions, seller product management,
  category-specific validation, image galleries, shops, reporting, comparison,
  stock/brand/price filters, caching, real activity/recently-viewed/featured feeds,
  and real seed accounts/products.
- [ ] 4. Remaining wishlist, multi-listing cart checkout, reusable address book,
  delivery-rate integrations and vouchers. Persistent carts, Buy Now, per-order
  delivery addresses, COD and server-calculated item totals are implemented.
- [ ] 5. Atomic stock reservations, payment sessions/attempts/events, authenticated
  checkout functions, Xendit TEST MODE hosted checkout, HTTPS App Links,
  durable webhooks, duplicate/uncertain-response handling and reconciliation.
- [ ] 6. Remaining returns, completed provider-refund validation and seller ledger.
  Order delivery states/timelines, address snapshots, seller dispatch, buyer
  receipt and COD/online unpaid cancellation are implemented.
- [ ] 7. Remaining review moderation, participant-only messages/blocking,
  in-app notifications, support/configurable policies, full administrator tools
  and audited privileged operations.
- [ ] 8. Full payment/inventory/authorization/review automated checks, all original
  acceptance scenarios, broader device/offline/accessibility/UI verification,
  release signing and genuine account-configured test transactions.

Deferred enhancements from the original scope remain deferred: PC compatibility
checker, push notifications, live courier integration, and actual xenPlatform
seller onboarding/routing/splits/payouts. No wallet, escrow or automatic seller
settlement is represented in this build.
