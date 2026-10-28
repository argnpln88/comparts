# New account connection — 2026-10-28

Target Supabase project: `qheletzzjnwsjaavbiqc` (`argnpln88's Project`, Comparts).
Account email: `aragonpilon88@gmail.com`.

Completed in the target project:

- All nine repository migrations, through `202610280009`, are applied and recorded.
- All nine Edge Functions are deployed and active. JWT settings match `supabase/config.toml`.
- Email confirmation is required; email OTPs are six digits with a 600-second expiry.
- Backend database access and the commerce privilege assertions passed.
- A seven-day, project-scoped deployment token was created with the owner's approval.
- A new Xendit Test Mode key with Money-in Write permission was created with approval.
- The new Xendit key created a PHP 100 test session, which was canceled without collecting payment. The returned business ID is recorded privately.
- Gmail SMTP, both exact OTP templates, and the Android callback URL are saved.
- Gmail accepted the supplied App Password in a direct authentication probe (235). A separate Supabase signup test returned HTTP 200 and recorded confirmation_sent_at for the owner's connection-test alias. The owner confirmed receiving the six-digit signup email on 2026-10-28; no OTP was read or stored.
- The active local configuration now targets this project. Previous local fixtures and configuration were backed up in an ignored account backup.
- Five isolated sample/test accounts can sign in with matching profiles and avatars, including two approved demo shops.
- The public catalog has 32 illustrated sample products: three per category, plus two payment-test products in Peripherals (five there).
- All 13 sample image objects and all 32 product image URLs passed public download checks. Client uploads to the sample-media bucket are denied.
- COD checkout, dispatch, receipt, reviews, cancellation, saved-address privacy, and review-photo guards passed hosted tests.
- Online checkout, retry idempotency, Xendit-confirmed cancellation, and stock restoration passed on the new project.
- The protected reconciliation schedule runs every two minutes; recent responses are HTTP 200 without timeouts.
- Hosted payment transaction/RLS and commerce permission tests passed.
- APK version `0.4.6+13` was rebuilt with the new configuration as `dist/comparts-ecommerce-demo.apk`.
- The APK was installed and launched on the Pixel emulator. Its live catalog loaded, buyer and seller UI sign-ins succeeded, and Seller Center loaded the new project's orders (one ready to ship and two completed).
- Public catalog pagination was checked: 20 first-page items and 12 second-page items, without overlap. See `build/connection-catalog-verification.json`.

Still pending:

- Retrieve the Xendit webhook token and register webhooks. Its password-confirmation prompt needs the owner. No callback token is configured, so webhook requests cannot authenticate yet.
- Test actual provider-confirmed collection/refund behavior. Test-session creation/cancellation does not prove collection or refunds. Signup inbox delivery is confirmed; completing password recovery remains a separate test.
- A physical-phone check remains separate from the successful emulator check.

The active configuration and rebuilt ecommerce APK use `qheletzzjnwsjaavbiqc`.
Older APKs under other filenames may still use `mosmaxlegakexjutqeaa`.
No old project data or credentials have been deleted or revoked.

Local secrets are in ignored `.env.account-connection.json`. They are not copied to
Flutter or this document. The new deployment token expires after seven days and
must be renewed for later deployments; its expiry does not stop deployed functions.
The token intentionally cannot update hosted Auth through the Management API,
which also requires `project_admin_write`. Those changes are being made in the
signed-in dashboard instead.

Read-only status:

```powershell
node scripts/account-connection.mjs plan
node scripts/account-connection.mjs audit
node scripts/account-connection.mjs health
```

After activation, `scripts/supabase.ps1` and the repository's Node helpers use
the new project token for their own processes. The global Supabase CLI identity
is not replaced: Supabase CLI login accepts user-scoped tokens, whereas this
deployment token is restricted to one project.

Checks completed during this change: 52 Flutter tests passed, Flutter analysis
reported no issues, nine Deno tests passed, and hosted commerce permissions passed.
