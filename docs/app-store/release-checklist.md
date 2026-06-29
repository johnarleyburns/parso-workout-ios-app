# Cladiron App Store Release Checklist

Use this checklist for the first public App Store v1 submission.

## Code Readiness

- Confirm app display name is `Cladiron`.
- Confirm the iOS app target is iPhone-only for v1.
- Confirm the app archive does not embed a Watch app.
- Confirm public copy says Apple Watch workouts import from Apple Health after
  recording, but no companion Watch app ships in v1.
- Confirm live heart-rate copy references Bluetooth chest straps for v1.
- Confirm no copy implies generative AI, cloud AI, medical advice, diagnosis,
  treatment, guaranteed results, cloud sync, social features, or nutrition
  coaching.
- Confirm `PrivacyInfo.xcprivacy` remains Data Not Collected.
- Confirm tip jar copy says "tip" or "support", never "donation".
- Confirm purchases unlock no features and product-load failure leaves the app
  fully usable.

## Verification

- Run `cd CadenceCore && swift test`.
- Run a Release build/archive for the `Cadence` iOS scheme.
- On a real device, verify HealthKit permission priming and authorization.
- On a real device, verify Apple Health workout import.
- On a real device, verify saving a strength workout summary to Health.
- On a real device with hardware available, verify Bluetooth chest-strap pairing
  and live heart-rate capture.
- Verify outdoor GPS workout recording and Health save.
- Verify JSON export/import round-trip with non-empty strength, cardio,
  assessment, and preference data.
- Verify StoreKit local products using `Cadence.storekit`.
- Verify sandbox StoreKit products with the local StoreKit config disabled.
- Verify the app behaves correctly when StoreKit products are unavailable.

## App Store Connect

- Create or confirm the app record:
  - App name: `Cladiron`
  - Bundle ID: `guru.parso.ios-workout-app`
  - Platform: iOS
  - SKU: `cladiron-ios-v1`
  - Price: Free
- Fill App Information from `docs/app-store/metadata.md`.
- Upload final screenshots using the screenshot storyboard in
  `docs/app-store/metadata.md`.
- Set App Privacy to `Data Not Collected`.
- Confirm the privacy policy URL is live and accurate:
  `https://parso.guru/cladiron_privacy.html`.
- Add review notes from `docs/app-store/metadata.md`.
- Confirm no demo account is required.

## In-App Purchases

- Ensure the Paid Applications agreement, banking, and tax forms are active.
- Create three consumable IAP products:
  - `guru.parso.cladiron.tip.small` - Buy us a coffee - about $1.99
  - `guru.parso.cladiron.tip.medium` - Supporter - about $4.99
  - `guru.parso.cladiron.tip.generous` - Patron - about $9.99
- Add English localizations matching `Cadence/Cadence.storekit`.
- Add a review screenshot for each IAP showing the Support Cladiron screen.
- Add IAP review notes: optional tips unlock no features or content.
- Attach all three IAPs to the first app version before submission.

## Screenshot Data

Seed screenshots with realistic data:

- Coach's Pick with a clear reason and at least one ruled-out alternative.
- Strength session with previous set context and a PR or near-PR.
- Progress dashboard with non-empty trends.
- Citation detail opened from a coach output.
- Backup & Restore or About privacy section.
- Support Cladiron screen with products loaded.

Do not show:

- Debug launch arguments or test identifiers.
- Placeholder product unavailable state in the final screenshot set.
- Watch companion UI.
- Medical claims or guaranteed outcomes.

## Post-Approval Smoke Test

- Install the live App Store build on a clean device.
- Confirm onboarding, Health permissions, logging, export, and support screen.
- Confirm live IAP products load and at least one real purchase path reaches
  Apple's sheet.
- Confirm the App Store listing does not mention any deferred feature.
