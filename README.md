# COMPARTS for Android

The shop display name is COMPARTS. The existing Android application ID and auth
callback scheme remain `com.rigmarket.rigmarket` so installed app updates and
the configured Supabase callback continue to work.

A Flutter/Dart Android app using Material 3, Riverpod, GoRouter and Supabase.
Cash on delivery, seller dispatch, buyer receipt and purchase reviews are now
available. See [the sample-account guide](docs/COMMERCE_DEMO.md) to try the flow.
This remains a development marketplace with manual courier updates and online
payments in Xendit Test Mode.
The active development project is `qheletzzjnwsjaavbiqc`, with sample buyer and
seller logins and 32 hosted sample items (at least three per category).
Use `dist/comparts-ecommerce-demo.apk` version `0.4.6+13` for this account.
See [connection verification and pending webhook setup](docs/ACCOUNT_CONNECTION_STATUS.md).
See [implementation status](docs/IMPLEMENTATION_STATUS.md) for remaining stages.

## Run on this Windows PC

Flutter is installed at `C:\flutter`. Android Studio, the Android SDK, and the
`Pixel_10_Pro_XL` emulator are also installed.

Open PowerShell in `F:\Aragon pilon`:

```powershell
flutter emulators --launch Pixel_10_Pro_XL
.\scripts\flutter.ps1 run -Device emulator-5554
```

Or connect an Android phone with USB debugging enabled:

```powershell
.\scripts\flutter.ps1 devices
.\scripts\flutter.ps1 run -Device YOUR_DEVICE_ID
```

The wrapper fixes the existing invalid `PUB_CACHE` for its own process and uses
an SDK junction at `F:\RigMarketAndroidSdk` to avoid spaces in the SDK path.
It does not move the installed SDK or change global environment settings.
If PowerShell blocks scripts, use a process-only invocation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\flutter.ps1 run -Device emulator-5554
```

No credentials are needed to explore the preview. Its 20 illustrative listings
are marked as sample data. Purchases and backend mutations are unavailable in
preview; there is no fake sign-in or fake payment-success flow.

## Build an installable APK

```powershell
.\scripts\flutter.ps1 apk
```

Output: `build\app\outputs\flutter-apk\app-debug.apk`.
This APK is signed with the development/debug key, for installation and testing.
Transfer the APK to your phone and open it to install, or use:

```powershell
& 'F:\RigMarketAndroidSdk\platform-tools\adb.exe' install -r .\build\app\outputs\flutter-apk\app-debug.apk
```

For a smaller optimized preview APK:

```powershell
.\scripts\flutter.ps1 apk -Release
```

Output: `build\app\outputs\flutter-apk\app-release.apk`. The delivery copy is
`dist\rigmarket-preview.apk`. It uses the development signing key too; release
build mode does not make this a production-ready or store-signed application.

Flutter is needed on the development PC to edit, run and rebuild the project.
The phone only needs the APK; Flutter is bundled into the application.
Store publication requires your own release signing setup and the remaining
marketplace implementation. The generated release configuration currently uses
the debug key and must be replaced before production distribution.

## Connect Supabase

1. Create a development project and configure email/password Auth and SMTP.
2. Apply `supabase/migrations/202610270001_foundation.sql` through SQL Editor
   or an initialized/linked CLI migration workflow. It creates profiles, public
   seller records, categories, and products with RLS.
3. In Authentication > URL Configuration, allow
   `com.rigmarket.rigmarket://auth/callback`.
4. Copy the configuration template and enter only your URL and publishable key:

```powershell
Copy-Item .\config\mobile.dev.example.json .\config\mobile.dev.json
```

5. Run or build with configuration:

```powershell
.\scripts\flutter.ps1 run -Device emulator-5554 -Config config/mobile.dev.json
.\scripts\flutter.ps1 apk -Config config/mobile.dev.json
```

Sign-up and forgot password now use **6-digit email OTP verification**. Set
**Confirm email** on, configure custom SMTP, and paste the two HTML templates
from `supabase/templates/` into Supabase's **Confirm sign up** and **Reset password**
email templates. Set OTP length to 6; suggested expiry is 600 seconds. See the
[OTP setup instructions](docs/SUPABASE_XENDIT_SETUP.md#email-otp-for-account-creation-and-forgot-password).

Registration opens a code-entry screen before signing in. Forgot password opens
code entry before allowing a new password. Both support resending with a
60-second cooldown and helpful invalid/expired-code errors. Reset requests show
a generic result whether or not an account exists. Sign-in, sign-out and sessions
are managed by Supabase Auth. Real email delivery and hosted configuration still
need testing with your account; preview mode sends no emails.

Configured catalog browsing reads published `products` whose `seller_profiles`
record is approved. A newly migrated project starts with no products or sellers.
The migration deliberately grants no client listing/approval writes; manage test
records through trusted admin access until the seller stage is implemented.
The local sample catalog is never used to hide live query failures.

The foundation stores specifications as JSONB. Category validation, image
management, private seller details and order snapshots belong to later stages.
Future migrations must preserve this schema or migrate the repository queries
together. This is not the complete database from the original requirements.

The APK now includes a persistent cart, single-listing Buy Now, Xendit Test Mode
hosted checkout and order/status screens. The payment tables, secure webhook,
stock reservations, protected reconciliation schedule, unpaid cancellation and
admin refund endpoint are deployed to the linked development project. See
[payment handoff](docs/PAYMENTS_HANDOFF.md) for required Xendit webhook registration,
test accounts, verification and limits. It uses a pickup demonstration with no
real shipping or seller payouts. No separate shopping website is needed. No
Xendit or privileged Supabase key belongs in the Flutter configuration.

## Checks

```powershell
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
```

See [verification results](docs/VERIFICATION.md) for checks actually run.

## Source layout

```text
lib/main.dart                  Startup and optional Supabase initialization
lib/src/core/                  Configuration, branding, theme
lib/src/app.dart               GoRouter and five-tab app shell
lib/src/features/auth/         Repository, controller, account forms
lib/src/features/catalog/      Models, repositories, search, listings, details
lib/src/features/account/      Account and connection instructions
lib/src/shared/                Reusable presentation widgets
supabase/migrations/           Foundation schema and access policies
test/                         Config, catalog, navigation and layout checks
scripts/flutter.ps1           Windows run/build/check wrapper
config/                       Public mobile configuration template
docs/                         Setup, status and verification records
```

Resolved against Flutter 3.47.2 / Dart 3.13.2: Riverpod 3.4.3, GoRouter 18.1.1,
Supabase Flutter 2.18.3 and intl 0.20.3. `pubspec.lock` records exact dependencies.
