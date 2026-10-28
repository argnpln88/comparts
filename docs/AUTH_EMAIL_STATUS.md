# Auth email setup status

Updated 2026-10-28 for COMPARTS.

The active app now uses `qheletzzjnwsjaavbiqc`. Gmail SMTP, both exact OTP
templates, six-digit/600-second settings, and the Android callback are saved.
The new App Password authenticated with Gmail (235). A Supabase signup test
returned 200 and advanced confirmation_sent_at. The owner confirmed receiving
the six-digit signup email on 2026-10-28; the OTP was not read or stored.
See [current account status](ACCOUNT_CONNECTION_STATUS.md). Earlier delivery
failures and recovery history below refer to the previous project.

## Current signup delivery blocker

The latest failed signup was traced to a Gmail SMTP rejection in hosted Auth
logs: status **534 / 5.7.9 / WebLoginRequired**, asking the sender to sign in
through a web browser. The intended new account was not created. This is a
sender-account delivery failure; it is not evidence of a bad recipient address.

Read-only checks confirmed the APK still matches the linked project, signup
and email confirmation are enabled, SMTP is configured for smtp.gmail.com:587,
the confirmation template includes `{{ .Token }}`, and OTP length/expiry remain
6 digits / 600 seconds. A fresh local SMTP authentication-only probe disconnected
without sending a message. It did not establish a working SMTP connection.

The Gmail sender's owner must sign in and complete Google's security prompts.
If the App Password is no longer valid, the owner must enter its replacement
directly in Supabase Authentication > Emails > SMTP Settings > Password.
No new App Password should be pasted into chat, repository files or the APK.
See [Google's App Password instructions](https://support.google.com/mail/answer/185833?hl=en).

Version 0.4.5 (build 11) explains email-service failures and throttling without
showing raw JSON. Failed requests stay on signup and do not start the resend
cooldown or advance to code verification. The app change does not remove the
Gmail block, and current signup inbox delivery remains unverified.
All 52 Flutter tests passed, including raw JSON email failures, retry after a
failed send, resend throttling, and the signup screen remaining on the form.
Flutter analysis reported no issues.

Read-only diagnostic commands:

```powershell
node scripts/inspect-auth-delivery.mjs
node scripts/inspect-auth-delivery.mjs --smtp-probe
node scripts/check-auth-email.mjs --email YOUR_INTENDED_EMAIL --connection
```

The helper uses the existing Supabase CLI identity, redacts log details and
keeps credentials in memory. It does not create users, send an email or change
SMTP settings. Recheck the provider after the sender owner clears the block;
only then test the intended signup and actual inbox delivery.

## Earlier configuration and recovery checks

Gmail SMTP is now saved and enabled in hosted Supabase. The dashboard reported
"Successfully updated settings". Reloading an independent SMTP tab confirmed
the enabled toggle, COMPARTS sender name, smtp.gmail.com host, port 587, intended
sender username, and stored hidden password. The account owner enabled Google
2-Step Verification and created the App Password used for this configuration.
An independent SMTP connection to Gmail on port 587 negotiated STARTTLS and
successfully authenticated (SMTP status 235). That probe sent no message.

Both hosted email templates now use the supplied COMPARTS HTML and subjects:
`Verify your COMPARTS account` and `Reset your COMPARTS password`. The complete
editor contents matched the local files before saving (ignoring the final
newline). Reloaded pages confirmed the saved subjects and bodies containing
`{{ .Token }}`. The original link-only templates have been replaced.

Hosted settings were corrected to six-digit OTPs with a 600-second expiry,
email confirmation enabled, and the Android auth callback URL allowed. These
changes do not require rebuilding the APK. Local Auth configuration now uses the
same OTP length/expiry and the supplied confirmation/recovery templates.

Actual password-reset OTP delivery is now verified. At the user's explicit
request, the diagnostic helper sent one recovery request to the confirmed sample
account. Supabase returned HTTP 200, the account's recovery_sent_at advanced to
2026-10-27T19:18:46.793286Z, and the recipient confirmed receiving an email with a
six-digit code. No password was changed and no OTP was read or recorded.

A new-account signup delivery test remains separate from that successful
recovery test. The alternative sample address checked earlier had no registered
account. Existing confirmed accounts can sign in normally. Do not rename,
delete, preconfirm, or substitute another account for an intended recipient.

The sender needs SMTP credentials once. Recipients registering in the APK do
not need Google App Passwords. The recipient entered in the APK must match the
inbox being checked. No mail credential is stored in repository files or the APK.
An accepted resend response is not proof of inbox delivery; the recipient must
confirm receipt and enter the code in the APK themselves.

For the already-confirmed sample account, a read-only connection check verified
the APK build configuration matches the linked project URL and public key.
Hosted Auth settings responded HTTP 200, with email enabled and automatic email
confirmation disabled. A confirmed account should sign in with its password;
the signup resend endpoint does not represent a new pending verification.

The APK now rejects Supabase's obfuscated duplicate signup response (a user with
an empty identities list) instead of opening an OTP screen and implying a new
email was requested. Signup resend copy also explains that an already verified
email should sign in. Regression tests cover both that response and a normal
pending signup with an email identity. The recipient subsequently selected the
recovery-delivery test and confirmed receipt of the six-digit email. Sending the
reset code did not change the password or complete a recovery session.

The diagnostic helper requires an explicit recipient for any resend:

```powershell
node scripts/check-auth-email.mjs --email YOUR_INTENDED_EMAIL
node scripts/check-auth-email.mjs --email YOUR_INTENDED_EMAIL --resend
node scripts/check-auth-email.mjs --email YOUR_INTENDED_EMAIL --connection
# Only when the recipient explicitly wants a password-reset code:
node scripts/check-auth-email.mjs --email YOUR_INTENDED_EMAIL --recover
```

The helper never creates an account, confirms an email, or prints an OTP. A
missing pending account means registration is needed first; it does not justify
reusing another account's email or credentials.
