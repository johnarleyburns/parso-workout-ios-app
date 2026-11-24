# Cladiron App Store Release Checklist

Use this checklist for the first public App Store v1 submission.

## Code Readiness

- App Store submission is local-only: the app has no iCloud entitlement and no
  CloudKit code or UI. Keep it that way unless a health-data-separated sync
  design lands (Guideline 5.1.3(ii)).
- Delete the legacy CloudKit container `iCloud.guru.parso.cladiron.sync` (or
  its health-bearing record types) in CloudKit Console before public
  submission so no previously mirrored health data remains in iCloud.

- Confirm app display name is `Cladiron`.
- Confirm the archive embeds the `Cadence Watch App` and both binaries pass
  App Store validation.
- Confirm public copy matches the shipped Watch app (phone-free strength with
  partners, HIIT/boxing rounds, cardio suite, live wrist HR, Health save +
  phone sync).
- Confirm live heart-rate copy references Bluetooth chest straps (iPhone) and
  wrist heart rate (Watch).
- Confirm no copy implies generative AI, cloud AI, medical advice, diagnosis,
  treatment, guaranteed results, cloud sync, social features, or nutrition
  coaching. The submission build is local-only; use on-device/export language.
- Confirm `PrivacyInfo.xcprivacy` remains Data Not Collected and declares the
  required reasons actually used (UserDefaults + FileTimestamp `3B52.1` on the
  iPhone; UserDefaults + SystemBootTime `35F9.1` on the Watch).
- Confirm `NSLocationAlwaysAndWhenInUseUsageDescription` is present and the
  outdoor-workout flow requests Always only after the user starts a workout.
- Confirm `remote-notification` is absent from `UIBackgroundModes`.
- Confirm contribution copy says "support" or "contribute", never "donation".
- Confirm all planning, coaching, logging, export, and execution surfaces remain
  available without a purchase.
- Confirm third-party content attribution and content-rights answers: exercise
  data/images from free-exercise-db (CC0) and Wikimedia assets (CC BY-SA) are
  attributed in About; no unlicensed third-party media is shipped.
- Confirm the single optional $9.99 contribution loads and unlocks nothing.
- Confirm product-load failure leaves the free app fully usable.

## Verification

- Run `swift test --package-path CadenceCore`.
- Run a Release build/archive for the `Cadence` iOS scheme.
- On a real device, verify HealthKit permission priming and authorization.
- On a real device, verify Apple Health workout import.
- On a real device, verify saving a strength workout summary to Health.
- On a real device with hardware available, verify Bluetooth chest-strap pairing
  and live heart-rate capture.
- Verify outdoor GPS workout recording and Health save.
- On a real Apple Watch: verify a phone-free strength session, live wrist HR,
  Health save (rings credit), and auto-ingest back to the phone.
- Verify the on-device store survives relaunch and that JSON export/import
  restores a fresh install.
- Verify JSON export/import round-trip with non-empty strength, cardio,
  assessment, and preference data.
- Verify StoreKit local products using `Cadence.storekit`.
- Verify sandbox StoreKit products with the local StoreKit config disabled.
- Verify the app behaves correctly when StoreKit products are unavailable.

## Identifiers, provisioning, and certificates after removing iCloud

Do this once in the Apple Developer portal and CI before the first local-only submission:

- App ID `guru.parso.ios-workout-app`: remove the **iCloud/CloudKit** capability
  and the `iCloud.guru.parso.cladiron.sync` container association.
- Regenerate the **App Store distribution provisioning profile** for that App ID
  and replace the CI secret `PROVISIONING_PROFILE_BASE64`. The Apple
  Distribution certificate, APNs key, App Store Connect API key, Watch/widget
  profiles, App Group, bundle IDs, HealthKit capability, and StoreKit product
  do not need to change.
- In CloudKit Console / App Store Connect, delete the legacy container
  `iCloud.guru.parso.cladiron.sync` (or its health-bearing record types) after
  removing it from the App ID. This removes previously mirrored data from
  iCloud; local device data is unaffected.
- If a CloudKit management token (`~/.cloudkit-management-token`) was used for
  the old schema check, revoke/rotate it. That check has been removed from the
  repo.

## App Store Connect

- Create or confirm the app record:
  - App name: `Cladiron`
  - Bundle ID: `guru.parso.ios-workout-app`
  - Platform: iOS
  - SKU: `cladiron-ios-v1`
  - Price: Free
- Fill App Information from `docs/app-store/metadata.md`.
- Upload final screenshots using the screenshot storyboard in
  `docs/app-store/metadata.md`, including at least one Apple Watch screenshot
  (required — the archive embeds a watchOS app) and the iPad screenshots the
  universal target requires.
- Set App Privacy to `Data Not Collected`.
- Confirm the privacy policy URL is live and accurate:
  `https://johnarleyburns.github.io/parso-workout-ios-app/` (published from this repo's
  `gh-pages` branch). Remove stale iCloud/microphone claims; this build stores
  training data on device and does not use the microphone.
- Add review notes from `docs/app-store/metadata.md`.
- Confirm no demo account is required.

## In-App Purchases

- Ensure the Paid Applications agreement, banking, and tax forms are active.
- Create one consumable IAP (unlock nothing):
  - `guru.parso.workout.support.dev` - Contribute to development - $9.99
- Add the English localization matching `Cadence/Cadence.storekit`.
- Add a review screenshot for the Support Cladiron screen.
- Add IAP review notes: the contribution is optional, all app features remain
  available without purchase, and a successful purchase only adds the Home
  Supporter badge.
- Attach the contribution IAP to the first app version before submission.

### App Review note — optional contribution

The complete app is usable without purchase, including planning, coaching,
logging, history, export, and Watch execution. The Support Cladiron screen is
reachable from Settings and Home. A successful $9.99 contribution only records
supporter status and displays a Supporter badge on Home; it unlocks nothing.

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
- Medical claims or guaranteed outcomes.

Watch screenshots must be captured from the real watch UI (watchOS simulator or
device), per the storyboard in `docs/app-store/metadata.md`.

## Post-Approval Smoke Test

- Install the live App Store build on a clean device.
- Confirm onboarding, Health permissions, logging, export, and support screen.
- Confirm the live contribution IAP loads and the purchase path reaches Apple's
  sheet without changing feature access.
- Confirm the App Store listing does not mention any deferred feature.
