# COMPARTS: Supabase and Xendit setup

The Android app now also supports cash-on-delivery orders, seller dispatch,
buyer receipt confirmation and purchase ratings/reviews. For sample seller and
buyer logins and the complete walkthrough, see [COMMERCE_DEMO.md](COMMERCE_DEMO.md).

> **Current APK integration:** A Test Mode payment backend, cart, Buy Now and order
> screens have now been added and deployed. Read [PAYMENTS_HANDOFF.md](PAYMENTS_HANDOFF.md)
> for the actual implementation, account steps, verification and limitations.
> This APK flow uses Xendit's hosted checkout result screen and manual return to
> the app; `PAYMENT_RETURN_BASE_URL` and a separate website are not required.
> The broader architecture below also describes future marketplace features;
> it is not a statement that every listed function or feature is implemented.

Prepared for your Flutter Android marketplace requirements. Documentation checked on October 27, 2026.

This is an account configuration and implementation guide. It does not create cloud accounts, deploy a backend, or implement the Flutter app. The supplied examples contain placeholders only. Commands in the deployment section require the migrations and functions described here to be implemented first.

A Flutter Android build and a focused Test Mode payment integration were subsequently added to this workspace. See [README](../README.md), [payment handoff](PAYMENTS_HANDOFF.md), and [implementation status](IMPLEMENTATION_STATUS.md) for the current scope. The complete marketplace design described below remains broader than this implementation.

## 1. What you need

| Item | Purpose |
| --- | --- |
| Supabase account and a development project | Auth, PostgreSQL, Storage, Edge Functions |
| Xendit account configured for the Philippines | TEST MODE hosted payment collection |
| Email account and access to both dashboards | Verification and configuration |
| Flutter stable, Dart, Android Studio/SDK, Android device or emulator | Build and test the app |
| Node.js 20+ and Supabase CLI | Migrations, secrets, function deployment |
| Docker Desktop if running Supabase locally | Local database, Auth and function testing |
| HTTPS hostname you control, including a free hosting hostname if suitable | Payment return pages and Android App Links |
| SMTP service and verified sender, for testing with non-team users | Registration, verification, password reset emails |
| Android application ID and signing certificate SHA-256 fingerprint | Verify App Links |

Keep development and production configuration separate. Start with one Supabase development project and Xendit TEST MODE. A Supabase project has no equivalent automatic Xendit test/live switch: your project separation and backend credentials determine the environment.

Supabase CLI installation and local requirements: [official CLI guide](https://supabase.com/docs/guides/local-development/cli/getting-started).

## 2. Architecture and responsibilities

```text
Flutter app
  |-- Supabase Auth: registration, sessions, email verification
  |-- Supabase Data API + RLS: catalog and authorized user data
  |-- Supabase Storage policies: images and attachments
  `-- authenticated Edge Functions: quotes, checkout, fulfillment, refunds
          |-- PostgreSQL transactions: totals, reservations, state changes
          `-- Xendit API: create/retrieve/cancel Payment Sessions and refund

Xendit --> public HTTPS Edge Function --> durable payment event inbox
                                           `--> idempotent transaction processor

Protected scheduled job --> retry event processing and reconcile provider state
Browser/App Link return --> Flutter --> authenticated backend status check
```

Use one Supabase Auth user for buying and selling. Seller approval is a separate privileged state. An admin is a separate permission; selecting Seller Center is just navigation.

For version one, checkout contains products from one seller. Use real Xendit test transactions and an explicitly simulated seller earnings ledger. Seller payouts, escrow, withdrawals, and xenPlatform routing are a later integration stage.

## 3. Create the Supabase project

1. Sign in at [Supabase Dashboard](https://supabase.com/dashboard).
2. Create an organization if needed, then a project named `rigmarket-dev`.
3. Choose an available region near your intended Philippine users. Check the dashboard's region choices rather than assuming a particular region is offered.
4. Generate a strong database password and keep it in your password manager.
5. Wait until the database is ready.
6. Open the project's Connect panel or API Keys settings. Record the project URL, project reference, and publishable key.
7. Locate the server secret key or legacy service-role key for backend use only. Do not put it in the mobile configuration.

| Value | Where it belongs |
| --- | --- |
| Project URL: `https://YOUR_PROJECT_REF.supabase.co` | Flutter and backend |
| Publishable key: `sb_publishable_...` | Flutter; access is constrained by RLS |
| Secret key: `sb_secret_...`, or legacy service-role key | Backend only; elevated database access |
| Database password | Password manager/CLI when needed |
| Supabase personal access token | CLI login or protected CI credentials |
| Xendit test secret and webhook token | Supabase Edge Function Secrets only |

Publishable keys are extractable from a built APK. They identify the app, while the signed-in user's JWT identifies the user. The backend must validate that user and their permissions. [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys).

## 4. Configure Authentication

In Authentication settings:

1. Enable email/password sign-up.
2. Keep email confirmation enabled for the hosted project.
3. Configure password rules and review authentication rate limits.
4. Set a real HTTPS Site URL, such as `https://YOUR_HOST.example` after replacing it with your hostname.
5. Add exact allowed redirect URLs for the implemented auth routes, for example:

```text
https://YOUR_HOST.example/auth/callback
https://YOUR_HOST.example/auth/reset-password
```

These routes must be handled by the app or an appropriate hosted fallback. Pass the matching redirect URL in sign-up, resend, and reset-password calls. For development you may separately allow a custom scheme such as `com.yourcompany.rigmarket://auth/callback`; that does not replace Xendit's required HTTPS payment return URLs.

Implement registration with name, email, password, and confirmation in Flutter. Store the password only through Supabase Auth. A trusted signup trigger may create the initial `profiles` record, with no privileged fields copied from user-controlled metadata.

The current app implements sign-in/out, persistent sessions, account verification by email OTP, resend verification, password recovery by email OTP, and password update. Recovery code verification opens the new-password form. External recovery links remain a fallback. Full profile editing and account deletion requests remain planned. Profile deletion must preserve required order/audit records according to your retention policy.

See [Supabase Flutter user management](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter).

### Email delivery

Configure Authentication > Emails > SMTP Settings using your email provider's host, port, username, password, sender email, and sender name. Verify the sending domain and its required DNS records. Turn off email link tracking if it rewrites auth links.

Supabase's built-in sender currently delivers only to organization team addresses and is limited to two emails per hour. Custom SMTP is needed for ordinary test users. Review the email rate limit after configuring SMTP, then test verification and recovery on a physical Android device. [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

### Email OTP for account creation and forgot password

COMPARTS now asks users to enter a **6-digit email code** inside the app. This is email verification, not SMS or authenticator-app MFA. Supabase generates and validates the codes; the app does not store codes in your database or generate its own.

Configure your hosted project before testing:

1. In **Authentication > Sign In / Providers > Email**, keep email sign-ups and **Confirm email** enabled. Without confirmation, Supabase can issue an account session immediately. The app detects this configuration problem during sign-up and signs that session out rather than presenting the account as OTP-verified.
2. Configure custom SMTP with a verified sender in **Authentication > Emails > SMTP Settings**. New free-tier projects created from June 3, 2026 cannot customize auth templates while using Supabase's default SMTP; configuring custom SMTP restores template customization. [Supabase announcement](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier).
3. In **Authentication > Email Templates** (or **Emails > Templates** in the current dashboard), open **Confirm sign up**. Set the subject to `Verify your COMPARTS account`, then paste the complete contents of [confirmation.html](../supabase/templates/confirmation.html) into the body and save.
4. Open **Reset password**. Set the subject to `Reset your COMPARTS password`, paste [recovery.html](../supabase/templates/recovery.html), and save.
5. Both templates must contain `{{ .Token }}`. That placeholder inserts the code; replacing it with a literal example number will break verification. The supplied templates use a code instead of a clickable confirmation URL. [Email template variables](https://supabase.com/docs/guides/auth/auth-email-templates).
6. Set email OTP length to **6**. A suggested expiry is **600 seconds (10 minutes)**. Review the project's email-send and verification rate limits. Supabase's server settings are authoritative. The app's 60-second resend cooldown only improves the user experience; restarting it does not bypass server limits. [Email OTP settings](https://supabase.com/docs/guides/local-development/cli/config#auth.email.otp_length).
7. Build using your real Supabase URL and publishable key as described in [README](../README.md). No email-provider password or admin key belongs in Flutter.

For the Gmail test sender, use these SMTP fields:

| Field | Value |
| --- | --- |
| Sender email address | The Gmail address that sends the codes |
| Sender name | `COMPARTS` |
| Host | `smtp.gmail.com` |
| Port | `587` |
| Username | The same Gmail address as the sender |
| Password | A Google App Password created for that sender account |

The sender needs a Google App Password once; people registering in the APK do
not need App Passwords. In the sender's Google account, enable **2-Step
Verification** through its final **Turn on 2-Step Verification** button. Passing
a Google sign-in prompt alone does not enable it. Then open
[App Passwords](https://myaccount.google.com/apppasswords), create one named
`COMPARTS`, and enter its generated value directly into Supabase's SMTP Password
field. Save the SMTP form and reload it to verify custom SMTP is still enabled.
Do not put the password in chat, source files, or the APK.

If no code arrives, check the exact recipient shown in the APK, the saved SMTP
toggle, and whether the hosted confirmation template contains `{{ .Token }}`.
An already confirmed account should sign in rather than register again.

The app flows are:

| Action | Steps |
| --- | --- |
| Create account | Name/email/password → request confirmation → enter code → verify email → signed in |
| Verify an unfinished registration | Enter email on sign-in → Verify email / resend code → enter latest code |
| Forgot password | Enter email → request reset code → enter code → choose and confirm a new password |
| Resume reset after restarting | Forgot password → enter email → I already have a reset code |

For sign-up verification, the repository calls `verifyOTP` with `OtpType.email`. Recovery uses `OtpType.recovery`, then `updateUser` with the new password after a verified session exists. These use separate OTP purposes; passwordless `signInWithOtp` is not used to create accounts during recovery. [Dart OTP verification](https://supabase.com/docs/reference/dart/auth-verifyotp).

An unknown account receives the same on-screen reset-request message; this avoids exposing whether an email is registered. Invalid or expired codes stay on the verification screen, and a new code can be requested after the cooldown. Do not log codes or put them in route parameters.

An already verified account should use **Sign in** or **Forgot password**.
Supabase may return an obfuscated user with no identities for a duplicate signup;
the APK rejects that response instead of claiming a new verification email was
requested. Signup resends explain that a confirmed account can sign in normally.

For local Supabase only, merge [auth-otp.config.toml.example](../setup/examples/auth-otp.config.toml.example) into the generated `supabase/config.toml`, then restart the local stack. Read emails in Mailpit. Those local template settings and `supabase db push` do **not** configure hosted email templates; paste the HTML into the hosted Dashboard separately. [Local email templates](https://supabase.com/docs/guides/local-development/customizing-email-templates).

Account-dependent checks still to run: real email delivery, correct/incorrect/expired/reused codes, wrong-purpose codes, repeated requests, verification after an app restart, and old/new password sign-in after a reset. Current automated tests mock the network; they do not prove delivery or hosted Auth configuration.

## 5. Database migrations and authorization

Dashboard configuration alone does not create the marketplace backend. Implement versioned SQL migrations, constraints, policies, and transaction functions before checkout.

Use this migration sequence:

| Migration group | Tables / work |
| --- | --- |
| Identity and permissions | `profiles`, `seller_profiles`, `addresses`; add private `admin_memberships`, `seller_private_details`, `account_deletion_requests` |
| Catalog | `categories`, `products`, `product_images`, `product_specifications` |
| Shopping | `wishlists`, `carts`, `cart_items` |
| Orders and stock | `orders`, `order_items`, `inventory_reservations`, `shipments`; add `order_events`, `shipping_rules` |
| Payments | add `payment_sessions` and `checkout_requests`; `payment_attempts`, `payment_events`, `refunds`, `simulated_seller_ledger` |
| Requests | `cancellation_requests`, `return_requests` |
| Reviews | `product_reviews`, `seller_reviews`, `review_images`, `review_replies` |
| Messages and alerts | `conversations`, `conversation_members`, `messages`, `notifications`; add `user_blocks` |
| Administration | `vouchers`, `voucher_redemptions`, `reports`, `audit_logs`; add `marketplace_settings` |

`profiles.id` references `auth.users.id`. Seller records belong to that same user. Products belong to a seller. Orders have a buyer and exactly one seller, with immutable item, address, fee, and policy snapshots. A checkout request owns the idempotency record; an order can have session history, and each session can have several payment attempts. Keep only one unresolved payable checkout for the same order.

Separate public shop details from pickup addresses, contact numbers, and other private seller information. RLS filters rows, not individual confidential columns; use separate tables, column privileges, or carefully designed views for different projections.

### Minimum permission matrix

| Data/action | Guest | Buyer | Approved seller | Admin/backend |
| --- | --- | --- | --- | --- |
| Published products, public shops, eligible reviews | Read | Read | Read | Moderate |
| Profile private data, addresses, cart, wishlist | No | Own only | Own only | Authorized support only |
| Seller onboarding | No | Create/update own allowed fields | Own allowed fields | Approve/suspend |
| Listing publication | No | No | Own, if approved | Moderate |
| Orders | No | Own purchases | Relevant seller projection | Authorized access |
| Shipping details | No | Own orders | Only required fulfillment data | Authorized access |
| Messages and private attachments | No | Participants only | Participants only | Logged moderation access |
| Payment totals, paid status, reservations, refunds, ledger | No write | No direct write | No direct write | Trusted functions only |
| Privileged roles, seller status, audit logs | No write | No write | No write | Trusted admin operations only |

Enable RLS on every exposed table and grant only the operations each role needs. Check both existing-row ownership and new-row ownership for updates. A profile owner must not be able to update their admin role or seller approval state. Do not authorize from user-editable Auth metadata.

Database rules must also enforce positive quantities, nonnegative integer-centavo amounts, valid states, one default address per user, one product review per order item, and one seller review per eligible order. Block self-purchase and self-review on the server.

Use unique constraints for checkout keys, provider session/payment references scoped to environment, event deduplication, voucher use, and notification/ledger effects. Restrict payment RPC execution to the backend, and secure any `SECURITY DEFINER` functions with a fixed `search_path` and explicit execute grants.

[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

## 6. Storage buckets

Create buckets in Storage and implement policies on `storage.objects`.

| Bucket | Visibility | Suggested limit | Rules |
| --- | --- | --- | --- |
| `product-images` | Private staging; publish approved assets separately | 5 MB/image | Seller owns listing; only approved listing assets become public |
| `shop-logos` | Public approved copies or private signed reads | 2 MB/image | Seller owns shop |
| `avatars` | Private unless user explicitly publishes it | 2 MB/image | User owns file |
| `review-images` | Private staging; publish approved review images | 5 MB/image | Eligible review owner |
| `return-evidence` | Private | 5 MB/image | Buyer, relevant seller, authorized admin |
| `message-attachments` | Private; create only if attachments are implemented | 5 MB/image | Conversation participants |

These limits are proposed app defaults. Allow JPEG, PNG, and WebP initially. Validate actual content server-side; a filename or MIME header is insufficient. Use random object names under an owner/listing namespace. Strip unnecessary image metadata before public publication.

Never upload address documents or dispute evidence into a public bucket. Public bucket URLs bypass read access controls; use private objects and short-lived signed URLs for restricted data. Prevent clients from copying unapproved images into the published area. [Storage access control](https://supabase.com/docs/guides/storage/security/access-control).

## 7. Set up Xendit TEST MODE

1. Create an account from [Xendit Dashboard](https://dashboard.xendit.co), using your correct country and account information. New accounts have Test Mode access. [Create account](https://docs.xendit.co/docs/create-account).
2. Select TEST MODE and verify it before generating keys or making requests.
3. Open Settings > Developers > API Keys, or the API Keys screen shown by your dashboard.
4. Generate a secret key for `COMPARTS development`. Grant only needed payment read/write permissions, and refund permissions when refunds are implemented. Store it securely.
5. Open Settings > Webhooks and obtain the webhook verification token.
6. Record your business/account identifier for backend webhook matching.
7. Check that Payment Sessions and your desired Philippine payment flows work for the account. Partner, region, and account restrictions can still affect test flows.

Key behavior: [Xendit API keys](https://docs.xendit.co/docs/api-keys). Dashboard locations and account restrictions: [pre-integration checklist](https://docs.xendit.co/docs/payments-integration-setup).

Start with a small number of supported channels. GCash uses `GCASH`; Maya uses `PAYMAYA`. Only enable them in your integration after checking account availability. Hosted checkout can supply the available selection; avoid hardcoding a promise that every method works. [GCash](https://docs.xendit.co/docs/gcash), [Maya](https://docs.xendit.co/docs/maya).

You do not need a Xendit public key or a Flutter card-entry SDK for this server-created hosted checkout flow. Use the test secret only from Edge Functions.

## 8. Backend configuration and secrets

Copy `setup/examples/edge.test.env.example` to a private ignored file, then fill it in locally or enter the values directly in Supabase Edge Functions > Secrets.

| Setting | Meaning |
| --- | --- |
| `XENDIT_SECRET_KEY` | Test secret from Xendit API Keys |
| `XENDIT_CALLBACK_TOKEN` | Token used to authenticate incoming Xendit webhooks |
| `XENDIT_BUSINESS_ID` | Expected merchant business identifier |
| `XENDIT_ENV` | `test`; backend must enforce this environment |
| `PAYMENT_RETURN_BASE_URL` | Future HTTPS App Link return flow only; unused in the current APK and may remain unset |
| `RECONCILIATION_JOB_SECRET` | Separate random secret checked by the scheduled worker |

These custom names are the application's proposed contract; backend code must explicitly read them. Supabase supplies platform variables such as `SUPABASE_URL` and its documented backend keys. Inspect the variables available in the deployed runtime and choose a supported server credential. Never overwrite platform variables or create custom secrets beginning with `SUPABASE_`. [Edge Function secrets](https://supabase.com/docs/guides/functions/secrets).

The app uses only the project URL and publishable key, as in `setup/examples/mobile.dev.example.json`. Build-time Dart defines are configuration, not secure storage.

## 9. Functions that must be implemented

The current focused APK implements the checkout, webhook, reconciliation,
cancellation and refund functions below, plus `payment-admin`. It does not yet
implement `order-transition` or `seller-admin`. See [the handoff](PAYMENTS_HANDOFF.md)
for deployed behavior and remaining account validation.

| Function | Authentication | Responsibility |
| --- | --- | --- |
| `checkout-quote` | Valid Supabase user | Trusted item prices, shipping and voucher eligibility; return quote/version |
| `checkout-create` | Valid Supabase buyer | Revalidate quote, lock inventory, snapshot order, reserve stock, create/resume session |
| `checkout-status` | Valid user plus order ownership | Read local state; optionally reconcile provider state with rate limiting |
| `xendit-webhook` | Callback token, independent of Supabase user JWT | Persist authenticated events, deduplicate, apply or queue effects |
| `payment-reconcile` | Protected scheduler secret/service credential | Retry inbox processing; fetch unresolved sessions/payments/refunds |
| `order-cancel` | Buyer ownership and permitted state | Coordinate provider cancellation before safe release/refund request |
| `order-transition` | Buyer/seller/admin permissions | Enforce fulfillment, receipt, return, and review eligibility rules |
| `refund-create` | Authorized admin/backend | Full-order refund with local duplicate prevention and provider tracking |
| `seller-admin` | Verified admin membership | Approve/suspend sellers; log changes |

Require server-side user identity checks even when the Edge gateway JWT check is enabled. Never accept a caller-supplied `buyer_id` as identity. For Flutter calls, send the signed-in access token as `Authorization: Bearer <user-jwt>` and the publishable key as `apikey`.

Set `verify_jwt = false` only for the Xendit webhook and a scheduler endpoint that implements its own authentication. Merge `setup/examples/functions.config.toml.example` into the generated configuration; it is not a replacement for the complete file. [Function authentication headers](https://supabase.com/docs/guides/functions/auth-headers).

### Checkout transaction design

1. Identify buyer from a validated Supabase session.
2. Accept product IDs, quantities, address ID, shipping choice, optional voucher code, and a checkout idempotency key. Derive seller and prices from trusted rows.
3. Recheck one-seller scope, seller approval, listing state, self-purchase, address ownership, price version and voucher limits. If the displayed quote changed, return a new quote for confirmation.
4. In one database transaction, lock relevant product/voucher rows in consistent order, calculate totals, create snapshots, allocate voucher capacity, and reserve stock without overselling.
5. Commit the local checkout intent before calling Xendit. Database changes and an external API call cannot be one PostgreSQL transaction.
6. Create the provider session, then persist its ID, returned URL, expiration, expected total/currency, environment, business ID and customer mapping.
7. Duplicate taps resume the stored pending checkout. If the API result is uncertain, keep a `creation_unknown` state and block replacement until reconciliation or manual investigation resolves it.

The current Create Session reference does not document a general idempotency header. A custom header or `reference_id` alone must not be assumed to make retries safe. Implement local uniqueness and serialization. If an ambiguous create response loses the provider ID, investigate using the stored reference and dashboard/support; do not invent a GET-by-reference endpoint or assume elapsed time proves no payment exists.

### Payment Session API contract

Backend request: `POST https://api.xendit.co/sessions`, using HTTP Basic authentication with the secret key as username and an empty password. Configure:

```text
session_type = PAY
mode = PAYMENT_LINK
capture_method = AUTOMATIC
allow_save_payment_method = DISABLED
currency = PHP
country = PH
reference_id = unique stored checkout reference
customer_id = stored Xendit customer, OR customer = validated customer details
success_return_url = HTTPS return route
cancel_return_url = HTTPS return route
```

Use the returned `payment_session_id`, `payment_link_url`, and `expires_at`. A customer object is required unless a valid customer ID is supplied; when creating it, include the required individual details, and persist the resulting customer ID for reuse. [Create Session reference](https://docs.xendit.co/apidocs/create-session).

Store money as integer centavos in PostgreSQL. Convert to PHP major units only at the provider boundary: 125050 centavos represents PHP 1250.50, so the API numeric amount is `1250.5`. Use exact decimal conversion with bounds and two-decimal validation, and normalize incoming amounts back to centavos before comparisons. Confirm the displayed test amount matches the order before recording a successful integration test.

Open the exact returned checkout URL in an external browser or supported browser tab. Show `Test payment — no real charge` in your app and include test wording in the checkout description. [Hosted one-time payment flow](https://docs.xendit.co/docs/payment-1).

## 10. Register and verify webhooks

Deploy the implemented webhook first. Its address will be:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/xendit-webhook
```

In Xendit TEST MODE > Settings > Webhooks, set this endpoint for:

- Payment Session — Completed
- Payment Session — Expired
- Payment status updates for the underlying Payments API version you use
- Unified Refunds — Refund Request Succeeded
- Unified Refunds — Refund Request Failed

Use Test & Save and inspect both Xendit delivery logs and Supabase function/database records. A dashboard test delivery is a connectivity test, not evidence that an order has actually been paid. [Webhook registration](https://docs.xendit.co/docs/payments-integration-setup).

The webhook handler must:

1. Reject a missing or incorrect `x-callback-token`; use a constant-time comparison and never log the token. [Xendit webhook security](https://docs.xendit.co/docs/integration-security).
2. Validate the payload and match business ID, stored provider session/payment references, expected total, currency, and backend environment. Do not assume a test/live flag is present in every payload; separate endpoints/credentials and verify through the matching provider environment where necessary.
3. Persist the verified event in a private durable inbox before returning 2xx. If persistence fails, return an error so delivery can retry.
4. Deduplicate using provider event IDs where available. Where absent, use a stable resource/event transition key; do not depend only on a delivery timestamp. Apply order/stock/ledger/notification effects transactionally and idempotently.
5. Quarantine unknown references or amount mismatches without changing orders. A webhook can arrive before the API response is saved; retain it for later matching.
6. Process supported events, ignore irrelevant events safely, and schedule durable retries for processing failures. Do not depend on an untracked background promise after returning the HTTP response.

Session lifecycle events are `payment_session.completed` and `payment_session.expired`. Store `payment_id` and `payment_request_id` when supplied. [Session webhook schema](https://docs.xendit.co/apidocs/webhook-notification-sent-defined-webhook-url-updates-payment-session).

For automatic PAY sessions, confirm successful collection and matching underlying payment details before moving an eligible order to To Ship. A completed SAVE session or a manual authorization is not collected payment. Underlying payment webhook naming varies by API version; the current Payments API guide includes `payment.capture`, `payment.failure`, `refund.succeeded`, and `refund.failed`. Implement against the actual subscribed schema. [Payments API webhooks](https://docs.xendit.co/docs/payments-api-webhooks), [session versus payment state](https://docs.xendit.co/docs/migrate-to-payment-session).

## 11. HTTPS returns and Android App Links

Host these real routes, with useful browser fallback pages:

```text
https://YOUR_HOST.example/payments/return
https://YOUR_HOST.example/payments/cancel
https://YOUR_HOST.example/auth/callback
https://YOUR_HOST.example/auth/reset-password
https://YOUR_HOST.example/.well-known/assetlinks.json
```

Use an opaque checkout identifier if a return URL needs order context. It is not authorization; the backend still checks ownership. Do not put JWTs, secret keys, addresses, or payment claims in these URLs.

In `android/app/src/main/AndroidManifest.xml`, add the INTERNET permission and an auto-verified HTTPS intent filter for your hostname and implemented routes inside MainActivity. Publish the provided assetlinks template at `/.well-known/assetlinks.json`, replacing its application ID and fingerprint. Use your actual Gradle `applicationId` and the certificate signing the installed APK. Play-installed builds need the Play App Signing certificate fingerprint. Debug and release builds can differ.

Choose a single deep-link owner. If using the `app_links` integration for Supabase auth callbacks, disable Flutter's built-in handler with `flutter_deeplinking_enabled=false`, route payment links explicitly to GoRouter, and handle cold and warm launches. Do not enable competing handlers. [Flutter Android App Links](https://docs.flutter.dev/cookbook/navigation/set-up-app-links).

On either payment return route, refresh order state from the backend. On app restart/resume, also refresh unresolved orders. Closing the browser or reaching the cancel page does not cancel the provider session. Reaching the success page does not mark the order paid.

## 12. Reconciliation, expiration and refunds

Configure Supabase Cron with a proposed initial interval of one to five minutes. Run a protected worker that processes the payment inbox and checks unresolved provider states. Store job credentials in Vault or another protected server location. [Scheduling functions](https://supabase.com/docs/guides/functions/schedule-functions).

Retrieve known sessions through `GET /sessions/{session_id}` from the backend; retain the provider result and apply the same state-transition logic as webhooks. [Retrieve Session](https://docs.xendit.co/apidocs/get-session).

A failed payment attempt can leave the session active. Preserve the reservation while another attempt or in-flight payment can still succeed. A local expiry timer is not enough to release stock. Check provider session and underlying payment-request states, and investigate late-payment races. If stock has already been released and money arrives, record an exception for review/refund instead of silently fulfilling unavailable stock.

Keep payment, fulfillment, cancellation/return, and refund status separate. Sellers may ship paid orders but cannot mark them paid. Buyer receipt/admin resolution determines completion and review eligibility; seller-entered delivery data alone does not.

For full-order refunds, implement a restricted backend call to `POST /refunds` using the stored payment request reference. Record the refund intent before requesting it, block duplicates, and track asynchronous results. Mark refunded only after trusted final confirmation. Restock based on the cancellation/return outcome. Test channel support first; label any unavailable-channel demonstration as simulated. [Refund API](https://docs.xendit.co/apidocs/refund-payment-request), [refund webhooks](https://docs.xendit.co/apidocs/refund-webhook-notification).

## 13. Local tooling and deployment order

These are instructions for the eventual app repository, not commands that have already been run. Do not run `flutter create` over an existing app.

For a new project:

```powershell
flutter doctor
flutter create --org com.yourcompany rigmarket
Set-Location rigmarket
flutter pub add supabase_flutter flutter_riverpod go_router url_launcher
npm init -y
npm install --save-dev --save-exact supabase
npx supabase init
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

Resolve compatible stable Flutter dependencies and commit the app's `pubspec.lock` and CLI package lock. Initialize Supabase with your URL and publishable key using the API supported by the resolved package. [Flutter quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/flutter).

For local Supabase, start Docker and run `npx supabase start`. Local Xendit webhook delivery additionally needs a public HTTPS tunnel; hosted development functions already have public HTTPS endpoints. Never expose your entire database dashboard through the tunnel.

After the migration/function implementation is complete and reviewed:

```powershell
npx supabase db push --dry-run
npx supabase db push
npx supabase secrets set --env-file .env.edge.test
npx supabase functions deploy checkout-quote
npx supabase functions deploy checkout-create
npx supabase functions deploy checkout-status
npx supabase functions deploy xendit-webhook
npx supabase functions deploy payment-reconcile
npx supabase functions deploy order-cancel
npx supabase functions deploy order-transition
npx supabase functions deploy refund-create
npx supabase functions deploy seller-admin
flutter run --dart-define-from-file=config/mobile.dev.json
```

Before those commands, copy the mobile configuration template into `config/mobile.dev.json`, and the server template into `.env.edge.test`; populate them privately. Merge the per-function configuration example into `supabase/config.toml`. A generated empty function scaffold is not a payment implementation.

Then create/configure Storage buckets, verify Auth/SMTP/redirect settings, register Xendit webhooks, enable the protected schedule, and run the checks below. Seed at least three approved seller accounts and twenty products through a development-only process using Supabase Auth/admin APIs for users. Do not seed real passwords in committed SQL. Bootstrap the first admin through a trusted database/admin operation, never a public signup field.

## 14. Acceptance checklist

All items below are pending account setup and implementation; no payment tests have been run by this guide.

- [ ] Registration sends verification; resend and password reset work with non-team addresses through SMTP.
- [ ] Auth and payment links work with the app closed, open, and resumed from the browser.
- [ ] Guests see only approved public information; two users cannot read each other's addresses, orders, messages or evidence.
- [ ] Users cannot approve themselves, become admin, alter totals/paid state, or invoke protected RPCs directly.
- [ ] Only approved sellers publish; suspended sellers cannot start new checkouts.
- [ ] Public image URLs do not expose draft images, private documents or evidence.
- [ ] Self-purchase fails; cart survives login/restart; one-seller checkout leaves other sellers' cart items intact.
- [ ] Price or shipping changes require a refreshed quote and buyer confirmation.
- [ ] Two buyers competing for the last unit cannot both reserve it.
- [ ] Voucher capacity cannot be oversubscribed by concurrent checkouts.
- [ ] Duplicate taps produce one unresolved payable checkout.
- [ ] Provider timeout/uncertain create blocks unsafe replacement.
- [ ] A supported hosted test payment produces a real provider record and authenticated webhook.
- [ ] Pending and failed attempts do not incorrectly cancel the session or release stock.
- [ ] Expiry/cancellation releases stock only after safe provider checks.
- [ ] Closing or killing the app mid-payment recovers the actual state on restart.
- [ ] Success URL alone cannot set paid status; invalid webhook tokens fail.
- [ ] Duplicate, delayed and out-of-order callbacks do not duplicate stock, notifications or ledger effects.
- [ ] Amount/currency/business/environment mismatches are quarantined.
- [ ] Missing webhooks are recovered by the protected scheduled job.
- [ ] Unexpected late payment creates an admin exception.
- [ ] Supported full-order refund remains pending until provider confirmation; duplicates are blocked.
- [ ] Seller shipping is labeled manual; buyer-confirmed completion controls verified reviews.
- [ ] Unpaid/canceled/self-purchased orders cannot generate verified reviews; duplicate order-item reviews fail.
- [ ] Simulated earnings are labeled and cannot be withdrawn.

For channel testing, use the hosted sandbox steps for that channel and the official [test card scenarios](https://docs.xendit.co/docs/cards-simulate-card-scenarios). Test card applicability depends on country and account connection; do not use real card details or assume one card works everywhere.

Where supported, Xendit's test simulation endpoint is `POST /v3/payment_requests/{payment_request_id}/simulate`; it requires the underlying payment-request ID, not the session ID. Its pending response is not proof of success; wait for provider confirmation. Keep simulation tools restricted to development. [Test simulation reference](https://docs.xendit.co/apidocs/simulate-payment-test-mode).

## 15. Common setup problems

| Symptom | Check |
| --- | --- |
| Email address not authorized / email rate exceeded | Custom SMTP, verified sender, Auth email limit |
| Webhook gets 401 before handler logs | Webhook JWT verification is disabled; callback token is validated in code |
| Checkout function gets 401 | User session JWT, correct project, handler identity validation |
| Xendit rejects session request | Test key permissions; customer details; PHP/PH; allowed channel; HTTPS returns |
| App stays in browser | Hosted assetlinks file, application ID, installed signing certificate, domain verification, deep-link listener |
| App shows pending after checkout | Delivery logs, durable inbox, reference matching, processing retries and reconciliation |
| Duplicate payments or refunds | Database idempotency/serialization and uncertain-response handling |
| Unexpectedly huge test amount | Centavos were sent without converting to pesos |
| Data is public unexpectedly | Table RLS/grants, unsafe views, public buckets, or an exposed privileged key |

## 16. Values to prepare

You can share nonsecret project information with the implementer:

- Supabase development project URL/reference and publishable key.
- Final Android application ID.
- HTTPS hostname and intended return routes.
- Desired available test payment methods.
- Initial shipping fees, marketplace rules, and admin account email.

Enter these privately in the appropriate dashboard/secret store:

- Xendit test secret key and callback verification token.
- Supabase backend secret/service-role key and database password.
- SMTP password and Supabase CLI access token.
- Scheduler secret.

Before live payments, use separate production configuration, complete Xendit's current Philippine account verification and channel activation, and confirm your marketplace collection/settlement arrangement with Xendit. Production seller routing and payouts need their own confirmed integration. Account configuration, migrations, functions, Flutter implementation, device testing and genuine Xendit test transactions remain to be completed.
