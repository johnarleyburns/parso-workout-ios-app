# Phase 0 — Docs & positioning

**Branch:** `phase-0-docs-positioning`
**Depends on:** nothing. Do this first — Phases 1, 4, and 6 build on it.

---

## Problem

The repo tells **three contradictory monetization stories**. The open-source
community you launch to on Hacker News is precisely the audience that will notice,
and "they call it free but paywall the actual product" is the kind of top comment
that defines a launch.

## What the code says today

| File | What it claims | Reality |
|---|---|---|
| `CLAUDE.md` | **Never mentions monetization at all** | The app ships a paid Coach tier |
| `README.md` | "A free, open-source, science-based **strength coach**" | The strength coach is the paid part |
| `docs/app-store/release-checklist.md` | *"Confirm purchases unlock no features"*; lists only the tip jar | Predates the Coach paywall (added 2026-07-03); **contradicts `docs/app-store/metadata.md`**, which documents Cladiron Pro correctly |

Following the release checklist as written, you would answer App Review's
questions **wrong**.

`CLAUDE.md` also advertises features that do not ship (verified against the code):

- **GZCLP and nSuns** — not in `StrengthPresets.all`. They were *deliberately
  removed* for lack of published evidence
  (`plans/field-testing/2026-06-19/01-routine-science-audit.md`, decision R1).
- **HealthKit bodyweight** — `bodyMass` is never read by
  `Services/HealthKitProvider.swift`. (Phase 4 adds it; until then the claim is
  false.)
- **PR timeline** and **consistency heatmap** in the Progress IA — neither exists.
  (Phase 6 adds them.)

---

## Steps

### 1. `docs/COMPETITIVE-ANALYSIS.md`

Already written. Verify it is present and linked from `README.md`.

### 2. `CLAUDE.md` — add a Monetization section

Project memory does not know the app has a paid tier. Add:

> ## Monetization
>
> The tracker is **free forever** — logging, history, Progress, Tests, and export
> are never gated. **Cladiron Pro** gates the Coach's *prescription* (what to do);
> the Coach's *insight* (what it noticed) stays free.
>
> Products: `guru.parso.cladiron.pro.annual` / `.monthly` / `.lifetime`, plus
> tip-jar consumables that unlock nothing. StoreKit 2 only — no RevenueCat, no
> server, no third-party SDKs (this is a privacy requirement, not a shortcut).
> Entitlement resolution lives in `CadenceCore/ProEntitlement.swift`; the gate is
> `CoachSurfacePresenter`, **not** `CoachGate` (which is dead code — Phase 2
> deletes it).

Fix the stale claims in the same pass: remove GZCLP/nSuns from the programs list,
remove "bodyweight" from the HealthKit line, and remove "PR timeline" and
"consistency heatmap" from the Progress IA. Phases 4 and 6 restore the last two
once they are true.

### 3. `README.md` — tell the honest story

Replace the "free, open-source strength coach" framing with:

> The tracker is **free forever** and open source. The **Coach** is a paid
> product. The source is open so you can verify we never track you.

This story is completely defensible — a complete free app plus one honest upsell is
a *better* story than most of the category. It just has to be told consistently.

### 4. `docs/app-store/release-checklist.md`

- Delete *"Confirm purchases unlock no features."*
- Add the three Pro IAPs and the free/Pro boundary.
- Add the App Review note explaining how to reach the paywall: onboarding →
  program preview → "Start training with the Coach".

### 5. `LICENSE` — add a GPLv3 App Store exception

GPLv3 is a known friction with Apple's terms; VLC was pulled from the App Store
over it. `git shortlog -sne` confirms **sole authorship** (John Arley Burns; no
other contributors), so the copyright holder can grant the exception. Without it,
a third party can file a GPL takedown against your *own* listing.

Append to `LICENSE`, and reference it from `README.md` and `TRADEMARKS.md`:

> **App Store exception.** As the sole copyright holder, John Arley Burns
> additionally grants permission to distribute this software through the Apple App
> Store under Apple's standard terms, notwithstanding any conflict between those
> terms and sections 6 and 12 of the GNU General Public License. This exception
> applies only to distribution by the copyright holder.

Keep GPLv3 itself (D8). The fork risk is theoretical; the credibility is real; and
a forked coach without the quarterly research updates decays within two quarters.

---

## Tests

None — documentation only.

## Acceptance

- No file in the repo claims the Coach is free.
- No file claims GZCLP, nSuns, HealthKit bodyweight, a PR timeline, or a
  consistency heatmap exists.
- `LICENSE` carries the App Store exception, referenced from `README.md` and
  `TRADEMARKS.md`.
- `docs/app-store/release-checklist.md` and `docs/app-store/metadata.md` agree
  with each other.

## Commit

```
docs: competitive analysis + one honest monetization story across CLAUDE/README/release-checklist
```
