# Supporter Flow — Decisions (locked)

_Answered by the maintainer 2026-06-28. Implemented in the same session._

| # | Decision | Answer (verbatim intent) |
|---|---|---|
| D1 | Tiers & prices | **Keep the same**: 3 consumables at $1.99 / $4.99 / $9.99; names "Buy us a coffee" / "Supporter" / "Patron". |
| D2 | Engagement gate | **6 completed workouts** (lowered from 12), still ≥2 sessions, snooze 7 days + 5 launches. → `ContributionPromptEngine.minWorkouts = 6`. |
| D3 | Charity line | **Drop it.** No Internet-Archive / charity framing; pure "support development". |
| D4 | About copy | **Use the proposed wording**: "No subscriptions and no ads. An optional tip jar is the only thing you can buy — and it's never required. …" |
| D5 | Supporter badge | **Settings state only** ("Supporter — Thank You"); no badge toggle, no badge elsewhere. |
| D6 | Prompt placement | **Home only.** The toast is rendered + evaluated only in `HomeView`, gated by `contributionPromptAllowed` (no active workout / start sequence). Not app-wide. |
| D7 | Product IDs | **Confirmed** `guru.parso.cladiron.tip.small / .medium / .generous`. Maintainer wants the exact App Store Connect creation steps → see `02-manual-steps.md` §M3. |
| — | Commit | Commit/merge/push the readiness fixes **after** the supporter code is implemented (done together this session). |

## Implementation note (deviation from `01-code-changes.md`)
- `ContributionCoordinator` **owns** its `ContributionStore` (constructs it in `init`) rather
  than receiving it as a parameter. Reason: a `@MainActor` initializer can't be used as a
  default argument from a nonisolated context (compile error). The app injects only the
  coordinator via `.environment`; Settings/Support read `coordinator.store`. Single shared
  store instance, no `@State`-ordering problem.
