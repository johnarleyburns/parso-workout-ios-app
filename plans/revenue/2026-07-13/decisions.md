# Revenue Plan — Locked Decisions

_Locked 2026-07-13. **Do not re-litigate.** If a phase seems to require breaking
one of these, stop and ask._

| # | Decision |
|---|---|
| **D1** | **Reprice** to $79.99/yr, $12.99/mo, $149.99 lifetime (founding launch price $99.99). Keep the 1-month free trial on annual. |
| **D2** | **The free app stays complete.** Logging, history, Progress, Tests, and export are never gated. The Coach's *prescription* is the only paid surface; the Coach's *insight* stays free. (Unchanged from `plans/monetization-plan.md` §1 — this is exactly what makes a higher coach price defensible rather than greedy.) |
| **D3** | **Bundle exercise images.** No runtime network fetch. NFR-3 ("no-network core") becomes *true*, and a CI guardrail keeps it true. |
| **D4** | **Passive readiness is fusion, not replacement.** Self-report remains authoritative wherever it is present. See below — this one has a subtlety that is easy to get wrong. |
| **D5** | **Data durability = backup/restore of the existing export blob to the user's private CloudKit.** Not full SwiftData + CloudKit live sync. |
| **D6** | **No social feed.** The acquisition loop is a shareable PR card — no account, no server. |
| **D7** | **The Apple Watch app is out of scope** for this plan. |
| **D8** | **Keep GPLv3**, and add an explicit App Store exception to `LICENSE`. |

---

## D4 — read this before writing any Phase 4 code

The obvious version of the passive-readiness recommendation is:

> *"The readiness signal is a self-report survey nobody fills out. Replace it with
> HRV from HealthKit."*

**That is half wrong, and the codebase catches it.**

The coach **already cites `sawMonitoring2016`** — *"Self-reported measures trump
objective monitoring."* Self-report was chosen **because the evidence favors it.**
Under this project's **HARD RULE** (every coaching output must cite navigable
science), you **cannot** ship a coach claim that contradicts a citation the coach
already carries. Doing so would be a correctness bug, not a style disagreement.

The real problem is not that self-report is wrong. It is **compliance** — a survey
only works if it gets filled out, and it mostly will not.

So the design is **fusion**:

- Passive HealthKit signals (HRV, sleep, resting HR) are a **zero-friction prior**,
  always available, requiring nothing of the user.
- **Self-report wins wherever it is present** — exactly as `sawMonitoring2016`
  requires.
- A passive red flag **prompts** the check-in ("your HRV is well below baseline —
  20 seconds to tell the coach how you feel?"), which fixes compliance *without*
  contradicting the science.

This is scientifically honest, it respects the existing citation, and it is the
better product. `ReadinessFusionTests` must contain a test named for this
invariant: **a self-report within the last 24h beats a contradicting passive
signal.**

---

## D1 — why the price goes up, not down

`plans/monetization-plan.md` §2 currently optimizes for undercutting:

> "annual undercuts Fitbod (~$96/yr) ~3x; lifetime undercuts Hevy ($74.99) and
> Strong ($99.99); intro lifetime $49.99 is the cheapest lifetime of any serious
> app in the category."

**That benchmarks Cladiron against loggers. Cladiron is a coach.** Its comparables
are RP Hypertrophy ($299/yr) and JuggernautAI (~$420/yr). Its buyer already pays
for MASS Research Review. In evidence-based fitness, **price is a credibility
signal** — the cheapest serious annual in the category is not a position of
strength when the product's whole claim is rigor.

The arithmetic (`docs/COMPETITIVE-ANALYSIS.md` §2): $100k net needs **~140,000
downloads at $34.99** and **~61,000 at $79.99**. The first number is not reachable
for a new indie app with no paid UA and no ASO history.

And the direction is one-way: **you can always discount later, but you cannot
un-anchor a cheap price.** Raising a public price post-launch reads as a
bait-and-switch, and raising it on existing subscribers requires per-user consent.
Launch high; run a founding-member promotion.

---

## D5 — why backup, not live sync

Full SwiftData + CloudKit sync is the *bigger* feature, but the *problem* is data
loss, not multi-device. Backing up the existing `CadenceExport` v5 `.json.gz` blob
to private CloudKit:

- reuses `DataExport.swift` wholesale,
- leaves the SwiftData schema untouched (no migration risk),
- keeps the **Data Not Collected** label (the data lives in the *user's* iCloud;
  Apple is the processor; you never see it),
- and solves the actual problem.

Live sync stays available later if demand appears. Note that
`CadenceCore/Sources/CadenceCore/Models.swift:22` records *"no
`@Attribute(.unique)` — CloudKit does not support unique constraints"* — **the
schema was deliberately kept CloudKit-compatible**, so that door is still open.
