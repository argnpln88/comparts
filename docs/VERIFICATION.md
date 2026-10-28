# Verification record

Date: October 27, 2026. Current delivery: version 0.2.0, including email OTP flows.
Network-mocked Auth checks do not establish that a hosted project sends emails.

## Passed

- Flutter dependency resolution with Flutter 3.47.2 stable and Dart 3.13.2.
- `scripts/flutter.ps1 analyze`: no issues found.
- `scripts/flutter.ps1 test`: all 20 tests passed.
  - Empty/partial configuration handling.
  - Backend secret/service-role credential rejection.
  - HTTPS URL and post-login destination validation.
  - Email/password validation.
  - Sample catalog category coverage and pagination.
  - Combined search, category, condition and sorting.
  - Live-query failures never substitute preview records.
  - Product lookup and centavo display.
  - Phone navigation, categories, authentication entry and setup instructions.
  - Enlarged-text home layout at 1.8 scaling.
  - Sign-up requests a code and only navigates after successful verification.
  - Invalid/expired and malformed codes prevent recovery completion.
  - Recovery updates require the verified user session, and cannot be repeated
    using the controller's consumed recovery authorization.
  - Wrong-session and signup-only verification cannot authorize recovery updates.
  - Resend cooldowns and purpose-specific recovery resend behavior.
  - Real Supabase SDK requests use `email` verification for signup and `recovery`
    for password reset; sessionless responses are rejected.
  - Unexpected auto-confirmed signup sessions are signed out with a configuration error.
  - Network-mocked widget tests exercise signup code entry, errors and intended
    destination, and recovery code entry, password confirmation and update.
  - A regression test emits the real SDK recovery event and confirms it does not
    redirect away from the in-app new-password form.
- Validated both email template paths, `{{ .Token }}` placeholders, and local
  TOML confirmation/OTP settings. Hosted templates were not modified.
- Earlier foundation check: `scripts/flutter.ps1 apk` built a debug APK.
- Earlier foundation check: `scripts/flutter.ps1 run -Device emulator-5554` launched on the
  Pixel 10 Pro XL emulator running Android 17.
- Visually inspected emulator screenshots for home, product detail and account:
  `screenshots/home.png`, `screenshots/product.png`, `screenshots/account.png`.
- `scripts/flutter.ps1 apk -Release`: optimized universal APK built successfully.
- Verified packaged native code includes `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Installed the updated optimized APK on the emulator and launched version
  0.2.0 successfully. The stored UI screenshots show the earlier 0.1.0 catalog.

Delivery: `dist/rigmarket-preview.apk`, 56,537,901 bytes (about 53.9 MiB).
This is a development-key-signed preview even though it uses release build mode.
SHA-256: `8ad4a5debddc0e9c7f526d5956a2527d6107b803e1a0753c0e8957263e3b4747`.
The checksum is also recorded in `dist/rigmarket-preview.apk.sha256`.

## Build fixes applied

The host's inherited PUB_CACHE pointed to a nonexistent D: drive. The Windows
wrapper uses a valid cache for its process when that drive is unavailable.
It also aliases the existing Android SDK through a junction without spaces;
the original SDK installation is not moved.

Kotlin's incremental cache failed to relativize source paths across the F: project
and C: package cache. `kotlin.incremental=false` in the project's Gradle settings
resolved that observed failure. It can make Kotlin recompilation slower.
See [Kotlin compilation/cache settings](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).

Initial layout tests found unconstrained text in two horizontal rows. The rows
were corrected and both phone-layout tests then passed.

The OTP regression test caught delayed SDK recovery events redirecting to the
external-link password screen. The routing guard now remains active while the
verified recovery flow awaits password update. Tests then passed. SDK PKCE
storage and JSON-isolate lifecycle are modeled correctly in the mocked test harness.

## Not tested / not implemented

- No Supabase cloud project was connected or modified.
- The foundation SQL migration has not been executed against PostgreSQL.
- No live registration, email delivery, verification/recovery callback,
  session persistence, RLS or Storage integration test was run.
- No physical Android phone or release signing certificate was tested.
- No Xendit transaction, webhook, payment reconciliation or refund was run.
- Cart/order/seller/review/message/admin/payment implementations and their
  required security and concurrency checks remain in the stage checklist.

Build instructions follow [Flutter Android deployment](https://docs.flutter.dev/deployment/android).
Current dependency APIs were checked against the official package pages for
[Riverpod](https://pub.dev/packages/flutter_riverpod),
[GoRouter](https://pub.dev/packages/go_router), and
[Supabase Flutter](https://pub.dev/packages/supabase_flutter).
