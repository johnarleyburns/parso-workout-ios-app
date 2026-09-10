# Revision notes — Cladiron Platform Spec v1.0 → v2.6

**v1.0:** `docs/plans/cladiron-mvp/CLADIRON_PLATFORM_SPEC.md` (3,250 lines)
**v2.5:** `docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md` + 64 mockups
**v2.6:** scope correction recorded 2026-09-09
**Date:** 2026-08-10 (v2.0/v2.1), 2026-08-11 (v2.2), 2026-09-02 (v2.3–v2.5 reconciliation), 2026-09-09 (v2.6 scope correction)

This file is the diff. Read it before the spec if you already know v1.0; skip it otherwise. §00000 protects the shipped training loop in v2.5, §0000 covers universal external-client delivery in v2.4, §000 covers the v2.3 reconciliation, §00 covers the v2.2 decision closure, §0 covers the v2.0 → v2.1 Mac amendment, and §1 onward is the v1.0 → v2.0 diff except where an earlier section supersedes it.

---

## 000000. v2.5 → v2.6 — self-planned, automated-coach-only scope (2026-09-09)

This is the active product correction. It supersedes the trainer/client and Pro
commercial model from v2.5; the older sections remain only as historical
decision context and are not implementation requirements.

- Cladiron has no personal-trainer role, client role, Trainer mode, roster,
  invite/accept flow, CKShare delivery, external-client packet, or human-coach
  result review. The only planning author is the individual user.
- The automated scientific coach may generate, critique, progress, substitute,
  and explain suggestions. The user accepts or edits them; the software is not
  a human coach and never silently mutates the user's plan.
- There are no gated Pro features, Pro entitlement, trial, paywall, or
  Universal Purchase requirement. Core planning, automated coach assistance,
  templates, insights, execution, history, export, partners, and readiness are
  available without purchase.
- The only purchase is an optional **$9.99 “Contribute to development”**
  consumable. A successful transaction adds a **Supporter** badge to Home and
  unlocks nothing else. It is not a feature gate or a subscription.
- Private iCloud remains for the user's own devices. The active roadmap is
  manual self-planning → automated coach depth → optional Supporter handling →
  platform/readiness polish. Trainer/client/Mac-workbench work is retired.

---

## 00000. v2.4 → v2.5 — plan onto the proven training loop (2026-09-02)

This revision follows the implementation and commit history, especially the
DB++ adoption series, partner/set-entry remediation, and Watch/cardio field-test
batches. It makes their shipped behavior a normative constraint on planning.

- Appendix AA names the existing seams a coder must preserve: the sole DB++
  bridge, 20-case `MuscleGroup`, `VolumeCredit`, rich workout prescription
  adapter, collapsed strength cards, full-screen set editor, performer-specific
  defaults, stable partner alternation, Watch flow models, and idempotent phone
  reconciliation.
- The old “body-part” language is replaced by canonical per-muscle tracking.
  DB++ direct/indirect/stabilizer roles and volume eligibility drive planned and
  completed totals; broad body regions are grouping/search only.
- Plans materialize into the existing `WorkoutSession` prescription seam. They
  do not create a second live set/result model, require every workout to be
  planned, or replace manual starts, swaps, history editing, cardio, or partners.
- The Watch contract now matches the shipped architecture: `HKWorkoutSession`
  owns live/background workout execution and HealthKit save; local records plus
  durable WatchConnectivity payloads reach the phone; the phone owns CloudKit.
  The obsolete `WKExtendedRuntimeSession` assumption is removed.
- `WS-EXECUTION-COMPAT` blocks planner work until compatibility fixtures exist.
  Acceptance criteria 40–45 cover plan materialization, legacy fallback, partner
  defaults, muscle credits, unplanned flows, and real-Watch offline recovery.
- Two new mockups distinguish planning UI from runtime UI: the shipped iPhone
  collapsed/expanded/full-screen set-entry sequence and the Watch strength/cardio
  lifecycle. The catalog now contains **64 screens**.

---

## 0000. v2.3 → v2.4 — universal external-client delivery (2026-09-02)

This revision lets a trainer coach someone who does not own an iPhone or Apple
Watch without weakening Cladiron's privacy-first, serverless boundary.

- A client now chooses one of two delivery modes: **Connected Cladiron** or
  **External / no app required**. Both use the same plan and review domain and
  both count identically for Cladiron Pro.
- External delivery builds an immutable, versioned `ExternalPlanPacket` from a
  plan snapshot. A shared renderer produces accessible HTML email, a polished
  PDF attachment, and a plain-text fallback from the same content tree.
- Trainers may open the system Mail composer with recipient, subject, HTML body,
  and PDF prefilled, or open the system Share sheet to use Messages, WeChat,
  AirDrop, Files, or another installed destination. Cladiron never sends in the
  background and never reads the trainer's mail or contacts.
- A privacy preflight lets the trainer choose the date range and whether to
  include notes, prior results, estimated maxes, and the reporting request. The
  exact output is previewed before it leaves the app.
- External clients reply through their chosen channel. The trainer records the
  reported result through a dedicated flow with `externalClientReport`
  provenance; the app never treats opening a composer as proof of delivery.
- There is deliberately no hosted public “share link” in this serverless MVP.
  “Share” means sharing the self-contained packet through the operating system.
  A future hosted-link feature would require an explicit authenticated backend,
  expiry/revocation, abuse controls, and a separate privacy review.
- Appendix Z is the implementation contract: domain types, deterministic packet
  builder, rendering rules, platform adapters, lifecycle/error states, secure
  temporary-file handling, accessibility, localization, and required tests.
- Six mockups cover client setup, external-client status, privacy preflight,
  the recipient-facing packet, result entry, and macOS sharing. The catalog now
  contains **62 screens/artifacts**.

---

## 000. v2.2 → v2.3 — shipped DB++ baseline and proprietary boundary (2026-09-02)

This revision aligns the roadmap with the code that landed after v2.2.

- Cladiron is now explicitly **proprietary, closed-source software**. GPL and
  App Store-exception language is removed from the current product licensing.
- Required public copy is: **“Cladiron is a proprietary, privacy-first
  application built on the open free-exercise-db-plusplus project. The exercise
  database, annotations, and related tooling remain freely available for use by
  other applications.”**
- `free-exercise-db-plusplus` 1.15.4 is already pinned behind the sole
  `TrainingEngineBridge` import boundary. The shipped baseline includes 873
  exercises, a 20-muscle ontology, evidence-audited roles/volume credits,
  movement classification, deterministic self-planning, history observations,
  adaptation/progression, evidence resolution, and persistence contract tests.
- Cladiron's readiness, pain, recovery, eligibility, citation policy,
  persistence, presentation, HealthKit, and Apple-platform integration remain
  app-owned and proprietary.
- Phases 0 and 2 are no longer described as greenfield database/engine builds.
  They close gaps between the shipped app and the unified-plan/trainer roadmap.
- A licensing/About mockup is added, bringing the catalog to 56 screens.

---

## 00. v2.1 → v2.2 — decisions resolved (2026-08-11)

No new design. Every open question the spec carried is now closed, and two of the answers changed the document materially.

| # | Decision | Resolution |
|---|---|---|
| 1 | **Persistence** | **SwiftData mirrored to CloudKit**, following the shipped app — *not* v1.0's GRDB + hand-written sync. Removed the single most expensive line in the spec. |
| 2 | **Module naming** | **`CadenceCore` / `CadenceUI` / `CadenceCommands`**; *Cladiron* is user-facing only. |
| 3 | **Status** | **Adopted as the roadmap.** `CLAUDE.md` gains a roadmap pointer; its shipped-behaviour sections stand until each phase lands. |
| 4 | **Prices** | **$99/yr · $12/mo · $249 lifetime**, tip jar unlocks nothing. |
| 5 | **Lifetime** | **Indefinite** — not a launch promotion. Honest because marginal cost of service is zero. |
| 6 | **Stripe service payments** | **Permanent non-goal.** The platform is now unconditionally serverless. |
| 7 | **Group/cohort programming** | **Non-goal**, confirmed. |
| 8 | **iPadOS 26** | **Presentation difference, not a floor.** Toolbar + ⌘K palette below 26. |
| 9 | **Localization** | **English at launch**, architecture localization-ready, per-locale cost stated (alias curation is the novel one). |
| 10 | **Policy defaults** | Ratified as specified. |

**The persistence reversal, in one paragraph.** v1.0 chose GRDB/SQLite plus a hand-written CloudKit sync layer, principally over watchOS+CloudKit reliability fears, and v2.0/v2.1 carried that forward without re-examining it. But the product itself reversed on 2026-07-27 and now runs SwiftData mirrored via `NSPersistentCloudKitContainer` in production, watchOS included — so the spec was quietly demanding a rewrite of a layer that already works. §10.1–10.2 now follow the shipped architecture, Q.1 records the reversal, and the constraints that actually matter moved to the foreground: CloudKit-compatible model shapes, **append-only enforced in the domain rather than by the framework** (mirroring is last-writer-wins per property), additive-only schema evolution, and the fact that **suppressing mirroring during a Watch runtime session takes deliberate work** — automatic sync will happily push mid-session unless stopped. The two hard rules survive untouched, because they were always about *when* to sync, not which store you use.

**Sections touched:** header (v2.2, status now "adopted"); Principle 7; §7.2; **§10.1–10.2 rewritten**; §9 preamble; §3.2 (three new non-goals); §29.3; §42.4; §44.4 (price table, lifetime, serverless closure); §45.2 (launch scope + per-locale cost); §46.3; Phase 0 and `WS-STORE`; §51.2/§51.3; Appendix G (v2.2 entry); L.5; **Q.3 rewritten as a closure table** plus new Q.3a; Q.1 (persistence row replaced); Q.4 (pricing bet made concrete); W.2/W.3; and the `CadenceCore`/`CadenceUI` rename throughout the spec, the notes, and the mockups. Paywall mockup now shows real prices.

---

## 0. v2.0 → v2.1 — the Mac app comes back, native, under Universal Purchase

v2.0 eliminated the Mac app and reached the desktop through **Mac Catalyst**. v2.1 reverses **that one decision** and nothing else.

**What v2.1 changes**

| | v2.0 | v2.1 |
|---|---|---|
| Mac delivery | Catalyst destination of the iPad target | **Native macOS app target** (SwiftUI for macOS, AppKit where the platform expects it) |
| Distribution | One record; Mac build via Catalyst | **One record, one bundle ID, Universal Purchase** — native macOS apps can use it, which is the fact v2.0 did not use |
| Mac for individual planning | Implied | **Explicit and normative**: fully functional and free, no purchase to plan your own training (§44.2, K.5a) |
| The purchase | Pro = clients | Unchanged — and now stated as *the product's only in-app purchase*, with clients addable from iPhone, iPad, **or Mac** and iCloud keeping the roster in step (§44.4, §49.25) |
| Packages | `CadenceCore` | `CadenceCore` **+ new `CadenceUI`** — the shared SwiftUI view layer that makes a second target affordable and mechanically enforces "no Mac-only capability" |
| Guard rails | — | **No Mac-only capability, CI-enforced** (§38.3); **Universal Purchase configured before the first Mac release** because records can never be merged (§38.5, L.6) |

**Why the reversal is defensible.** v2.0 gave five reasons to kill the Mac app. Two were about *where programming happens* (trainers are mobile; iPadOS 26 closed the capability gap) — those hold, and §32 is untouched. The other three were about *how to reach the desktop*, and each has an answer: Catalyst's cost is that a professional tool reads as an iPad app in a window, and Apple's own guidance is native SwiftUI for a **new** multi-platform app; the "two professional UIs" cost was an AppKit premise, not a shared-SwiftUI one; and "one app, one purchase" — v2.0's best argument — is delivered by Universal Purchase rather than by Catalyst. §2.3 records the full arc (v1.0 native → v2.0 Catalyst → v2.1 native) rather than overwriting it.

**Sections touched:** header + 30-second summary + §1; §2.3 (rewritten as the decision arc); §3.1/3.2; Principle 5; §5 glossary; §6.1 persona / §6.2 journey 7; §7.1 (targets, packages, diagram) and §7.5 (idiom ladder); Part V title and §29.1; §31.6; §33.1; §37.3; **§38 rewritten** (native app, shared vs shell, the no-Mac-only rule, honest second-target cost, Universal Purchase mechanics, native test plan, why-native decision); §44.2/44.4; Phase 4; `WS-MAC-NATIVE` and `WS-UNIVERSAL-PURCHASE` replacing `WS-CATALYST`; acceptance criteria renumbered with new 24, 25, 29 (criteria now run to 34); §50 test plan; §51.2 risks; Appendix G (v2.1 changelog); K.0 + K.5 + new K.5a; L.1/L.2/L.5/L.6; M.4 (three new rows); Q.1 (three rows), Q.4 (two new bets); S (six new traceability rows); T; W.7/W.9; X.4; colophon.

**Mockups:** `mac-catalyst-*` renamed to `mac-*` **and rewritten** (the "what Catalyst adds" panel and its trade-off note were wrong under v2.1), plus a new **`mac-athlete-planner.html`** showing the free, full-fidelity individual planner on Mac. Total 54 → **55**.

**Deliberately retained Catalyst references.** §2.3, §38.4, §38.7, the Appendix F glossary entry, Appendix G, and Q.1 mention Catalyst *as history or as the rejected alternative*. Those are intentional; every other reference is gone.

---

## 1. The four changes that drove the revision

| # | Change | Where it lands |
|---|---|---|
| 1 | **The Mac stops being a separate product.** The full trainer workbench moves onto the **iPad** at full fidelity, keyboard-first, with a menu bar. *v2.0 additionally removed the Mac app and used Catalyst; **§0 supersedes that half** — the Mac app is kept and native, in the same App Store record under Universal Purchase. What survives from v2.0 is the part that mattered: the professional surface is no longer desktop-only, and the Mac is not a second purchase.* | §2.3 (full arc), Part V, §38 (native Mac), §3.2, Appendix L |
| 2 | **iPhone gains complete trainer functionality.** Not a viewer: a coach can run a roster, author a full per-set plan, review results, and send — entirely on a phone. | §32 (the whole section), §30.2, Appendix K.10–K.12 |
| 3 | **The iPhone authoring model is redesigned for touch,** rather than shrinking the grid. | §32.2–32.7 |
| 4 | **Monetization is re-cut:** Pro gates *coaching other people* only; any client requires Pro; 30-day trial; one purchase covers iPhone + iPad + Mac; **all self-coached use — including the entire expert system and partner sessions — is free forever**. | §44 (rewritten), §8.5, §23, §9.12, Appendix P.8, U.15 |

---

## 2. Why the Mac app went away in v2.0 — and what survived (§2.3, condensed)

> **Read with §0.** Arguments 1–2 below still stand and drive the current design. Arguments 3–5 were about desktop *delivery* and are superseded: v2.1 ships a native Mac app under Universal Purchase. The list is kept because the reasoning matters and because a decision log should show its own reversals.

1. **Trainers are not at a desk.** Programming happens between clients, standing up. A desktop-only professional surface optimizes for the least common posture in the job.
2. **iPadOS 26 closed the gap** — a real menu bar with visible key equivalents, windowing and tiling, mature pointer support. The specific things that made a Mac app necessary in v1.0 are now native iPad capabilities.
3. **Catalyst gives the desktop for free** — real menu bar, multiple windows, `NSSavePanel`, printing, right-click — from the same target. Apple ships a dozen of its own apps this way.
4. **A solo developer cannot maintain two professional UIs.**
5. **One app, one purchase, one mental model** — and it is what makes iPhone trainer mode coherent rather than an odd satellite.

v2.0 called the residual "iPad-derived" feel an acceptable cost and recorded it as a bet. **That bet is the one v2.1 called** — for a tool a coach stares at for hours, it was the wrong place to compromise, and shared SwiftUI plus Universal Purchase made the native alternative affordable. The cost accounting moved with it: §38.4 now prices a second target honestly, and Q.4 bets that shared SwiftUI keeps it cheap.

---

## 3. The compact authoring model (the core new design)

Governed by a normative rule (§32.1): *every field of every entity that can be authored on iPad can be authored on iPhone; compact width may change how many interactions an edit costs, never what can be expressed.*

Five layers, coarse to fine (§32.2):

| Layer | Mechanism | Typical cost |
|---|---|---|
| 1 | **Session sources** — last week, a template, another client, or Generate | 1–2 taps per session |
| 2 | **Set schemes** — a named generator fills an item's whole set list | 2–3 taps per exercise |
| 3 | **Shorthand** — `bench 4x8 @70% rpe8 r2:30`, or paste a whole session | 1 line per exercise |
| 4 | **Chip rows + prescription bar** — edit any single field of any single set | 2 taps per field |
| 5 | **Bulk apply** — one field across many sets | 3 taps for N sets |

Supporting pieces:

- **Set stack + chip rows** (§32.3) — one row per set; each chip an independently tappable 44 pt target; warm-ups recessive; numbers never truncate; chips are VoiceOver-adjustable elements.
- **The prescription bar** (§32.6) — a persistent bottom accessory, **never a modal**, with a field picker (the column analogue), a contextual control, and a `‹ set n of m ›` stepper (the row analogue). This is what makes five-set editing cost five taps.
- **Client switching without a sidebar** (§32.8) — Clients tab + nav-bar client chip with a quick switcher + horizontal paging on the week header.
- **Send preflight** (§32.9) — Generate never chains into Send; the sheet shows the week summary, critique count, and the weights about to freeze.
- **Compact review** (§32.11) — diff rows with matching sets collapsed, so exceptions dominate.
- **Honest limits** (§32.10) — a stated list of what genuinely remains slower on a phone, with mitigations.

Parity is enforced in four independent places (Appendix S.1): the normative rule, acceptance criterion 12, the CI parity fixture, and the WS done-conditions.

---

## 4. Monetization, before and after

| | v1.0 | v2.0 |
|---|---|---|
| Who pays | The trainer (Mac app subscription); single users pay for expert-system assistance | The trainer only |
| Self-coached expert system | Paid surface | **Free** |
| Partner sessions | Not modelled | **Free**, and modelled (§9.11, §23) |
| Client threshold | Implicit (you needed the Mac app) | **Any client — one or forty — requires Pro** |
| Trial | Unspecified | **30 days**, starting at the first gated action |
| Devices | Mac app separate | **One purchase covers iPhone, iPad, Mac** |
| Client-side cost | Free, no paywalls | Unchanged — free, no paywall, no purchase UI at all |
| Server | One thin billing/licensing endpoint | **None — the exception is withdrawn; the platform is fully serverless** |
| Lapse behaviour | Unspecified | **Read-only trainer surfaces; clients stay connected; results keep arriving; export keeps working; own training untouched** (§44.6) |
| Paywall conduct | Unspecified | Codified: appears only on a user action involving another person's device, lists the free tier first, no dark patterns, no analytics, one trial reminder (§44.7, P.8) |
| Migration | n/a | Existing Pro buyers keep everything and gain Trainer mode; nothing free becomes paid (§44.8) |

**Partner ≠ client** (§8.5) is the load-bearing distinction that keeps the boundary honest and the paywall non-leaky. A partner trains beside you (free); a client receives plans on their own device (Pro). Promotion from one to the other is explicit and gated.

---

## 5. Model changes

Additive; nothing in v1.0's model was removed.

| New | Purpose |
|---|---|
| `SetScheme`, `SetSchemeID`, `SchemeKind`, `SchemeParams` (§9.9) | Named, parameterized set-list generators — the phone's layer 2 and the iPad's Apply Scheme |
| `StrengthItem.schemeApplied` | Enables "re-apply with different parameters" without reconstructing intent |
| `PerformerRef`, `PartnerRef` (§9.11); `performer` on every result | Partner rotation with correct data isolation |
| `Session.partners`, `performerOverrides` | Shared or per-lifter prescriptions |
| `ProEntitlement`, `EntitlementState`, `TrainerCapability` (§9.12) | One gate, one place; no inline entitlement checks in views |
| `ExerciseDef.shorthandAliases` | Deterministic shorthand resolution (CI-checked for uniqueness per locale) |
| `ClientRelationship`: `archived` status, `RoundingProfile`, `InjuryNote`, `colorTag` | Archived clients don't count toward the gate; rounding is per client |
| `AuthoringIdiom` | Diagnostics only; never drives behaviour |
| Appendix B.7 | Shorthand token-resolution algorithm |
| Appendix I.8 | Scheme expansion algorithm (pure and total) |

---

## 6. Section-by-section map

Part V was rewritten and everything after it renumbered.

| v1.0 | v2.0 | Note |
|---|---|---|
| §1–18 | §1–18 | Carried forward; §2.3 added (why no Mac app), §3.2 expanded, Principle 10 added (free/paid line), Principle 4 strengthened to the expressiveness rule, §7.5 added (idiom ladder), §8.5 added (partner vs client), §9.9/9.11/9.12 added, §12.3 gained the alias-uniqueness gate, §16.1 distinguishes shorthand from the LLM, §17 gained per-idiom surface rules, §18.2 hardened for compact Send |
| §19–27 (Part IV) | §19–28 | Athlete app; §20.2 (where Trainer mode lives), §23 (partner sessions), §28.3 (trainer first-run) added |
| §28–34 (Mac app) | §29–38 (trainer surface) | **Rewritten.** §29 IA across idioms · §30 clients · §31 iPad planner · **§32 iPhone builder (new)** · **§33 command system (new)** · §34 assistance · §35 templates · §36 review · §37 export · **§38 Catalyst (new)** |
| §35–37 (Watch) | §39–41 | Carried forward; §39.5 partner rotation added |
| §38–42 (cross-cutting) | §42–46 | §42.5 gained the lapse rule; §43.1 extended to the paywall; **§44 rewritten**; §45.3 accessibility per idiom |
| §43–48 (delivery) | §47–51 | Re-phased; work-streams renamed/added; acceptance criteria expanded from 20 to 31 |
| Appendices A–X | A–Y | K rewritten (55 mockups), L rewritten (targets), O extended (density table, new components), P gained §P.8 paywall copy, Q gained 12 new decisions, R gained the mobile-authoring moat, S rewritten, U gained R-TIER-1..5 and R-RST-3, V gained V.8/V.9, W gained W.6 (compact authoring gotchas) and W.8 (entitlement), **Y added (keyboard/menu command reference)** |

---

## 7. Delivery re-sequencing

The biggest change after Part V: **the compact authoring system ships in Phase 1, with the free athlete app** — not in the trainer phase. It is the hardest UI in the product, and building it where the stakes are lowest, a year before trainers depend on it, is the main de-risking move of the revision.

| Phase | v1.0 | v2.0 |
|---|---|---|
| 0 | Foundations + sync proof | Same, plus schemes/partners/entitlement types |
| 1 | Single-user planner (iPhone) | Athlete app on **iPhone and iPad**, including **set stack, prescription bar, schemes, shorthand, partner sessions** |
| 2 | Expert system | Same — and now free |
| 3 | Mac trainer app + sharing | **Trainer mode on iPad** + sharing + command system + **Pro entitlement** |
| 4 | Depth + LLM | **Trainer mode on iPhone + the native Mac app (v2.1)** |
| 5 | — | Depth, autoregulation, LLM interface |

New acceptance criteria worth calling out: #12 (compact-authoring parity — the keystone test), #22 (every command fires from menu, keyboard, and touch), #23 (native Mac test plan), #24 (no Mac-only capability), #25 (clients addable from any device), #29 (Universal Purchase holds), #26–28 and #30–31 (trial start, no-upsell-in-free, lapse behaviour, no inline entitlement reads, prior-purchase migration).

---

## 8. Mockups

55 screens in `mockups/`, catalogued in `mockups/index.html` and Appendix K.0:

- **15 iPad** — roster/dashboard, client overview, week board, per-set grid, menu bar + HUD + palette, generate, critique, strength profile, review, templates + schemes, copy-to-client drag, two windows, invite, export, athlete planner.
- **4 Mac (native)** — builder, dashboard, save panel + print, and the free athlete planner (`mac-athlete-planner.html`).
- **8 iPhone trainer** — roster triage, client week, client switcher, review diff rows, copy-to-client, send preflight, Pro paywall, lapsed read-only.
- **16 iPhone athlete** — home, plan week, **set stack**, **prescription bar (3 field states)**, **scheme picker (2 states)**, **shorthand (3 states)**, **bulk select (2 states)**, exercise picker + substitute, move/reschedule, **partner session (3 states)**, assisted planning, progress, onboarding, coach's plan received, active set, after-set rest.
- **12 Watch** — the eleven v1.0 screens unchanged, plus partner rotation.

Several files deliberately show two or three states of one view side by side, because on these screens the states are the design.

---

## 9. What was explicitly *not* changed

The plan/week/day/session/item/set spine, prescription-vs-result separation, %1RM snapshot-at-send, the append-only rule, the no-sync-during-runtime-session rule, CloudKit sharing, the Watch execution model, Excel export, the privacy and no-telemetry stance, and the not-a-medical-device boundary. The expert-system architecture is retained but now explicitly composes around the shipped DB++ engine boundary. If v1.0 was right about something, later revisions say so and move on.

---

## 10. Open questions — all resolved 2026-08-11

This section listed five open questions. **All are closed**; see §00 above for the answers and Appendix Q.3 in the spec for the authoritative closure table.

1. ~~Pro price points and whether lifetime stays~~ → **$99/yr · $12/mo · $249 lifetime; lifetime indefinite.**
2. ~~iPadOS 26 as the trainer-mode floor~~ → **No; presentation difference only.**
3. ~~Group/cohort programming~~ → **Non-goal.**
4. ~~Client↔trainer service payments via Stripe~~ → **Permanent non-goal; the platform is unconditionally serverless.**
5. ~~Localization order~~ → **English at launch, architecture localization-ready.**

Plus two decisions surfaced during closure that were not on the original list: **persistence follows the shipped SwiftData + CloudKit architecture** rather than v1.0's GRDB, and **modules are named `CadenceCore`/`CadenceUI`** with *Cladiron* reserved for user-facing copy.

What remains is not questions but **bets to check against reality** — compact authoring, the native Mac target's maintenance cost, $99/yr conversion for a one-client coach, and whether a free expert system pays for itself through the trainer tier. Each is written down in spec Q.4 with the signal that would falsify it.
