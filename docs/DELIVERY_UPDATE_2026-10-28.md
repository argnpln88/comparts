# COMPARTS 0.4.3 (build 9)

The app payment method now reads **Online payment**. Payment status is visible
separately from delivery status, including **Paid** after backend confirmation.
The existing Xendit credentials remain in Test Mode; Xendit's own hosted page
can still display its test-environment labels. App wording does not enable live
collections or seller payouts.

Checkout supports a private saved delivery address, **Use current address**,
**Update address**, and **Save delivery address**. Recipient, contact number,
house/street/barangay, city/municipality/province and postal code are validated.
The sample buyer has a fictional address in Quezon City with postal code 1100.
Current address means the account's saved address, without GPS lookup.

Completed purchases support up to three public item-review photos, from camera
or gallery, each JPG/PNG/WebP under 3 MB. The buyer sees thumbnails and can remove
draft photos before submission. Upload failures preserve the draft for retry.
Uploaded photos cannot be replaced or deleted by client accounts. A sample
storage-item review has an explicitly identified illustration.

Deployed migration: `202610280009_addresses_review_photos.sql`.
Deployed function: `commerce-order`.
Provisioning and hosted checks: `node scripts/catalog-delivery-update.mjs` and
`node scripts/catalog-delivery-update.mjs verify`.

The hosted catalog contains 22 published items: two each in CPUs, motherboards,
graphics cards, RAM, storage, power supplies, cases, coolers/fans and monitors,
plus four peripherals. Fourteen new items were added; existing product and
historical order records were retained.

Validation:

- 46 Flutter tests passed, including address draft preservation during a slow
  saved-address fetch, saved-address editing/reuse, captured-photo submission,
  payment confirmation badges, and existing auth/order/navigation behavior.
- Flutter analysis passed with no issues.
- Nine Deno payment-policy/reconciliation tests passed.
- Deno type-check passed for the deployed `commerce-order` function.
- Hosted checks passed for all category counts, private address access,
  invalid-address rejection, public review photos, order-detail photo projection,
  rejection of direct review writes and foreign-order photo references, and
  denial of anonymous, unrelated-user, unreceived-order and post-review uploads.
- The release APK was installed and launched on the emulator. Its saved-address
  card, editable address fields, Online payment selector, Paid badge, order-list
  statuses, sample review thumbnail and full-size photo dialog were checked.
  Screenshots are in `build/ui-e2e/updated-online-checkout.png`,
  `updated-delivery-fields.png`, `updated-paid-review.png` and
  `updated-review-photo.png`.

Delivery: `dist/comparts-ecommerce-demo.apk`, with its SHA-256 checksum alongside.
Camera behavior on a physical phone and a completed hosted Xendit collection
were not exercised in this update.
