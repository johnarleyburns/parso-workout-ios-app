# Monetization — Manual Test Matrix

StoreKit behaviour that can't be verified headlessly. Run on device/simulator with
the `Cadence.storekit` configuration bound to the **Run** scheme
(Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration →
`Cadence.storekit`), or with sandbox testers on device (plan §8.3).

## Automated coverage (no manual step needed)

- `swift test` — `ProEntitlementTests` (18): lifetime, active sub, trial, expired,
  revoked/refunded, upgraded, family-shared, offline-cache staleness, Codable.
- `swift test` — `CoachKnowledgeBaseTests` (3): KB loads, version matches newest
  entry, every changelog citation resolves.
- UI (`MonetizationUITests`): free preview shown, paywall opens with Restore, free
  logging loop uninterrupted, Pro sees the full Coach card.

## Manual matrix

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1 | Products render | Open paywall | Annual (pre-selected, "30 days free"), Lifetime ("Founding price", $49.99), Monthly shown with correct prices |
| 2 | Buy annual (trial) | Purchase annual | Trial starts; Coach unlocks; Home shows "Trial — X days left"; Settings shows "Trial — Xd left" |
| 3 | Trial reminder | Set StoreKit time rate / advance | Local notification fires ~3 days before trial end (provisional, quiet) |
| 4 | Buy monthly | Purchase monthly | Coach unlocks immediately; no trial banner |
| 5 | Buy lifetime | Purchase lifetime | Coach unlocks; Settings shows "Lifetime"; survives app relaunch |
| 6 | Restore | Fresh install → Restore Purchases | Entitlement restored from account |
| 7 | Expired sub | Let subscription expire | Coach re-locks; preview + paywall return |
| 8 | Refund / revoke | Refund via StoreKit Transaction Manager | Coach re-locks on next refresh |
| 9 | Ask to Buy (pending) | Enable Ask to Buy, purchase | "Purchase pending" alert; unlocks after approval |
| 10 | Family Sharing | Purchase lifetime/annual on family account | Shared member gets Pro (ownershipType == .familyShared) |
| 11 | Offline cold launch | Subscribe, enable Airplane Mode, relaunch | Pro stays unlocked from cache (≤30-day ceiling); never locks mid-workout |
| 12 | Sub → lifetime | With active sub, buy lifetime | Lifetime purchase allowed; post-purchase notice about cancelling the sub in Settings |
| 13 | Free loop | Free user: log → history → export | Zero paywall interruptions; export works |
| 14 | Onboarding funnel | Complete onboarding | Program preview shown before paywall; "Maybe later" enters the free app |
| 15 | KB "New" badge | Bump KB version, reinstall | "New" badge in Settings → clears after viewing Coach Research Updates |

## Notes

- Non-consumable lifetime has no App Store "introductory offer"; the $49.99 founding
  price is the launch price with a scheduled change to $69.99 at day 60 (plan §8.4).
- One intro offer per Apple ID per subscription group is enforced by Apple.
