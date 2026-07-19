# Cladiron App Store Release Checklist

Use this checklist for the first public App Store v1 submission.

## Code Readiness

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
  coaching.
- Confirm `PrivacyInfo.xcprivacy` remains Data Not Collected.
- Confirm tip jar copy says "tip" or "support", never "donation".
- Confirm the free/Pro boundary matches `docs/app-store/metadata.md`: the tracker
  (logging, history, Progress, Tests, export) and the coach's *insights* are free
  forever; **Cladiron Pro** gates only the coach's *prescription*.
- Confirm the three Pro IAPs load and that tip-jar consumables unlock nothing.
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
- Verify the automatic iCloud backup and restore-on-fresh-install path with a
  signed-in iCloud account.
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
  `docs/app-store/metadata.md`, including at least one Apple Watch screenshot
  (required — the archive embeds a watchOS app).
- Set App Privacy to `Data Not Collected`.
- Confirm the privacy policy URL is live and accurate:
  `https://parso.guru/cladiron_privacy`.
- Add review notes from `docs/app-store/metadata.md`.
- Confirm no demo account is required.

## In-App Purchases

- Ensure the Paid Applications agreement, banking, and tax forms are active.
- Create three auto-renewable / non-consumable Cladiron Pro products (the paid
  coach tier):
  - `guru.parso.cladiron.pro.annual` - Cladiron Pro Annual - $79.99/yr, 1-month
    free trial
  - `guru.parso.cladiron.pro.monthly` - Cladiron Pro Monthly - $12.99/mo, no trial
  - `guru.parso.cladiron.pro.lifetime` - Cladiron Pro Lifetime - founding $99.99
    (full price $149.99)
- Create three consumable tip IAP products (unlock nothing):
  - `guru.parso.cladiron.tip.small` - Buy us a coffee - about $1.99
  - `guru.parso.cladiron.tip.medium` - Supporter - about $4.99
  - `guru.parso.cladiron.tip.generous` - Patron - about $9.99
- Add English localizations matching `Cadence/Cadence.storekit`.
- Add a review screenshot for each IAP: the paywall for the Pro products, the
  Support Cladiron screen for the tips.
- Add IAP review notes: Cladiron Pro unlocks the coach's prescription; the tracker
  and the coach's insights stay free. Optional tips unlock nothing.
- Attach all IAPs to the first app version before submission.

### App Review note — how to reach the paywall

The free/Pro boundary: the tracker (logging, history, Progress, Tests, JSON
export/import) and the coach's live *insights* are free forever. **Cladiron Pro**
gates only the coach's *prescription* (program generation, today's exact
set/rep/load, autoregulation, deloads). To reach the paywall: complete onboarding
→ view the generated program preview → tap **"Start training with the Coach"**
(also reachable from the Coach card on Home). Restore Purchases is on the paywall.
A full log → history → export loop works with zero paywall interruptions.

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
- Confirm live IAP products load and at least one real purchase path reaches
  Apple's sheet.
- Confirm the App Store listing does not mention any deferred feature.
