# COMPARTS 0.4.4 (build 10)

Checkout quantity now has minus/plus buttons and a numeric input, with the
existing limit of 1–20 items. Blank, zero and out-of-range values show an error
and disable order submission. The buttons stop at the minimum and maximum.

Changing quantity fetches a fresh server quote while retaining the address,
payment choice and quantity controls. Order submission waits for that quote;
failed stock/price checks remain visible so the buyer can adjust the quantity
or retry. Totals are hidden while the new quote is pending.

The checkout has a blue gradient product header, white rounded sections for
delivery, payment and order totals, section icons and a soft blue background.
The shared theme uses a soft blue canvas, white cards and brighter blue buttons.

Validation: 48 Flutter tests passed and Flutter analysis reported no issues.
The quantity checks exercise both buttons, direct entry, bounds, pending/failed
quote recovery, preserving address drafts and submitting the selected quantity.

The release APK was installed on the Android emulator. Minus/plus were checked,
then a quantity of 3 was typed for the sample monitor. The hosted quote returned
the correct total of ₱35,985.00 (3 × ₱11,995.00), and the saved delivery address
remained intact. No order was submitted during this UI check. Screenshots:
`build/ui-e2e/checkout-quantity-style.png` and `checkout-quantity-total.png`.

Build command:

```powershell
.\scripts\flutter.ps1 apk -Release -Config config/mobile.dev.json
```

Install `dist/comparts-ecommerce-demo.apk`. Its SHA-256 checksum is in the adjacent
`.sha256` file. This update does not require a database migration.
