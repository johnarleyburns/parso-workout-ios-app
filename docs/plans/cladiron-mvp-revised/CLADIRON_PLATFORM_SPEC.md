# Cladiron Coaching Platform — Complete Specification (Revised)

**Version:** 2.6 — *self-planned, automated-coach product* (revises v2.5, v2.4, and v1.0 in `docs/plans/cladiron-mvp/`)
**Status:** Authoritative implementation roadmap, scope-corrected on **2026-09-09**. It distinguishes the shipped baseline from remaining MVP work; `current_status.md` is the execution ledger.
**Supersedes:** `cladiron-mvp/CLADIRON_PLATFORM_SPEC.md` v1.0, which itself superseded `MVP_DESIGN.md` v0.2
**Companion docs (present in this directory):** `REVISION-NOTES.md` (what changed and why), `mockups/index.html` (per-screen visual mockup catalog), `Cladiron-Coaching-Export-Sample.xlsx` (sample export)

> **Note on inherited references.** v1.0 cited two companion documents — `TRAINER_PLATFORM_STRATEGY.md` (business case and positioning) and `DATABASE_SWIFTDATA_MIGRATION.md` (the persistence-layer analysis behind the GRDB decision and the two hard sync rules) — and both are cited again below where their reasoning is load-bearing. **Neither file exists in this repository.** They are treated here as the *intended* homes for that material: the decisions they justified are restated in summary form in §10, §42.6, and Appendix Q so that this specification stands alone, and the citations mark where the fuller analysis belongs if those documents are ever written. The same applies to `MVP_DESIGN.md` v0.2, which v1.0 superseded.

## v2.6 active scope correction — self-planned, automated coach only

This section is the current product boundary and supersedes any conflicting
v2.5 trainer/client, roster, sharing, Pro, trial, paywall, external-delivery,
or trainer-specific Mac requirements elsewhere in this document. Those older
sections remain below only as historical decision context; they are not active
implementation work.

- Cladiron has one product user: an athlete planning and executing their own
  training. Planning is manual, template-based, or assisted by Cladiron's
  automated scientific coach. “Coach” means software in the active plan; there
  is no personal-trainer role and no client role.
- There is no Trainer mode, client roster, trainer/client relationship, invite or
  accept flow, CKShare delivery, external-client packet, or human-coach result
  review. Private iCloud sync remains for the user's own devices only.
- There are no gated Pro features, Pro entitlement, trial, paywall, or feature
  downgrade. Manual planning, templates, automated coach suggestions, critique,
  progression, insights, execution, history, export, and partner sessions are
  not gated by purchase.
- The only planned purchase is an optional **$9.99 “Contribute to development”**
  consumable. A successful purchase adds a **Supporter** badge to the user's
  Home view and unlocks nothing else. It is never required, promoted as a
  feature gate, or used to restrict core functionality.
- The active platform scope is iPhone + embedded Apple Watch, with iPad/other
  larger-surface self-planning considered only when it directly serves the same
  individual user. The trainer-specific Mac target and Universal Purchase work
  are removed from the roadmap.

The active delivery plan is therefore: preserve the shipped training loop;
finish manual self-planning; deepen the automated coach; add optional supporter
badge/purchase handling; then polish readiness, natural-language assistance,
and cross-device self-sync. New work must not expand legacy trainer/client or
Pro compatibility types; migration/removal of those leftovers is separate
cleanup, not a reason to revive the retired product model.

---

## How to read this document

This specification describes Cladiron as one Apple-native product centered on
**iPhone + Apple Watch**, with optional larger-surface self-planning where it
serves the same individual user. It includes the scientific coach expert
system (`CadenceCore`) that powers evidence-based planning. It is written to
be handed to an agentic coding tool work-stream by work-stream, so it is
deliberately concrete: data types, workflows, screen-by-screen interaction,
the encoded evidence base with citations, and acceptance criteria.

The only sync boundary in the active plan is the user's own private iCloud
store across their devices. There is no client delivery, external packet, or
human-coach sharing workflow.

**Product and open-project boundary (normative).** Cladiron is proprietary,
closed-source software. **Cladiron is a proprietary, privacy-first application
built on the open free-exercise-db-plusplus project. The exercise database,
annotations, and related tooling remain freely available for use by other
applications.** No Cladiron screen, metadata, documentation, or support copy may
describe the application itself as open source. Open-project links and license
notices must describe only `free-exercise-db-plusplus`, upstream exercise data,
and their related tooling.

**Shipped DB++ baseline (normative starting point).** The repository already pins
`free-exercise-db-plusplus` **1.15.4** as a Swift package dependency and routes it
through the sole import boundary `TrainingEngineBridge`. The current catalog has
**873 exercises**, a normalized **20-muscle ontology**, evidence-audited muscle
roles and volume credits, movement classification, deterministic self-planning,
history-derived observations, plan adaptation/progression, package-evidence
resolution, and persistence round-trip coverage. App-owned readiness, pain,
recovery, eligibility, presentation, and citation policy compose around DB++ and
remain authoritative. Implementation must extend this boundary, not rebuild or
fork the database/engine inside Cladiron.

**What changed from v1.0, in one paragraph.** The active product is now explicitly
self-planned: the athlete builds manually, starts from templates, or accepts
suggestions from the automated scientific coach. Human trainer/client delivery,
rosters, sharing, external packets, Pro gates, trials, and trainer-specific Mac
work are retired from the roadmap. The only optional purchase is a $9.99
“Contribute to development” consumable that adds a Supporter badge to Home and
does not unlock functionality.

> **v2.0 → v2.1 note.** v2.0 of this document eliminated the Mac app entirely and reached the desktop through **Mac Catalyst**. v2.1 reverses that specific delivery decision: the Mac app returns as a **native** target under Universal Purchase (§2.3, §38). Everything else v2.0 established — mobile-first trainer capability, the compact authoring model, and the free/Pro line — is unchanged and, if anything, better served. Because one App Store record carries exactly one macOS binary, the native target **replaces** the Catalyst destination; the two cannot coexist.

The document is organized in eight parts plus appendices:

- **Part I — Product** — vision, scope, principles, personas.
- **Part II — Architecture & data** — one app across four idioms; the unified planning model and complete data model.
- **Part III — The scientific coach expert system** — the heart of the platform: how the evidence-based engine assists planning, what it knows, and how it stays defensible.
- **Part IV — The athlete experience (iPhone-first)** — the free, self-coached app: a manual + assisted weekly planner.
- **Part V — Larger-surface self-planning (historical trainer section retained below)** — active work remains individual self-planning; the old trainer/client surface is non-normative.
- **Part VI — The Apple Watch app** — execution.
- **Part VII — Cross-cutting** — private self-sync, privacy, optional contribution, units, errors.
- **Part VIII — Delivery** — phasing, work-streams, acceptance, testing.
- **Appendices** — citation registry, formula reference, exercise/taxonomy schemas, keyboard command reference, consolidated type catalog, glossary, mockup catalog.

Evidence claims are cited inline as `[Author Year]` and collected with DOIs in **Appendix A**. The expert system is *evidence-gated*: no prescription rule ships without a citation, and CI enforces it (§12).

---

## The 30-second summary

Cladiron is an **Apple-native, evidence-based strength-and-conditioning platform**. It is one product with an iPhone app, an embedded Watch app, and optional larger-surface self-planning:

1. **Self-planned athletes** plan their week in the **Plan tab** — by hand, from pre-made plans, with a training partner, or with **automated coach assistance** — and execute on Apple Watch.
2. The automated coach generates, critiques, progresses, and explains suggestions; the user remains the author and decides what to accept or edit. It is not a human trainer, a client service, or an always-on improvisational coach.
3. All core planning, coach assistance, execution, history, insights, templates, export, and partner sessions are available without a feature gate. The only purchase is an optional **$9.99 “Contribute to development”** consumable that adds a **Supporter** badge to Home.
4. Private iCloud sync supports the same user's devices. There is no client delivery, roster, invite, external packet, or human-coach sharing path.

The same plan object, execution on the wrist, and review flow serve the user.
Plan provenance distinguishes manual, template, and automated-coach-suggested
origins; the user remains responsible for accepting or editing every suggestion.

The differentiator is the **scientific coach expert system**: an evidence-gated engine that generates, critiques, and progresses plans using published sport-science evidence (volume landmarks, proximity-to-failure, %1RM/RPE-RIR prescription, periodization, autoregulation, fatigue management), always with a cited rationale — not a black-box LLM.

---

## Table of contents

**Part I — Product**
1. Executive summary
2. Vision & positioning: one planning model, one app, every screen
3. Scope & non-goals
4. Guiding principles
5. Terminology & glossary (short form; full glossary Appendix F)
6. Personas & top user journeys

**Part II — Architecture & data**
7. System architecture and the four idioms
8. The unified planning model
9. Complete data model
10. Persistence, sync, and plan provenance

**Part III — The scientific coach expert system**
11. Philosophy: evidence-based, evidence-gated
12. The EvidenceGate architecture
13. The knowledge base (encoded evidence)
14. Assistance capabilities
15. Planning-assistant workflows (trainer and single-user)
16. The LLM-as-interface layer
17. Explainability and citations
18. Safety, liability, contraindications, and pain handling

**Part IV — The athlete experience (iPhone-first, free)**
19. The restructure: retiring the always-on coach
20. Information architecture
21. The Home page (plan + progress)
22. The Plan tab (manual + assisted weekly planner)
23. Partner sessions (free tier)
24. Plan provenance in the athlete app
25. Progress and the per-muscle dashboard
26. Insights (retained)
27. Execution from the plan
28. Onboarding, first-run, and migration

**Part V — The trainer surface (iPad, Mac, iPhone)**
29. Overview: one trainer app at three densities
30. Client management and the dashboard
31. The full planner / builder on iPad
32. The iPhone trainer builder (compact-width authoring)
33. The command system: menus, keyboard, and pointer
34. Expert-system assistance for trainers
35. Templates, programs, and multi-client operations
36. Workout review
37. Export and backup
38. The native Mac app and Universal Purchase

**Part VI — The Apple Watch app**
39. Execution model
40. Feedback and readiness
41. Sync, offline, complications, and widgets

**Part VII — Cross-cutting concerns**
42. CloudKit sharing specification
43. Privacy and data ownership
44. Monetization: Cladiron Pro and the client gate
45. Units, localization, and accessibility
46. Error handling, edge cases, empty states, notifications

**Part VIII — Delivery**
47. Phased implementation plan
48. Work-stream specifications
49. Acceptance criteria
50. Testing and QA
51. Analytics stance, risks, and open questions

**Appendices**
- A. Evidence and citation registry
- B. Formula reference
- C. Exercise library schema and seed list
- D. Muscle-group and movement-pattern taxonomy
- E. Consolidated data-type catalog
- F. Glossary
- G. Changelog
- H. Worked examples: the expert system in action
- I. Engine algorithms
- J. Built-in pre-made plan library
- K. Detailed screen specifications and the mockup catalog
- L. Platform requirements and deployment
- M. State machines and the edge-case matrix
- N. Data-flow sequences
- O. Design system, adaptive layout, and visual language
- P. Content and copy guidelines (including paywall copy)
- Q. Decision log and traceability
- R. Competitive positioning and moats
- S. Requirements traceability matrix
- T. Quick-reference cheat sheet
- U. The rule set (enumerated)
- V. Additional worked scenarios
- W. Implementation notes and gotchas
- X. Reading paths and document maintenance
- Y. Keyboard and menu command reference

---
---

# PART I — PRODUCT

## 1. Executive summary

Cladiron is a platform for **planning, executing, and reviewing evidence-based strength and conditioning training** on Apple devices. It ships as **one universal app** (plus its embedded Watch app) that presents two configurations of the same data:

- The **self-coached configuration** (iPhone/iPad + Apple Watch) is for an athlete coaching themselves, alone or with a training partner. Its centrepiece is a **weekly planner** — the **Plan tab** — where the athlete lays out their training week by hand, adopts a pre-made plan, or asks the **coach expert system** to draft and refine a plan for them. The Home page shows the **current plan and per-muscle progress**; execution uses the already-shipped, field-tested iPhone and Watch workout loops; **Insights** surface evidence-based observations. Planning adds prescriptions and scheduling without replacing exercise entry, set logging, partner rotation, cardio, HealthKit, WatchConnectivity, history, or recovery behavior. **It is free, forever, in full** — including expert-system generation, critique, progression, and partner sessions.

- The **coached configuration** switches the same app into **Trainer mode**: a roster of clients, the full expert-system-assisted planner, prescribed-vs-actual review, templates, multi-client operations, and export. On **iPad** it is a three-column workbench with a menu bar, hardware-keyboard command set, pointer affordances, drag-and-drop between clients, and multi-window support. On **Mac** it is a **native macOS app** — the same view layer and the same `CadenceCore`, with a Mac scene model, a real menu bar, desktop-density tables, save panels, and printing. On **iPhone** the same capabilities are re-expressed for one thumb and a 6-inch screen — not a cut-down viewer, but a complete authoring system built on set-scheme presets, a persistent prescription bar, shorthand entry, and bulk edit. Trainer mode requires **Cladiron Pro**, which begins with a **30-day free trial** and, through Universal Purchase, covers all the user's devices at once.

The crucial design decision that unifies these is that **a plan is a plan regardless of who authored it, or on what screen.** The athlete's Plan tab, the iPad planner, and the iPhone trainer builder produce the same object. When a trainer sends a plan, it lands in the client's Plan tab flagged as *coach-authored*; when the athlete plans for themselves, it is *self-authored*; a pre-made plan is *template-authored*. Everything downstream — execution, logging, progress, insights, export — is identical.

The platform's competitive differentiator, and the primary subject of Part III, is the **scientific coach expert system**. It is not a chatbot and not a black-box generator. It is an **evidence-gated engine**: a deterministic knowledge base of published sport-science findings (with citations and DOIs) that generates plans, audits plans for problems, suggests progressions from logged performance, substitutes exercises while preserving training stimulus, autoregulates load from effort feedback, and detects when a deload is warranted — and it explains every recommendation with a cited rationale. A natural-language layer sits *on top* of the engine as an interface, running on-device or via Apple's Private Cloud Compute, but it never makes the safety-critical prescription decisions itself.

## 2. Vision & positioning: one planning model, one app, every screen

### 2.1 The problem with "always-on coaching"

The predecessor to this product was an iPhone app with an **always-on live coach**: a surface that reacted in the moment — suggesting the next set, nudging in real time, behaving like a coach standing next to you at every instant. Three problems motivated its retirement:

1. **It conflated planning with execution.** Real coaching separates the two: a coach *plans* a training block deliberately (considering the week, the athlete's recovery, their goals, the evidence) and then the athlete *executes* the plan. An always-on system that improvises in the moment cannot reason about the week, cannot balance weekly volume across sessions, and cannot apply periodization — because it never plans.
2. **It made the app feel like a slot machine, not a training tool.** Continuous in-the-moment suggestions encourage compulsive checking and reduce the athlete's own agency over their training. Serious lifters want to *see and own their plan*, not be surprised by it set-by-set.
3. **It did not map to the trainer product.** A trainer plans a week for a client; there is no "always-on live coach" in a trainer's workflow. To unify the self-coached and coached experiences under one planning model and one engine, the athlete app had to become a *planner* too.

### 2.2 The unified planning model

The platform is organized around a single spine (detailed in §8):

```
Plan  →  Week  →  Day  →  Session  →  Item  →  Set / Cardio / Mobility / Instruction
```

A **Plan** is a structured intention for training over a horizon (a week, a mesocycle). It is authored by **the athlete**, **their trainer**, or **a pre-made template**, and it is executed and reviewed identically in every case. This single object is what the Plan tab edits, what the trainer planner produces on any device, what the Watch executes, and what the review surfaces compare against.

The vision, stated as one sentence: **plan your week — by hand, from a template, with a partner, or with an evidence-based coach's help — whether the coach is the app's expert system or a real human trainer, on whatever device is in your hand, and execute it on your wrist.**

### 2.3 The Mac decision, and how it arrived here

This decision has flipped twice, so the whole arc is recorded rather than the current answer alone. A decision log that hides its own reversals is worth less than one that shows them.

| Version | Mac delivery | Why |
|---|---|---|
| **v1.0** | A **separate native macOS app** (`Cladiron Coach`), sold as its own product, and *the* place professional planning happened | Assumed a dense grid, keyboard commands, and side-by-side windows were desktop-only capabilities |
| **v2.0** | **No Mac app.** The iPad became the professional surface and reached the desktop through **Mac Catalyst** | Trainers work on the move; iPadOS 26 supplied the menu bar and windowing; Catalyst was nearly free; a solo dev could not maintain two professional UIs |
| **v2.1 (this document)** | A **native macOS app**, in the **same App Store record** as the iOS app under **Universal Purchase**, free for individual planning, with clients behind the one in-app purchase | The mobile-first insight held, but the delivery mechanism was wrong: a native target is now cheap because the view layer is shared SwiftUI, and Universal Purchase removes the second-product problem that made a Mac app feel like a fork |

**What v2.0 got right, and keeps.** Two of its five arguments were about *where programming happens*, and they are stronger than ever:

1. **Trainers are not at a desk.** The moment programming actually happens for an independent coach is between sessions, on a gym floor, standing up, phone in hand — or on an iPad propped on a rack. Making the *portable* surfaces first-class is the product insight, and §32 (full authoring on iPhone) remains the distinctive claim of this specification.
2. **iPadOS closed the gap.** iPadOS 26 brought a real **menu bar** (swipe down, hover the pointer at the top, or Globe-M), **windowing** with tiling and multi-window, and mature pointer support. A keyboard-first iPad app is no longer a contradiction, and the iPad remains a full-fidelity professional surface in its own right — not a Mac substitute.

**What changed, and why the Mac comes back native.** v2.0's remaining three arguments were about *how to reach the desktop*, and each has an answer:

3. **"Catalyst gives the desktop for free" — but at a cost this product should not pay.** Catalyst's own trade-off, which v2.0 acknowledged and listed as a checkable bet, is that a touch-derived layout reads as "the iPad app in a window." For a tool a professional stares at for hours while programming twenty clients, that is precisely the wrong place to accept a compromise. Apple's own guidance points the same way: **Catalyst is the right tool for porting an existing iPad app; a new multi-platform app built from scratch should use native SwiftUI on each platform.** Cladiron is new.
4. **"A solo developer cannot maintain two professional UIs" — true of AppKit, false of shared SwiftUI.** v1.0's premise was a hand-built AppKit workbench with its own grid, inspector, and menu system. That is not what this is. The Mac target shares `CadenceCore`, the view models, and the great majority of the SwiftUI view layer with iPhone and iPad; what differs is the **shell** — scene and window model, `.commands`, table metrics, file panels, printing. The `.commands` tree (§33.1) actually maps *more* directly to a native Mac menu bar than to Catalyst's. This is a real second target with a real cost (§38.4), but it is a fraction of the v1.0 estimate.
5. **"One app, one purchase, one mental model" — preserved exactly, by Universal Purchase.** This was v2.0's best argument and it survives intact, because a native Mac app **does not require a separate product**. Sharing the iOS bundle ID puts both binaries in **one App Store record**: one download entitlement, one in-app purchase, one subscription. A coach installs Cladiron on their phone, starts a trial, and their Mac is already unlocked. Universal Purchase is available to native macOS apps, not only to Catalyst ones — this is the fact that makes v2.1 possible and that v2.0 did not use.

**One constraint worth stating early.** An App Store record carries exactly **one** macOS binary, so the native target **replaces** the Catalyst destination — they cannot both ship. And records that start separate **can never be merged**, so Universal Purchase must be configured from the very first Mac release (L.6).

**The honest cost, restated.** v2.1 buys native feel by accepting a second app target: platform-conditional code, a second test matrix, and the standing discipline that **no capability may be Mac-only** (§38.3). If that discipline slips, the "one product" promise breaks and the Mac becomes the fork v2.0 feared. Q.4 records this as the bet to check.

### 2.4 Positioning

Cladiron is positioned as the **evidence-based, Apple-native training platform for serious strength and conditioning** — for self-coached lifters who want to program intelligently, and for independent strength coaches who want a fast, scientific, native planning tool that travels with them. It competes on **depth, not breadth**: planning, execution, review, and evidence-based assistance done exceptionally well, and deliberately *not* nutrition tracking, social feeds, a video library, business CRM, or cross-platform (Android/web) clients. Its moats are (a) the native Apple-ecosystem execution experience, especially on the Watch; (b) the evidence-gated expert system; (c) a serverless, privacy-first, no-lock-in architecture; and now (d) **the only professional programming surface that fits in a pocket** — a genuine differentiator against desk-bound web dashboards. The full business case is in `TRAINER_PLATFORM_STRATEGY.md`.

## 3. Scope & non-goals

### 3.1 In scope (this specification)

- A **universal iPhone/iPad app** with two configurations of one data model: the free **athlete experience** (Plan tab, Home, Progress, Insights, partner sessions, execution) and the Pro **Trainer mode** (roster, full planner, review, templates, multi-client operations, export).
- **Full-fidelity trainer planning on iPad**, keyboard-first, with a menu bar, a documented command set (Appendix Y), pointer affordances, drag-and-drop between clients, and multi-window/Stage Manager support.
- **A native macOS app** with the same capabilities at desktop density, shipped in the **same App Store record under Universal Purchase** (§38).
- **Full-fidelity trainer planning on iPhone** through a purpose-designed compact-width authoring system (§32) — set-scheme presets, the prescription bar, shorthand entry, bulk edit, and a client-switching model that works with one thumb.
- An **Apple Watch app** for executing strength, cardio, and mobility work with per-set logging, optional RPE, rest timing, native heart-rate tracking, and partner rotation.
- The **scientific coach expert system** (`CadenceCore`): evidence-gated plan generation, critique, progression, substitution, autoregulation, deload detection, and insights, with a natural-language interface layer.
- **Universal client delivery:** serverless CloudKit sharing for connected Cladiron clients, plus local HTML/PDF/plain-text plan packets and manual result capture for external clients, with no custom server and no custom accounts.
- **Cladiron Pro** entitlement via StoreKit 2: the client gate, the 30-day trial, and the free-tier guarantee (§44).
- **Excel export/backup** for data portability.
- Per-set prescription with rep targets, load prescriptions (absolute / %1RM / bodyweight / band / machine / assisted), RPE/RIR, rest, set types, and separate actual results.

### 3.2 Non-goals (explicitly out)

- **A separate Mac *product*.** The Mac app is native, but it is not a second App Store record, a second price, a second purchase, or a Mac-only feature set. "Download the other app for the Mac" is the thing being ruled out, not the Mac app itself (§2.3, §38.3, L.6).
- **A Mac-only capability of any kind.** If it is worth having on the Mac it ships to iPad and iPhone too (§38.3).
- **Nutrition and meal tracking** of any kind.
- **Android or web clients**; the platform is Apple-only by design.
- **A custom backend or account system** (CloudKit sharing replaces both).
- **Business administration** for trainers: scheduling, invoicing beyond optional payment routing, marketing, lead capture, CRM.
- **Social features**: feeds, followers, badges, streaks, challenges, leaderboards.
- **Technique video** upload, review, or a video exercise library.
- **Automatic exercise recognition** from Watch motion sensors.
- **Velocity-based training** hardware/telemetry (the model reserves fields; no VBT device integration ships).
- **Medical, clinical, or rehabilitation** workflows and diagnosis (§18).
- **Detailed body measurements and progress photos** (progress is training-performance-based).
- A **two-sided marketplace** matching trainers to clients (the trainer brings their own clients).
- **Group/class programming** (one plan pushed to a cohort as a first-class object). Multi-client apply (§35.3) covers the practical need. **Confirmed a non-goal on 2026-08-11**; revisit only if gyms or teams become a target segment.
- **Client↔trainer service payment routing** (Stripe under Guideline 3.1.3(d)). **Resolved as a permanent non-goal on 2026-08-11**: it is the only remaining feature that would reintroduce a server, and being able to say "there is no server" without an asterisk is worth more than the convenience. Trainers collect payment by whatever means they already use.
- **Localization beyond English at launch.** The architecture is localization-ready (§45.2) and nothing hard-codes English, but no second locale ships in this plan.

### 3.3 Relationship to prior documents

This specification **supersedes v1.0** as the authoritative product description, but it does not supersede proven shipped behavior. The current DB++ exercise/muscle model and field-tested iPhone/Watch execution loop are normative compatibility constraints in Appendix AA. New planning data adapts into those seams; it may not replace them merely because an earlier mockup looked different. Where this document and v1.0 differ, **this document governs**. `REVISION-NOTES.md` is the section-by-section diff.

## 4. Guiding principles

These principles are load-bearing; when a design decision is ambiguous, resolve it in favour of the earlier-numbered principle.

1. **Evidence-based, and evidence-gated.** Every prescription rule in the expert system is grounded in published sport-science evidence and carries a citation. No rule ships without one; CI enforces this (§12). The system prefers to say "the evidence is mixed here, and this is a judgment call" over asserting false certainty.
2. **The engine decides; the language model only translates and narrates.** Safety-critical prescription logic is deterministic, inspectable, and cited. The LLM parses natural language into structured requests and renders rationale into prose, but never makes the prescription decision.
3. **Plan, then execute.** Training is planned deliberately and executed faithfully. The app supports planning (with assistance) and honest execution; it does not improvise prescriptions in the moment.
4. **One planning model, authored by anyone, anywhere.** The athlete, a trainer, and a template all produce the same `Plan` object — and every device can author it at full fidelity. A capability that exists on iPad exists on iPhone; only the *interaction cost* differs, never the *expressiveness*. This is a hard rule, not an aspiration (§32.1).
5. **Apple-native is the moat — on every platform it ships to.** Native SwiftUI and deep watchOS/iPadOS/macOS integration are the competitive advantage. The platform is iOS/iPadOS/macOS/watchOS only, each target genuinely native to its platform, and leans into platform capabilities (Health, Live Activities, complications, the Digital Crown, the iPad menu bar, Mac windows and menus) rather than a lowest-common-denominator cross-platform layer — including the cross-platform layer a compatibility shim would represent.
6. **Serverless and account-less.** No custom backend, no custom user accounts. Identity is the user's Apple ID; sync and sharing are CloudKit; entitlement is StoreKit 2; the trainer runs nothing.
7. **Local-first and offline-first.** The local SwiftData store is the source of truth for the device; the app is fully usable offline; sync is additive. A logged set is never lost.
8. **Privacy-first, no telemetry.** No analytics, no tracking, no advertising, no data harvesting.
9. **Own your data — no lock-in.** One-click Excel export of the entire dataset. Making it easy to leave is a feature and an acquisition lever, not a risk.
10. **Free to train yourself; pay to train others.** Every capability an athlete needs for their own training — including the full expert system and partner sessions — is free forever, with no upsells in the athlete surfaces. The paid line is drawn at the point where the app starts doing professional work *for other people* (§44).
11. **Small in breadth, deep in depth.** Do a focused set of things exceptionally well; refuse breadth that dilutes them.
12. **Honest about uncertainty and effort.** Effort feedback (RPE/RIR) and readiness are treated as *useful signals*, not infallible measurements; the app never overstates precision (e.g., estimated 1RM is always labelled *estimated*).

## 5. Terminology & glossary (short form)

A full glossary is Appendix F. Key terms used throughout:

- **Plan** — a structured training intention over a horizon (typically a week or a mesocycle), authored by the athlete, a trainer, or a template.
- **Week / Day / Session** — the calendar structure of a plan. A **Session** is one training bout (e.g., "Monday: Lower Body + Conditioning").
- **Item** — a component of a session: a strength exercise, a cardio block, a mobility/timed activity, or a note/instruction.
- **Set** — the atomic unit of strength prescription: its own reps, load, RPE/RIR target, rest, and type.
- **Prescription vs Result** — the *prescription* is what was planned; the *result* is what the athlete actually did. Stored separately, compared in review.
- **e1RM (estimated 1RM)** — a per-exercise estimate of the athlete's one-rep-max, derived from logged submaximal performance (Epley/Brzycki) or entered manually. Drives %1RM loading.
- **%1RM** — load prescribed as a percentage of e1RM; the engine computes the working weight.
- **RPE / RIR** — Rating of Perceived Exertion (Helms 1–10 scale) and Reps In Reserve; RPE 10 = 0 RIR (failure), RPE 8 = 2 RIR, etc.
- **Volume landmarks (MV / MEV / MAV / MRV)** — maintenance, minimum-effective, maximum-adaptive, and maximum-recoverable weekly set volumes per muscle (§13.1).
- **Provenance** — who authored a plan: self, trainer, or template.
- **Partner** — someone training *alongside* the user in the same physical session, with their own logged sets in a rotation. A partner is **not** a client: no plan is delivered to them, no share is created, no roster entry exists. Partner sessions are **free** (§23, §8.5).
- **Client** — someone the user authors plans *for*. A connected client uses Cladiron and CloudKit sharing; an external client receives portable plan packets and reports results for trainer entry. **Any client requires Pro** (§44).
- **Trainer mode** — the Pro configuration of the app: roster, planner-for-others, review, templates, export. A mode of the one app, not a separate app.
- **Idiom** — which shape the app is currently in: `compact` (iPhone, or a narrow iPad window), `regular` (iPad), or `mac` (the native macOS app). Idiom drives layout, not capability (§7.5).
- **Universal Purchase** — Apple's mechanism for shipping iOS and macOS binaries under **one App Store record and one bundle ID**, so a single download entitlement and a single in-app purchase cover every platform (§38.5, L.6).
- **CadenceCore** — the shared Swift package containing the expert system, data model, and citation registry.
- **EvidenceGate** — the mechanism that ensures every prescription is backed by a registered citation (§12).
- **Insight** — an evidence-based observation about the athlete's training surfaced to help them.

## 6. Personas & top user journeys

### 6.1 Personas

- **Sam — the self-coached intermediate lifter.** Trains 4×/week, understands sets/reps/RPE, wants to program intelligently without hiring a coach. Primary user of the Plan tab and expert-system assistance. Values owning and seeing the plan, evidence-based guidance, and a flawless Watch logging experience. **Pays nothing, ever**, and is never shown an upsell in his own training surfaces.
- **Dana — the independent strength coach.** Coaches 15–40 remote and in-person clients. Programs in three postures: at her desk with an iPad and Magic Keyboard (bulk work, new blocks, templates), at home on a Mac (the native app; two clients in two windows, printing this week for an in-person session), and **on the gym floor with her phone** (adjust today's session for the client in front of her, review last night's logs between appointments, fire off a substitution). Values fast per-set programming, %1RM from each client's e1RM, evidence-based assistance that respects her methodology, prescribed-vs-actual review, and data portability. Pays for Pro.
- **Maya — Dana's client.** Wears an Apple Watch, wants to follow her coach's plan without friction, no accounts or paywalls. Uses the app in *coached* mode: her Plan tab is populated by Dana; she executes on the Watch; her results flow back. **Pays nothing.**
- **Rae — the accidental coach.** Programs for exactly one person besides herself: her partner, who trains at a different gym on a different schedule. She is why the tier boundary matters. Rae plans her own training free, trains *with* a partner free, and the moment she wants to *send* a week to someone else's phone she hits the Pro gate — with a 30-day trial that lets her find out whether the workflow is worth it before paying.
- **Alex — the beginner.** New to structured training. Uses pre-made plans and heavy expert-system assistance with strong guardrails; benefits from the app's conservative defaults and clear explanations. Free.

### 6.2 Top journeys (summarized; detailed in Parts IV–VI)

1. **Self-plan a week with assistance.** Sam opens the Plan tab, states a goal and constraints, the expert system drafts a week with a cited rationale, Sam edits it, and schedules it. → §22, §15.
2. **Adopt and adapt a pre-made plan.** Alex browses pre-made plans, picks a beginner full-body 3×/week template, the system individualizes loads from Alex's sparse e1RM data and flags what to fill in. → §22.4.
3. **Train with a partner.** Sam and a friend run the same session in rotation; each set is logged to the right lifter; each person's history and e1RM stay their own. → §23.
4. **Execute a session on the Watch.** Maya starts today's session on her Watch, logs each set with the Crown, optionally rates RPE, follows rest timers, does the prescribed cardio against a heart-rate target, and finishes; results sync back. → Part VI.
5. **Program a week on iPad.** Dana selects a client, generates a draft, edits the per-set grid with the keyboard alone, critiques, and sends — without lifting her hands from the keys. → §31, §33.
6. **Program a week on iPhone, standing up.** Dana, between clients, opens the roster on her phone, picks Maya, taps `5×5`, adjusts two sets with the prescription bar, types `rdl 3x10 @rpe8 r90` into quick-add, and sends. → §32.
7. **Same product on the desktop, no second purchase.** Dana opens Cladiron on her Mac — already installed and already unlocked, because the trial she started on her phone covers it — tiles two client windows side by side, and drags an exercise from one to the other; loads recalculate to the destination client's e1RM. → §38, §35.3, §44.4.
8. **Hit the Pro gate honestly.** Rae taps "Add a client," sees exactly what Pro covers and what stays free, starts a 30-day trial with no card friction beyond Apple's, and is reminded once before it converts. → §44.
9. **Review and progress.** Dana reviews Maya's completed session (prescribed vs actual), sees an exception, accepts a suggested e1RM change, and sends next week's plan. → §36, §14.
10. **Export everything.** Dana exports her whole dataset to Excel for backup and peace of mind, from any device. → §37.

---
---

# PART II — ARCHITECTURE & DATA

## 7. System architecture and the four idioms

### 7.1 One app, one core, four surfaces

The platform comprises **one product**, built from **two app targets plus an embedded Watch app**, over **two shared Swift packages**:

- **Cladiron (iOS / iPadOS)** — the universal mobile target. Two idioms — `compact` (iPhone; also a narrow iPad window) and `regular` (iPad) — and two configurations — athlete (free) and Trainer mode (Pro).
- **Cladiron (macOS)** — the **native Mac target**, idiom `mac`. Same configurations, same capabilities, desktop shell. **Same bundle ID and same App Store record** as the mobile target, so the two ship as a single **Universal Purchase** (§38.5).
- **Cladiron Watch App** — the execution surface, embedded in the iOS app.
- **CadenceCore (Swift package)** — the shared brain and model: the expert system (knowledge base, generators, critics, progression, autoregulation, deload logic), the complete data model and its domain invariants, the citation registry and EvidenceGate, the 1RM/e1RM math, the volume/effort computations, the entitlement resolver, and the CloudKit sync/share layer abstractions. Every target depends on it; the Watch app depends on a lightweight execution subset.
- **CadenceUI (Swift package)** — the shared SwiftUI view layer and view models: the set stack, the per-set grid, the week board, roster and review surfaces, rationale and citation components. This package is what makes a second app target affordable, and it is where the "no Mac-only capability" rule (§38.3) is mechanically enforced — a feature that lives here reaches all three idioms by construction. Only the **shell** (scene and window model, `.commands`, file panels, printing, platform metrics) is per-target.

```
        ┌──────────────────────────────┐   ┌──────────────────────────────┐
        │        CadenceCore          │   │         CadenceUI           │
        │  • Data model + invariants   │   │  • Set stack + chip rows     │
        │  • Expert system:            │   │  • Per-set grid              │
        │      generate / critique /   │   │  • Week board, roster,       │
        │      progress / substitute / │   │    review, rationale         │
        │      autoregulate / deload   │   │  • View models               │
        │  • Knowledge base + citations│   │                              │
        │  • EvidenceGate              │   │  Shared by every target —    │
        │  • 1RM / %1RM / volume math  │   │  a feature added here        │
        │  • Pro entitlement resolver  │   │  reaches all three idioms    │
        │  • CloudKit sync + share     │   │  by construction (§38.3)     │
        └──────────────────────────────┘   └──────────────────────────────┘
                        ▲                                 ▲
                        └───────────────┬─────────────────┘
        ┌───────────────────────────────┴───────────────────────────────┐
        │        ONE APP STORE RECORD · ONE BUNDLE ID · UNIVERSAL PURCHASE│
        ├───────────────────────────────────┬───────────────────────────┤
        │  Cladiron (iOS / iPadOS) target   │  Cladiron (macOS) target  │
        ├──────────────────┬────────────────┼───────────────────────────┤
        │ compact (iPhone) │ regular (iPad) │  mac (native)             │
        │ • Athlete: Plan, │ • Athlete:     │  • Athlete: full planner, │
        │   Home, Progress │   2-column     │    free, desktop density  │
        │ • Trainer mode:  │   planner      │  • Trainer mode:          │
        │   roster sheet,  │ • Trainer:     │    3-column workbench,    │
        │   prescription   │   3-column,    │    Mac menu bar, windows, │
        │   bar, schemes,  │   per-set grid,│    NSSavePanel, printing, │
        │   shorthand      │   menu bar,    │    right-click, Services  │
        │                  │   drag & drop, │                           │
        │                  │   multi-window │                           │
        └──────────────────┴────────────────┴───────────────────────────┘
                        │
            ┌───────────┴───────────┐
            │  Cladiron Watch App   │
            │  Execution: sets,     │
            │  cardio, RPE, rest,   │
            │  partner rotation     │
            └───────────────────────┘
```

`CadenceCore` is the linchpin of the "one engine, many screens" design, and `CadenceUI` is what keeps a second app target from becoming a second product. Every planning surface is a UI over the same generators and critics; the difference is *interaction density*, not brain — and, per Principle 4, not expressiveness either.

### 7.2 Persistence and sync at a glance

- **Local store:** **SwiftData** on each device is the device's source of truth. v1.0 specified GRDB/SQLite with a hand-written sync layer; the shipping app reversed that on 2026-07-27 in favour of SwiftData mirrored to CloudKit, and **this specification follows the shipped architecture** (§10.1, Q.1).
- **Single-user sync:** a user's own data (their training *and*, for a trainer, their roster and drafts) syncs across their devices by mirroring the SwiftData store to the user's **private** CloudKit database via `NSPersistentCloudKitContainer` (`cloudKitDatabase: .private`). This is what makes "start on iPad, finish on iPhone, review on the Mac" work — and it is why the Mac target needs no sync code of its own.
- **Trainer↔client exchange:** connected clients use **CloudKit sharing** (`CKShare` + one custom record zone per client) for plan delivery and result return. External clients use locally rendered HTML/PDF/plain-text packets plus explicit, trainer-entered results. No custom server; no custom accounts. Detailed in §42 and Appendix Z.
- **Entitlement:** `ProEntitlement` resolves from StoreKit 2 transactions, Apple-ID-tied, cached locally and revalidated; it syncs implicitly because it is derived from the App Store account, not stored data (§44.4).
- **Three invariants carried throughout:** (a) **% loads resolve to a concrete weight and are snapshotted when a plan is sent/started**; (b) **the Watch owns the live `HKWorkoutSession` while the phone owns CloudKit, with durable WatchConnectivity reconciliation between them**; (c) **entitlement never gates reading, executing, or exporting data the user already has** (§44.6).

### 7.3 The expert-system placement

The shipped implementation delegates reusable exercise intelligence and core
deterministic training operations to the open `free-exercise-db-plusplus` 1.15.4
package. `CadenceCore/TrainingEngineBridge.swift` is the only Swift source allowed
to import that package. `CadenceCore` translates app profiles, targets, plans,
and history at this boundary, then composes DB++ outcomes with Cladiron's
proprietary readiness, pain, recovery, eligibility, citation, persistence, and
UI policies. CI must fail if another Swift source imports the package or if the
exact version pin changes without an explicit spec revision.

The expert system lives entirely in `CadenceCore` and is therefore available identically to the athlete planner and the trainer planner on every idiom. A **natural-language interface layer** (§16) wraps the engine: on iPhone/iPad/Mac it can run on-device (Apple Foundation Models) or via Private Cloud Compute for heavier requests, and it is strictly an interface — it converts free text into a structured `PlanningRequest`, calls the engine's deterministic generators/critics via a typed tool interface, and narrates the engine's cited output. The engine's decisions never depend on the language model.

### 7.4 Platform-capability integration

- **HealthKit** — reads heart rate during cardio and (optionally, with permission) recovery-relevant signals (resting HR, HRV, sleep) to inform readiness insights (§13.12, §40). Writes workouts to Health.
- **Live Activities & Dynamic Island** — an in-progress session and rest timer are visible without opening the app.
- **watchOS complications & widgets** — "today's session" and "next up" are glanceable. On iPad, a **roster widget** shows which clients need attention.
- **The Digital Crown** — the primary input for adjusting reps/load and entering RPE on the Watch.
- **iPadOS menu bar and windowing** — the trainer command set is exposed as a real menu bar with visible key equivalents, and the app supports multiple windows, tiling, and Stage Manager (§33, §38).
- **Hardware keyboard** — supported on **iPhone as well as iPad**: if a keyboard is attached to a phone, the same command set applies (§33.5).
- **Pointer** — hover states, right-click context menus, and precise drag targets on iPad and Mac.
- **Mac platform integration** — a real menu bar, multiple windows with restoration, `NSSavePanel`/`NSOpenPanel`, printing, Quick Look of an exported workbook, and the Services menu (§38.2).
- **App Intents / Shortcuts** — "start today's workout," "what's my plan today," and (Pro) "what did *Maya* do yesterday."
- **Handoff** — start a plan on iPad, continue on iPhone, or hand execution to the Watch.
- **Drag and drop** — between exercises, sessions, days, clients, and windows (§35.3).

### 7.5 The idiom ladder (how one app changes shape)

Layout is chosen by **horizontal size class + idiom**, never by device model. A single `TrainerWorkbench` scene resolves to one of three arrangements:

| | `compact` (iPhone, narrow iPad window) | `regular` (iPad) | `mac` (native macOS) |
|---|---|---|---|
| Navigation | `NavigationStack` + bottom tab bar; roster is a pull-down sheet | `NavigationSplitView` 3-column: roster ∣ week/session ∣ inspector | Same 3-column at Mac metrics, with a source-list sidebar, resizable inspector, and window chrome |
| Per-set editing | **Set stack** of chip rows + **prescription bar** (§32.3) | **Per-set grid** with keyboard traversal (§31.3) | Per-set grid at desktop density + right-click menus |
| Bulk edit | Long-press → selection mode → bar applies to all | Shift/Cmd multi-select rows | Shift/Cmd multi-select rows |
| Commands | Toolbar + context menus; keyboard set when a keyboard is attached | Menu bar + Cmd-hold shortcut HUD + full keyboard | Mac menu bar + full keyboard + Services |
| Cross-client copy | "Copy to client…" sheet with %-recalc preview | Drag exercise onto a roster row, or "Copy to…" | Drag between windows |
| Inspector (rationale/critique) | Bottom sheet at medium detent | Third column | Third column, resizable |
| Export | Share sheet / Files | Share sheet / Files | `NSSavePanel`, plus printing |
| Purchase | Cladiron Pro (StoreKit 2) | Same entitlement | Same entitlement — **one Universal Purchase covers all three** (§38.5) |

**The invariant:** every field of every entity is reachable and editable in all three arrangements. Where a compact-width interaction would take too many taps, the answer is a *faster path to the same edit* (schemes, shorthand, bulk apply) — never a removed capability. §32.1 states this as a testable rule and §49 makes it an acceptance criterion.

## 8. The unified planning model

### 8.1 The spine

Everything the platform does is organized around one hierarchy:

```
Plan
└── Week (one or more; a Plan may be a single week or a multi-week mesocycle)
    └── Day (Mon–Sun; a Day may be a rest day or hold one or more Sessions)
        └── Session (a training bout, e.g., "Lower Body + Conditioning")
            └── Item (ordered)
                ├── StrengthItem   → ordered Sets
                ├── CardioItem     → steady / interval / open prescription
                ├── MobilityItem   → rounds × timed/reps
                └── InstructionItem → free text (a coaching note or standalone instruction)
```

A **Plan** is the unit that is authored, sent, adopted, and reviewed. Self-coached athletes typically work one **Week** at a time (a rolling weekly planner), optionally grouped into a **mesocycle**. A trainer typically authors a Week per client and re-sends weekly, optionally from a saved multi-week program template.

### 8.2 Provenance and authorship

Every Plan carries **provenance**:

- **`selfAuthored`** — created by the athlete in their own Plan tab.
- **`trainerAuthored`** — created by a trainer and sent to the client. Immutable to the client by default (the client executes it; they can log actuals and, if permitted, request changes, but they don't rewrite the prescription). Carries the trainer's identity for attribution.
- **`templateAuthored`** — instantiated from a pre-made plan (shipped with the app or saved by the user/trainer). Once instantiated it becomes editable and effectively self- or trainer-authored depending on who instantiated it.

Provenance drives only *presentation and edit permissions*, never execution. A trainer-authored session and a self-authored session are logged and reviewed identically. **Provenance is also independent of the authoring device**: a plan written on an iPhone is indistinguishable from one written on an iPad or a Mac (the model records `authoredOnIdiom` for diagnostics only, never for behaviour).

### 8.3 Assistance is orthogonal to authorship

The expert system can assist *any* authoring path. A self-authored plan may be entirely hand-built, fully generated, or (most commonly) generated-then-edited. A trainer-authored plan may be hand-built, generated and refined, or a template adapted. The axes are independent:

- **Authorship**: self / trainer / template.
- **Assistance**: none / generated / critiqued / progressed.
- **Surface**: compact / regular / mac.

This independence is what lets the iPhone trainer builder be "the iPad planner at a different interaction density": same engine, same model, same output.

### 8.4 Scheduling model

A Plan's Week maps to real calendar days. Sessions are scheduled on Days; a Day may hold zero (rest), one, or (rarely) two Sessions. The author may **reschedule** a Session within the week without changing its content — by drag on iPad/Mac, or by a **Move to day…** action on iPhone (which is faster than dragging on a phone and is available everywhere for accessibility). Missed sessions are tracked and feed adherence and insights. The planner supports **repeat** operations (repeat a Session on selected days; repeat a Week).

### 8.5 Partners and clients are different things

This distinction is load-bearing for both the data model and the business model, so it is stated once, here, normatively:

| | **Partner** | **Client** |
|---|---|---|
| Who | Someone lifting *with* you, in the same session, same place | Someone you author plans *for*, who trains on their own device |
| Data | Their sets are logged inside **your** session as `SetResult`s tagged with a `PartnerRef`; optionally mirrored to their own app if they also use Cladiron | A `ClientRelationship` with a dedicated CloudKit shared zone; their own full record of plans and results |
| Delivery | Nothing is delivered — you're standing next to each other | A `Plan` is written into their zone and appears in their Plan tab, attributed to you |
| Roster | No roster entry, no invite, no share | Roster entry, invite/accept flow, `CKShare` |
| Review | The session summary shows both lifters' work | Full prescribed-vs-actual review, exceptions, engine suggestions |
| Cost | **Free** | **Pro** (§44) |

A partner can be promoted to a client (an explicit action that creates the relationship and triggers the Pro gate); a client is never silently treated as a partner. The engine treats a partner's logged sets as **that person's** training data for the purposes of their own volume/e1RM if they are a Cladiron user; if they are not, partner sets are retained on the host's device for the session record but excluded from the host's own volume accounting and e1RM (§9.11).

## 9. Complete data model

This section specifies the full domain model. Types are given as Swift value types for clarity; their persistence mapping (SwiftData `@Model` types, subject to the CloudKit-compatibility constraints in §10.1) and shared-zone record mapping are in §10 and Appendix E. Domain invariants (e.g., private initializers enforced by the expert system) are noted; the enforcement mechanism is EvidenceGate (§12).

### 9.1 Identity and provenance

```swift
struct PlanID: Hashable, Codable { let raw: UUID }

enum PlanProvenance: Codable {
    case selfAuthored
    case trainerAuthored(trainer: TrainerRef)
    case templateAuthored(templateID: TemplateID, adaptedBy: AuthorRef)
}

struct TrainerRef: Codable { let displayName: String; let shareOwnerID: String }  // no PII beyond a display name
enum AuthorRef: Codable { case selfAthlete; case trainer(TrainerRef) }

enum AuthoringIdiom: String, Codable { case compact, regular, mac, watch }  // diagnostics only; never drives behaviour
```

### 9.2 Plan, Week, Day, Session

```swift
struct Plan: Codable {
    let id: PlanID
    var title: String
    var provenance: PlanProvenance
    var goal: TrainingGoal              // primary goal (may vary per session)
    var horizon: PlanHorizon            // singleWeek | mesocycle(weeks: Int)
    var weeks: [PlanWeek]
    var createdAt: Date
    var updatedAt: Date
    var authoredOnIdiom: AuthoringIdiom?
    var status: PlanStatus              // draft | active | archived
    var notes: String?
    var rationale: EngineRationale?     // present if generated/critiqued (see §17)
}

enum TrainingGoal: Codable { case strength; case hypertrophy; case enduranceMuscular; case generalFitness; case powerSpeed; case fatLoss; case mixed }
enum PlanHorizon: Codable { case singleWeek; case mesocycle(weeks: Int) }
enum PlanStatus: Codable { case draft; case active; case archived }

struct PlanWeek: Codable {
    let id: UUID
    var index: Int                      // 0-based week within the plan
    var days: [PlanDay]                 // exactly 7, Monday-first (locale-aware display; storage canonical)
    var intendedProgression: ProgressionIntent?  // how this week differs from the prior (see §13.9)
    var isDeload: Bool
}

struct PlanDay: Codable {
    let id: UUID
    var weekday: Weekday
    var sessions: [Session]             // 0..2; empty = rest day
    var isRestDay: Bool { sessions.isEmpty }
}

struct Session: Codable {
    let id: UUID
    var title: String                   // "Lower Body + Conditioning"
    var goal: TrainingGoal              // may override the plan goal for this session (DUP-style)
    var items: [WorkoutItem]            // ordered
    var estimatedDurationMinutes: Int?  // engine-estimated
    var status: SessionStatus           // planned | inProgress | completed | skipped
    var startedAt: Date?                // written by execution
    var completedAt: Date?
    var sessionRPE: Double?             // optional overall session RPE (execution)
    var painFlag: PainFlag?             // optional post-session
    var note: String?                   // athlete or trainer note
    var partners: [PartnerRef]          // empty for a solo session (§9.11)
}

enum SessionStatus: Codable { case planned; case inProgress; case completed; case skipped }
```

### 9.3 Workout items (polymorphic)

```swift
enum WorkoutItem: Codable {
    case strength(StrengthItem)
    case cardio(CardioItem)
    case mobility(MobilityItem)
    case instruction(InstructionItem)
}
```

**Strength item and sets** — the atomic set is the core unit; every set is independently prescribed:

```swift
struct StrengthItem: Codable {
    let id: UUID
    var exerciseKey: ExerciseKey        // reference into the bundled library (no exercise text synced)
    var order: Int
    var instructions: String?           // coaching cue
    var tempo: String?                  // e.g. "3-1-1-0" (modelled now; UI optional)
    var defaultRestSeconds: Int?
    var alternateExerciseKey: ExerciseKey?  // one optional trainer/engine-specified substitute
    var sets: [PrescribedSet]
    var schemeApplied: SetSchemeID?     // which scheme preset generated these sets, if any (§32.4)
    var supersetGroup: SupersetGroupID?     // reserved; nil in 2.0 (approximate via ordering + note)
}

struct PrescribedSet: Codable {
    let id: UUID
    var setIndex: Int
    var kind: SetKind                   // warmup | working | backoff | amrap | drop
    var repTarget: RepTarget
    var load: LoadPrescription
    var targetRPE: Double?              // Helms 1–10
    var targetRIR: Int?                 // alternative to RPE; the two interconvert (RPE = 10 − RIR)
    var restSeconds: Int?
    var trainerNote: String?
}

enum SetKind: Codable { case warmup; case working; case backoff; case amrap; case drop }

enum RepTarget: Codable {
    case exact(Int)                     // 8
    case range(min: Int, max: Int)      // 8–10
    case amrap(minimum: Int?)           // AMRAP, optionally "at least N"
    case duration(seconds: Int)         // isometric / carry / plank
    case distance(meters: Double)       // loaded carry distance
}

enum LoadPrescription: Codable {
    case absoluteWeight(value: Double, unit: WeightUnit)
    case percent1RM(percent: Double, calculatedWeight: Double?)  // weight snapshotted at Send/Start
    case bodyweight
    case bodyweightPlus(value: Double, unit: WeightUnit)
    case assisted(value: Double, unit: WeightUnit)
    case band(level: String)
    case machineSetting(String)
    case rpeOnly                        // "work up to RPE 8 for the day" — load chosen by athlete
    case unspecified
}

enum WeightUnit: Codable { case lb; case kg }
```

**Actual results** — kept strictly separate from the prescription:

```swift
struct SetResult: Codable {
    let id: UUID
    var prescribedSetID: UUID?          // nil for an unprescribed extra set
    var performer: PerformerRef         // .owner or .partner(PartnerRef)  — §9.11
    var actualReps: Int?
    var actualLoad: Double?
    var actualLoadUnit: WeightUnit?
    var actualDurationSeconds: Int?
    var actualDistanceMeters: Double?
    var actualRPE: Double?
    var actualRIR: Int?
    var completed: Bool
    var skippedReason: String?
    var note: String?
    var completedAt: Date?
}
```

**Cardio item**:

```swift
struct CardioItem: Codable {
    let id: UUID
    var order: Int
    var prescription: CardioPrescription
    var instructions: String?
}

enum CardioPrescription: Codable {
    case steadyState(SteadyState)
    case intervals(Intervals)
    case open(OpenActivity)             // "≥30 min easy–moderate"
}

struct SteadyState: Codable {
    var activity: CardioActivity        // walk/run/bike/row/swim/elliptical/stairs/other
    var durationSeconds: Int?
    var distanceMeters: Double?
    var intensity: CardioIntensity?
    var inclinePercent: Double?
    var cadenceRange: ClosedRange<Int>?
    var warmupSeconds: Int?
    var cooldownSeconds: Int?
}

struct Intervals: Codable {
    var activity: CardioActivity
    var warmupSeconds: Int?
    var rounds: Int
    var work: IntervalSegment
    var recovery: IntervalSegment
    var cooldownSeconds: Int?
}

struct IntervalSegment: Codable {
    var durationSeconds: Int?
    var distanceMeters: Double?
    var intensity: CardioIntensity
}

struct OpenActivity: Codable { var activity: CardioActivity; var goalText: String; var targetIntensity: CardioIntensity? }

enum CardioActivity: Codable { case walk; case run; case bike; case row; case swim; case elliptical; case stairs; case other(String) }

enum CardioIntensity: Codable {
    case rpe(ClosedRange<Double>)
    case heartRateBPM(ClosedRange<Int>)
    case percentMaxHR(ClosedRange<Double>)
    case heartRateZone(Int)             // 1–5 (§13.13)
    case pace(ClosedRange<Double>, PaceUnit)
    case speed(ClosedRange<Double>, SpeedUnit)
    case powerWatts(ClosedRange<Int>)
    case talkTest(TalkTestLevel)
}

struct CardioResult: Codable {
    let id: UUID
    var cardioItemID: UUID
    var performer: PerformerRef
    var durationSeconds: Int?
    var distanceMeters: Double?
    var averageHR: Int?
    var hrRange: ClosedRange<Int>?
    var averagePace: Double?
    var overallRPE: Double?
    var note: String?
    var completedAt: Date?
}
```

**Mobility / timed and instruction items**:

```swift
struct MobilityItem: Codable {
    let id: UUID
    var order: Int
    var name: String                    // "Hip flexor stretch"
    var rounds: Int?
    var perRound: RepTarget             // .duration(30) etc.
    var eachSide: Bool
    var instructions: String?
}
struct MobilityResult: Codable { let id: UUID; var mobilityItemID: UUID; var performer: PerformerRef; var completed: Bool; var note: String?; var completedAt: Date? }

struct InstructionItem: Codable { let id: UUID; var order: Int; var text: String }
```

### 9.4 Exercise library and taxonomy

**Shipped source of truth.** Do not create a second Cladiron-owned exercise
database or decoder. The package-backed DB++ snapshot supplies 873 exercises,
source imagery identifiers, evidence-audited direct/indirect/stabilizer roles, a
20-muscle ontology, volume eligibility/credits, and movement classification.
`exerciseId` is the stable join key for evidence and imagery. App models may add
backward-compatible optional fields and user-created exercises, but canonical
built-in taxonomy changes belong upstream in `free-exercise-db-plusplus`.

```swift
struct ExerciseKey: Hashable, Codable { let raw: String }  // stable key, e.g. "barbell_back_squat"

struct ExerciseDef: Codable {           // bundled, not synced
    let key: ExerciseKey
    var displayName: String
    var shorthandAliases: [String]      // "bench", "bp", "bb bench" — drives shorthand entry (§32.5)
    var kind: ItemKind                  // strength | cardio (mobility items are freeform)
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup]
    var movementPattern: MovementPattern
    var equipment: [Equipment]
    var defaultRepRange: ClosedRange<Int>?
    var isUnilateral: Bool
    var loadModes: [LoadMode]           // which LoadPrescription cases are valid
    var stimulusToFatigue: SFRTier      // low | moderate | high (§13.5)
}

enum MuscleGroup: Codable { case quads; case hamstrings; case glutes; case chest; case back; case lats; case traps; case frontDelts; case sideDelts; case rearDelts; case biceps; case triceps; case forearms; case calves; case abs; case obliques; case lowerBack; case neck /* ... */ }

enum MovementPattern: Codable { case squat; case hinge; case lunge; case horizontalPush; case verticalPush; case horizontalPull; case verticalPull; case carry; case rotation; case isolation; case cardioCyclic }

enum Equipment: Codable { case barbell; case dumbbell; case kettlebell; case machine; case cable; case bodyweight; case band; case ez; case trapBar; case cardioMachine(CardioActivity) /* ... */ }

enum ItemKind: Codable { case strength; case cardio }
enum LoadMode: Codable { case absolute; case percent1RM; case bodyweight; case bodyweightPlus; case assisted; case band; case machineSetting }
enum SFRTier: Codable { case low; case moderate; case high }
```

`shorthandAliases` is new in 2.0: it is what lets a trainer type `bench 4x8 @70% rpe8` on a phone and get the right exercise (§32.5). Aliases are bundled, localizable, and must be unambiguous within a locale (a CI check asserts no alias resolves to two exercises).

### 9.5 The exercise performance profile (e1RM and history)

Per athlete, per exercise:

```swift
struct ExercisePerformanceProfile: Codable {
    var exerciseKey: ExerciseKey
    var estimatedOneRM: Double?
    var estimatedOneRMUnit: WeightUnit
    var confidence: EstimateConfidence  // low | medium | high
    var source: EstimateSource          // testedByTrainer | submaximalSet | programmedSet | acceptedSuggestion | manual
    var derivedFrom: String?            // "175 lb × 4"
    var formula: OneRMFormula           // epley | brzycki | blended
    var updatedAt: Date
    var history: [OneRMEstimatePoint]   // dated estimate points for the trend
}

struct OneRMEstimatePoint: Codable { var date: Date; var weight: Double; var reps: Int; var rpe: Double?; var estimated: Double }
enum EstimateConfidence: Codable { case low; case medium; case high }
enum EstimateSource: Codable { case testedByTrainer; case submaximalSet; case programmedSet; case acceptedSuggestion; case manual }
enum OneRMFormula: Codable { case epley; case brzycki; case blended }
```

The engine may raise a **1RM update suggestion** (§14.3); the athlete/trainer accepts or ignores it — the profile is never silently overwritten.

### 9.6 Volume accounting

```swift
struct MuscleVolumeWeek: Codable {
    var muscle: MuscleGroup
    var weekStart: Date
    var directSets: Double              // sets where this muscle is primary
    var fractionalSets: Double          // sets where secondary (counted at 0.5 by convention)
    var totalSets: Double { directSets + fractionalSets }
}

struct VolumeLandmarks: Codable {       // per athlete, per muscle; individualized over time
    var muscle: MuscleGroup
    var mv: Int; var mev: Int; var mav: ClosedRange<Int>; var mrv: Int
    var basis: LandmarkBasis            // default (evidence-derived) | individualized (from history)
}
enum LandmarkBasis: Codable { case evidenceDefault; case individualized }
```

Volume accounting counts **only the owner's** working sets (`performer == .owner`); a partner's sets never contribute to the host's volume (§8.5).

### 9.7 Readiness and feedback signals

```swift
struct ReadinessSignal: Codable {       // optional; from HealthKit and/or self-report
    var date: Date
    var restingHR: Int?
    var hrvMillis: Double?
    var sleepHours: Double?
    var selfReportedReadiness: Int?     // 1–5 quick check
    var soreness: [MuscleGroup: Int]?   // 0–3 per muscle, optional
}

struct PainFlag: Codable { var present: Bool; var location: String?; var severity: Int?; var note: String? }  // severity 0–10
```

### 9.8 Templates and pre-made plans

```swift
struct PlanTemplate: Codable {
    let id: TemplateID
    var title: String
    var author: TemplateAuthor          // builtIn | user | trainer
    var goal: TrainingGoal
    var experienceLevel: ExperienceLevel
    var daysPerWeek: Int
    var equipmentProfile: [Equipment]
    var weeks: [PlanWeek]               // with %1RM / RPE prescriptions so it individualizes on instantiation
    var description: String
    var evidenceNotes: String?          // the rationale with citations
}
enum TemplateAuthor: Codable { case builtIn; case user; case trainer(TrainerRef) }
enum ExperienceLevel: Codable { case beginner; case intermediate; case advanced }
struct TemplateID: Hashable, Codable { let raw: UUID }
```

### 9.9 Set schemes (new in 2.0)

A **set scheme** is a named, parameterized generator for a whole set list. Schemes are the primary authoring accelerator on iPhone (§32.4) and the "Apply Pyramid…" replacement on iPad; both surfaces use the same type.

```swift
struct SetScheme: Codable {
    let id: SetSchemeID
    var displayName: String             // "5×5", "Top set + 2 back-offs", "Ascending pyramid", "3×8–10"
    var kind: SchemeKind
    var params: SchemeParams            // sets, reps/range, %/RPE ladder, rest, warm-up ramp on/off
    var isBuiltIn: Bool
    var goalAffinity: [TrainingGoal]    // used to order the picker for the current session goal
}

enum SchemeKind: Codable {
    case straightSets            // N × reps at one load/effort
    case doubleProgressionRange  // N × min–max reps at one load
    case topSetBackoffs(backoffPercentOfTop: Double)
    case ascendingPyramid        // rising %, falling reps
    case descendingPyramid
    case wave                    // e.g. 3 waves of 3
    case emom                    // time-structured (maps to duration reps)
    case custom
}

struct SchemeParams: Codable {
    var workingSets: Int
    var repTarget: RepTarget
    var effort: EffortSpec?             // .rpe(Double) | .rir(Int) | .none
    var loadSpec: LoadSpec              // .percentOfE1RM([Double]) | .absolute(Double) | .rpeOnly | .inherit
    var restSeconds: Int?
    var includeWarmupRamp: Bool
}
struct SetSchemeID: Hashable, Codable { let raw: String }
```

Applying a scheme is a single undoable action that replaces (or appends to) an item's `sets` and records `schemeApplied`, so the UI can offer "re-apply with different parameters" without the author reconstructing intent by hand.

### 9.10 Client relationship (trainer mode)

```swift
struct ClientRelationship: Codable {    // trainer-side; lives in the shared zone
    let id: UUID
    var displayName: String
    var connectedAt: Date?
    var status: ClientStatus            // invited | active | paused | archived
    var deliveryMode: ClientDeliveryMode
    var shareZoneID: String?            // present only for connectedCladiron
    var externalDelivery: ExternalClientDelivery?
    var notes: String?
    var goal: TrainingGoal?
    var experience: ExperienceLevel?
    var equipmentProfile: [Equipment]
    var injuries: [InjuryNote]
    var unitPreference: WeightUnit
    var equipmentIncrements: RoundingProfile   // §31.4
    var colorTag: RosterTag?            // trainer-chosen tint for fast visual scanning of the roster
}
enum ClientStatus: Codable { case invited; case active; case paused; case archived }
struct InjuryNote: Codable { var area: String; var note: String?; var avoidPatterns: [MovementPattern]; var recordedAt: Date }
```

`archived` is new: a removed client whose history the trainer keeps for their own records. **Archived clients do not count toward the Pro gate** — ending a coaching relationship must never feel like it is being billed (§44.3).

Delivery is orthogonal to client identity. A client may use automatic Cladiron
sharing or receive portable packets on any device; both are Pro clients and both
use the same `Plan`, prescription, review, and result types:

```swift
enum ClientDeliveryMode: String, Codable { case connectedCladiron, external }
enum ExternalShareChannel: String, Codable { case email, messages, other, print, file }
enum ExternalReportStatus: String, Codable {
    case notRequested, awaitingReply, receivedNeedsEntry, recorded
}
struct ExternalClientDelivery: Codable {
    var emailAddress: String?            // trainer-entered; never Contacts-derived
    var preferredChannel: ExternalShareChannel?
    var lastPacketID: UUID?
    var lastPacketVersion: Int?
    var lastPreparedAt: Date?
    var lastSharedAt: Date?              // user/composer action, not delivery proof
    var lastReportedAt: Date?
    var reportStatus: ExternalReportStatus
}
```

Add `deliveryMode` and optional `externalDelivery` to `ClientRelationship`.
`shareZoneID` and `connectedAt` become optional because an external client has no
CloudKit share. Switching modes preserves locally owned plans and manually
recorded results; disconnecting an active share requires explicit confirmation.
Full packet/report types and invariants are normative in Appendix Z.

### 9.11 Partner sessions (new in 2.0)

```swift
enum PerformerRef: Codable {
    case owner
    case partner(PartnerRef)
}

struct PartnerRef: Codable, Hashable {
    let id: UUID
    var displayName: String             // "Chris"
    var linkedCadenceUser: Bool        // true if this partner also uses Cladiron and accepted a session link
    var colorIndex: Int                 // for the rotation UI
}
```

Rules:

- A `Session` may carry 0..3 `partners`. Every `SetResult`/`CardioResult`/`MobilityResult` records its `performer`.
- **Rotation execution** (Watch and phone) advances performer-by-performer within a set index, which is how people actually train together: A's set 1, B's set 1, A's set 2, …
- Prescriptions can be **shared** (both lifters run the same item) or **per-performer** (an item may carry `performerOverrides: [PartnerRef: [PrescribedSet]]`, which is how two lifters share a bar-and-rack but not a load).
- **Volume/e1RM isolation:** the owner's analytics use only `performer == .owner`. If the partner is a linked Cladiron user, their sets mirror into their own private store as `selfAuthored` results.
- **No share, no roster, no gate.** Partner sessions never create a `ClientRelationship` and never require Pro. Promoting a partner to a client is an explicit, gated action.

### 9.12 Entitlement (new in 2.0)

```swift
struct ProEntitlement: Codable {
    var state: EntitlementState
    var productID: String?              // guru.parso.cladiron.pro.annual | .monthly | .lifetime
    var expiresAt: Date?                // nil for lifetime
    var isInTrial: Bool
    var trialEndsAt: Date?
    var lastVerifiedAt: Date
}

enum EntitlementState: Codable {
    case free                           // full athlete experience; no clients
    case trial(daysRemaining: Int)      // full Pro, 30 days
    case pro                            // active subscription or lifetime
    case proExpiredGrace                // lapsed: read-only trainer surfaces (§44.6)
}
```

The resolver lives in `CadenceCore` and is the **single** place any surface asks "may this user do trainer work?" — there is no ad-hoc gating in views (§44.5). Its answer is a `TrainerCapability` set (`viewRoster`, `authorForClient`, `sendPlan`, `inviteClient`, `exportRoster`), which makes the grace-period and trial behaviours expressible without scattering conditionals.

## 10. Persistence, sync, and plan provenance

### 10.1 Local persistence (SwiftData)

Each device persists to a **SwiftData** store owned by CadenceCore, mirrored to the user's private CloudKit database (§10.2). The `@Model` types mirror the domain model in §9: `Plan`, `PlanWeek`, `PlanDay`, `Session`, `SessionPartner`, the item family (`StrengthItem`, `PrescribedSet`, `CardioItem`, `MobilityItem`, `InstructionItem`), the result family (`SetResult`, `CardioResult`, `MobilityResult`), `ExercisePerformanceProfile`, `OneRMEstimatePoint`, `MuscleVolumeWeek`, `VolumeLandmarks`, `ReadinessSignal`, `PainFlag`, `PlanTemplate`, `SetScheme`, `ClientRelationship`, and `EngineRationale`. The citation registry and exercise library are **bundled read-only data, not model entities** — they never sync.

> **Decision note.** v1.0 specified GRDB/SQLite with a hand-written CloudKit sync layer, principally over watchOS+CloudKit reliability concerns. The shipping app **reversed that on 2026-07-27** and now mirrors SwiftData to CloudKit via `NSPersistentCloudKitContainer`, in production, including on watchOS. This specification follows the shipped architecture rather than asking for a persistence rewrite (Q.1). The two hard sync rules that motivated much of the original analysis — snapshot-at-send and no-sync-during-a-runtime-session — are **retained unchanged**, because they are correctness rules about *when* to sync, not about which store you use.

**CloudKit-compatibility constraints** (these are hard, and they shape §9): every mirrored property is optional or has a default; relationships are optional and have inverses; no `@Attribute(.unique)`; each entity carries a stable `UUID`, an `updatedAt`, and an `originDevice`. Domain enums with associated values (`LoadPrescription`, `CardioIntensity`, `RepTarget`, `PlanProvenance`, `PerformerRef`, `SchemeKind`) persist as a discriminator plus a `Codable` payload — the mapping is chosen once and never changed casually, because changing it is a migration.

The persistence layer is deterministic: cache keys use SHA-256 (never Swift `Hasher`, which reseeds per launch); **schema changes are additive only** (optional/defaulted, no destructive migration) so older stores and older JSON exports keep working; the store is the device source of truth.

### 10.2 Single-user cross-device sync

A user's own data syncs across their devices by mirroring the SwiftData store to the user's **private** CloudKit database (`cloudKitDatabase: .private`, container `iCloud.guru.parso.ios-workout-app`). Apple is the processor; the platform operates no server and never sees the data, so the **Data Not Collected** privacy label is unaffected (§43).

Mirroring is last-writer-wins per property at the framework level, so the invariants the product depends on are enforced **above** it, in CadenceCore:

- **Results are append-only.** A `SetResult`/`CardioResult`/`MobilityResult` is inserted, never mutated by a later edit or by a remote change. This is a domain rule with a test (§50), not a framework behaviour.
- **Plan edits** are last-writer-wins, which the framework already gives; drafts additionally carry a `lastEditedBy(deviceID, at:)` stamp so the UI can say something useful (§46.2).
- **e1RM** updates merge, with the trainer's acceptance authoritative for future %1RM prescriptions.
- **A sent plan is immutable in the ways that matter** because its %1RM loads were snapshotted at send (§10.4).

For a trainer, the private database also carries **the roster, drafts, templates, and rounding profiles**, which is what makes the "start on iPad, finish on iPhone, review on the Mac" loop real — and what makes "add a client from any device" (§49.25) a property of the architecture rather than a feature to build three times. Because a draft plan can be open on two devices at once, the UI surfaces a non-modal "also being edited on your iPad" note rather than locking (§46.2).

**Trainer↔client sharing is separate.** Delivery to a *client's* device uses CloudKit **sharing** with an explicitly managed per-client zone (§10.3, §42) — that path is not automatic mirroring and CadenceCore owns it. The split is deliberate: mirroring for *your own* devices, explicit sharing for *other people's*.

### 10.3 Trainer↔client sync (CloudKit sharing)

Full detail in §42. In summary: the trainer owns one **custom `CKRecordZone` per client** and a `CKShare` on it with the client as a read-write participant. The trainer writes the plan into the zone; the client's app reads it and writes back results and e1RM updates. Identity is the users' Apple IDs; no custom accounts; no server. **Every device the trainer owns can do this** — the share is owned by the Apple ID, not by a particular machine, which is another reason the Mac-only trainer app was unnecessary.

### 10.4 Plan provenance across the boundary

When a trainer sends a plan:

1. The plan's `provenance` is `trainerAuthored(trainer:)`.
2. Its `%1RM` loads are **resolved to concrete weights and snapshotted** into `calculatedWeight` from the client's current e1RM at send time (§13.3), so the client sees concrete numbers and they don't drift.
3. It appears in the client's **Plan tab** as an incoming plan attributed to the trainer, with edit locked.
4. Results the client logs sync back into the same zone; the trainer's review reads them.

When the athlete self-authors, provenance is `selfAuthored`, edit is unrestricted, and there is no cross-user zone. A template instantiation is `templateAuthored` and then editable by whoever instantiated it.

### 10.5 Offline behaviour

All planning, execution, logging, review, and export work offline against the local store. Sync is additive and eventually-consistent. On the Watch specifically, execution never depends on connectivity: local records and pending WatchConnectivity payloads survive disconnection, and the phone applies them idempotently before its normal CloudKit path.

**Entitlement offline:** `ProEntitlement` is cached with its last verification date and remains valid offline for a generous window (14 days) before degrading to `proExpiredGrace`. A trainer on a gym floor with no signal never loses access to their roster (§44.6).

---
---

# PART III — THE SCIENTIFIC COACH EXPERT SYSTEM

This is the heart of the platform. The expert system is what lets a self-coached athlete program like they have a knowledgeable coach, and what lets a real trainer program faster and more defensibly. It is an **evidence-gated engine** — a deterministic knowledge base of published sport-science findings that generates, critiques, progresses, and adapts training, always with a cited rationale — wrapped by a natural-language interface that never makes the prescription decision itself.

**Tier note.** The entire expert system is **free** for planning your own training (Principle 10). Nothing in Part III is behind Cladiron Pro when the subject of the plan is the user themselves or a partner. Pro governs *who you may author for*, not *how good the help is* (§44.2).

## 11. Philosophy: evidence-based, evidence-gated

### 11.1 What "evidence-based" means here, concretely

Many products claim to be "AI-powered" or "science-based." In this platform the claim is operationalized: **every prescription rule the engine applies is tied to a specific, registered citation, and the system can show its work.** When the engine sets quad volume to 14 working sets per week, it can say *why* (that figure sits in the maximum-adaptive-volume band for trained lifters) and *on what basis* (the dose-response meta-regression literature), and it links the exact citations. When the evidence is genuinely mixed — as it is for the specific choice of periodization model — the engine says so and treats the choice as a **judgment call**, offering options rather than a false optimum.

This has three consequences for design:

1. **The knowledge base is explicit and inspectable** (§13), not implicit in a model's weights. It is a set of rules and parameters with citations, maintained as code and data in `CadenceCore`.
2. **The engine is deterministic and testable.** Given the same athlete state and request, it produces the same plan and the same rationale.
3. **Confidence is first-class.** Recommendations carry an `EvidenceConfidence` (strong / moderate / limited / judgmentCall) that is surfaced to the user. The engine never launders a judgment call as settled science.

### 11.2 Why not just an LLM?

A large language model can *sound* like an evidence-based coach, but for the safety-critical act of prescribing training to real people it has three disqualifying problems: it can hallucinate specific numbers and citations; it cannot guarantee determinism or testability; and it hides its reasoning inside opaque weights, so its output cannot be audited or gated. The platform therefore inverts the usual arrangement: **the deterministic engine prescribes; the LLM is an interface** that (a) parses a free-text request into a structured `PlanningRequest`, and (b) renders the engine's structured, cited rationale into readable prose. The LLM never chooses a load, a volume, an exercise, or a progression. This is Principle 2, and it is both a safety property and a genuine competitive counter-position: most competitors are shipping black-box "AI workout generators," which is exactly the liability-prone, undifferentiated approach this design rejects (§16).

### 11.3 Assist, don't replace

The engine **assists** an author; it does not replace them. A self-coached athlete remains the author of their plan; a trainer remains the coach of record. This is a product stance and a safety stance: the human is always in the loop, and the engine's outputs are proposals with rationale, never faits accomplis.

### 11.4 The engine's five jobs

1. **Generate** — draft a plan (session, week, or mesocycle) from a goal and constraints.
2. **Critique / audit** — inspect any plan (however authored) and flag problems: volume outside landmarks, muscle imbalances, missing movement patterns, unrealistic loads, inadequate rest, junk volume, overreaching risk.
3. **Progress** — from logged performance and e1RM, suggest the next load/volume step in the author's chosen progression model.
4. **Substitute** — swap an exercise for an alternative that preserves the training stimulus, with the least fatigue penalty.
5. **Autoregulate & detect deloads** — adjust prescribed load/volume in response to effort feedback (RPE/RIR) and readiness, and flag when accumulated fatigue warrants a deload.

Plus a sixth, cross-cutting output: **insights** (§14.6), evidence-based observations surfaced to help the athlete understand their training.

## 12. The EvidenceGate architecture

The EvidenceGate is the mechanism that enforces Principle 1 in code: **no prescription rule ships without a registered citation.**

### 12.1 The citation registry

`CadenceCore` contains a **citation registry**: a seeded, read-only table of `Citation` records, each with a stable `CitationID`, full bibliographic data, a **DOI or URL**, a one-line finding summary, and an `EvidenceConfidence`. Appendix A is the human-readable form. Every rule and parameter in the knowledge base references one or more `CitationID`s.

```swift
struct Citation: Codable {
    let id: CitationID                  // "pelland_2025"
    var authors: String
    var year: Int
    var title: String
    var venue: String
    var doiOrURL: String
    var finding: String                 // one-line summary of the relevant finding
    var confidence: EvidenceConfidence
    var kind: CitationKind              // metaAnalysis | rct | positionStand | textbook | practitionerFramework
}
enum CitationKind: Codable { case metaAnalysis; case rct; case positionStand; case textbook; case practitionerFramework }
```

`practitionerFramework` (e.g., the MEV/MAV/MRV volume-landmark framework) is a distinct, lower-tier kind: useful and widely used, but explicitly labelled as a practitioner model rather than a meta-analytic result, and surfaced as `moderate` or `limited` confidence.

### 12.2 Private-init prescriptions gated by evidence

Prescription-bearing types (e.g., a generated `PrescribedSet` or a `RationaleDecision`) use **private initializers** within `CadenceCore`. They can only be constructed through the engine's builders, and each builder path requires a non-empty set of `CitationID`s that resolve in the registry. A rule that would emit a prescription without a citation cannot compile a valid decision object.

**Scheme note.** `SetScheme` application (§9.9) goes through the same builders: a scheme is a *shape*, and the effort/rest/load defaults it fills in are cited rules (R-INT-2, R-RST-1). A user-authored custom scheme carries no engine claim and is labelled as the author's own choice rather than an engine recommendation — the UI must not attach citation chips to a hand-made scheme.

### 12.3 CI enforcement

1. **Citation-resolution check.** Every `CitationID` referenced anywhere in the knowledge base must resolve to a `Citation` in the registry; every registry entry must have a non-empty `doiOrURL`.
2. **Rule-coverage check.** Every knowledge-base rule module must attach at least one `CitationID` to each prescription it can emit.
3. **Alias-uniqueness check** (new in 2.0). Every `shorthandAlias` in the exercise library resolves to exactly one exercise per locale, so shorthand entry (§32.5) is deterministic.

These checks make "evidence-gated" a build invariant, not a documentation aspiration.

### 12.4 Versioning the knowledge base

The knowledge base is versioned (`KnowledgeBaseVersion`). Each plan's `EngineRationale` records the KB version that produced it, so a plan generated last year can be understood in terms of the evidence available then, and updates to the evidence base are auditable changes to a versioned artifact rather than silent shifts.

## 13. The knowledge base (encoded evidence)

This section specifies what the engine knows: the parameters, rules, and their citations. Citation IDs resolve in Appendix A.

> **Framing note.** The engine encodes *ranges and defaults*, individualized over time from the athlete's own data, not rigid universal numbers. Sport science gives population-level dose-response signals with substantial individual variability; the engine treats published values as starting points and adjusts to the individual as evidence from their logged training accumulates.

### 13.1 Training volume and volume landmarks

**Encoded rule.** The engine tracks **weekly working-set volume per muscle group** (warm-up sets excluded; a set counts as **direct** = 1.0 for its primary muscles and **fractional** = 0.5 for meaningful secondary muscles). It maintains four per-muscle **landmarks**, seeded from evidence-based defaults and individualized from the athlete's history:

- **MV (Maintenance Volume)** ≈ **6 sets/muscle/week** — enough to maintain, used in deloads/maintenance phases.
- **MEV (Minimum Effective Volume)** ≈ **4–8 sets/muscle/week** for trained individuals — the floor for growth.
- **MAV (Maximum Adaptive Volume)** ≈ **10–20 sets/muscle/week** for most muscles in trained lifters — the productive band where hypertrophy phases should live.
- **MRV (Maximum Recoverable Volume)** ≈ **18–25+ sets/muscle/week**, highly individual — the ceiling beyond which fatigue outstrips recovery.

Hypertrophy blocks are planned to sit in the **MAV** band and to **progress volume upward across a mesocycle** toward MRV, then deload. Strength blocks use lower per-muscle volumes at higher intensity. Beginners start nearer MEV.

**Evidence.** Weekly set volume shows a **robust dose-response relationship with hypertrophy** (and strength), with **diminishing returns** more pronounced for strength than hypertrophy — the largest and most current synthesis being the Pelland/Robinson et al. meta-regression [pelland_2025], building on the Schoenfeld/Ogborn/Krieger dose-response meta-analysis [schoenfeld_2017] and the IUSCA position stand [iusca_2021]. The **MV/MEV/MAV/MRV landmark framework** is a practitioner operationalization [rp_landmarks] that is *consistent with* the meta-analytic data but is itself a practitioner model, surfaced at `moderate` confidence. **Confidence:** dose-response **strong**; specific landmark numbers **moderate**.

**Design implications.** Volume is the engine's single most important programming lever and the basis of its most valuable insights and critiques. Because "more is not always better," the engine caps and progresses volume deliberately rather than maximizing it.

### 13.2 Intensity: load, the load–rep relationship, and goals

**Encoded rule.** The engine prescribes load three ways, treated as **complementary**: an **absolute weight**, a **percentage of e1RM**, or an **RPE/RIR target**. It uses a **load–rep continuum** as a heuristic mapping between goal, rep range, and relative load:

- **Maximal strength**: ~**1–6 reps** at roughly **≥ 85% 1RM**, lower per-muscle volume, longer rest.
- **Hypertrophy**: a **broad effective range** (~**5–15+ reps**, ~**60–85% 1RM**), with **volume and proximity to failure** mattering more than the specific rep number.
- **Muscular endurance**: **≥ 15 reps** at **< 60% 1RM**.
- **Power/speed**: low reps, submaximal loads moved with intent, **kept well away from failure**.

**Evidence.** The load–rep continuum and %1RM–rep relationships are standard S&C programming knowledge [nsca_essentials]. The key modern nuance — that **hypertrophy occurs across a wide range of loads/rep ranges provided sets are taken to a similar high effort** — is supported by the hypertrophy literature [iusca_2021, schoenfeld_2017]. **Confidence:** continuum **strong**; "effort/volume over exact rep range" **moderate-to-strong**.

### 13.3 %1RM, e1RM estimation, and load resolution

**Encoded rule.** Per exercise, the engine maintains an **estimated 1RM (e1RM)** from the athlete's best qualifying submaximal set, using **Epley** by default (`1RM = w × (1 + reps/30)`) with **Brzycki** (`1RM = w × 36/(37 − reps)`) available as a more conservative alternative, and a **blended** option; accuracy is best in the **~2–10 rep** range and degrades above ~10 reps. When load is prescribed as `%1RM`, the working weight is computed as **`round(e1RM × percent, equipmentIncrement)`** and **snapshotted at send/start**. e1RM is **never silently overwritten**; a qualifying performance raises an *update suggestion* (§14.3). The number is always presented as **estimated**.

**Evidence.** 1RM estimation from submaximal reps is standard and supported by validated prediction equations [nsca_essentials, epley_1985, brzycki_1993]. **Confidence:** **strong** in the low-rep range, **limited** at high reps.

### 13.4 Effort prescription: RPE, RIR, and the Helms scale

**Encoded rule.** The engine's primary effort language is the **Helms RPE 1–10 scale mapped to RIR**: **RPE 10 = 0 RIR**, **9 = 1**, **8 = 2**, **7 = 3**. RPE and RIR interconvert (`RPE = 10 − RIR`). Effort targets are used **alongside %1RM**: %1RM sets the planned load; the RPE target defines the intended proximity to failure, which **autoregulates** the actual load to daily readiness. The engine prescribes typical working effort in the **~1–3 RIR (RPE 7–9)** band, reserving true failure for occasional AMRAP/testing sets because **failure raises fatigue disproportionately to its stimulus benefit**.

**Evidence.** The Helms RPE-RIR scale [helms_2016] is the most common evidence-based load-prescription tool. RPE-prescribed loading is **non-inferior** to percentage-based loading in periodized, set-and-rep-matched programs [helms_2023]. **Confidence:** RPE-RIR as a tool **strong**; exact effort bands **moderate**.

### 13.5 Proximity to failure

**Encoded rule.** Goal-dependent:

- **Hypertrophy** — training **closer to failure increases growth**, with **diminishing (and possibly negative) returns very close to failure**; the productive band is roughly **0–3 RIR**, and the engine defaults working sets to **~1–3 RIR**.
- **Strength** — proximity to failure has a **negligible independent effect**; keep strength work shy of failure and prioritize load and specificity.
- **Power/speed** — keep sets **well away from failure**.

**Evidence.** The proximity-to-failure meta-regression [robinson_2024] found hypertrophy increases as sets are taken closer to failure while strength is negligibly affected; supporting RCT and review evidence shows **1–2 RIR matches failure** for hypertrophy in trained individuals [refalo_2024, refalo_2023]. **Confidence:** hypertrophy direction **strong**; exact optimum **moderate**; strength-negligibility **strong**.

### 13.6 Training frequency

**Encoded rule.** Distribute each muscle's weekly volume across **≥ 2 sessions/week** as a default when volume is moderate-to-high, but treat frequency as **secondary to total weekly volume** for hypertrophy. For **strength**, higher frequency carries a modest additional benefit with diminishing returns.

**Evidence.** In the dose-response meta-regression [pelland_2025], **frequency's effect on hypertrophy was compatible with negligible** once volume is accounted for, while **strength increased with frequency (diminishing returns)**. **Confidence:** "volume > frequency for hypertrophy" **strong**; frequency benefit for strength **moderate**.

### 13.7 Exercise selection and stimulus-to-fatigue

**Encoded rule.** Select exercises to (a) **cover the fundamental movement patterns** appropriate to the goal, (b) **hit the target muscles** with the planned weekly volume, and (c) favour a good **stimulus-to-fatigue ratio (SFR)**. Each `ExerciseDef` carries `primaryMuscles`, `secondaryMuscles`, `movementPattern`, `equipment`, and a coarse `stimulusToFatigue` tier used by the selector and the substitution engine. The engine ensures **balance** and flags gaps or imbalances in critique.

**Evidence.** Pattern coverage, muscle-targeted volume, and SFR-aware selection are standard evidence-informed programming principles [nsca_essentials, iusca_2021]; SFR is a practitioner framework [rp_landmarks]. **Confidence:** coverage & balance **strong**; SFR tiers **limited/moderate**.

### 13.8 Rest periods and tempo

**Encoded rule.** Rest by goal: **strength/power ~2–5 min**, **hypertrophy ~1.5–3 min**, **muscular endurance/conditioning ~30–90 s**. **Tempo** is modelled and can be prescribed but is treated as a **secondary variable** with low-visibility UI.

**Evidence.** Longer inter-set rest (≥ ~2 min) supports strength and hypertrophy by preserving per-set performance [schoenfeld_rest_2016, nsca_essentials]. **Confidence:** rest guidance **moderate-to-strong**; tempo importance **limited**.

### 13.9 Progressive overload models

**Encoded rule.** The engine supports several **progression models** (a `ProgressionIntent` on each `PlanWeek`/mesocycle):

- **Linear load progression** — add load when the top of the rep/RPE target is met.
- **Double progression** — progress reps within a range at fixed load, then add load and reset reps.
- **Percentage-based progression** — planned week-to-week %1RM increases.
- **RPE-/autoregulated progression** — hold an RPE target and let load float.
- **Volume progression** — add working sets week-to-week within the MAV→MRV band, then deload.

The engine reads **logged performance** and **e1RM trend** to compute the next step and to **flag stalls**.

**Evidence.** Progressive overload is the foundational driver of adaptation [nsca_essentials]; the specific model is largely interchangeable when overload is achieved [grgic_2017_periodization, williams_2017]. **Confidence:** overload **strong**; model superiority **limited**.

### 13.10 Periodization

**Encoded rule.** The engine **periodizes** because **periodized training beats non-periodized** for strength, and **treats the choice among models as a judgment call**:

- **Linear periodization (LP)**, **Daily/weekly undulating (DUP/WUP)**, **Block periodization**.

Default for a general trainee: a simple **accumulation → intensification → deload** mesocycle.

**Evidence.** **Periodized > non-periodized for strength** [williams_2017]. **LP vs DUP for hypertrophy: no meaningful difference** [grgic_2017_periodization]; volume-equated comparisons broadly similar [moesgaard_2022]. **Confidence:** "periodize" **strong**; model choice **judgmentCall**.

### 13.11 Deloads and fatigue management

**Encoded rule.** Deloads roughly every **4–8 weeks** (after an accumulation block, near MRV, or on stalling/overreaching), implemented as a week at **~MV volume** and/or reduced intensity. **Triggers:** sustained performance decline, rising actual-vs-target RPE, volume near/above MRV for multiple weeks, poor readiness, or a pain flag.

**Evidence.** Deloading is a **practitioner-consensus fatigue-management practice** [rp_landmarks, nsca_essentials]; direct trial evidence for specific protocols is limited. **Confidence:** value of fatigue management **moderate**; exact cadence/protocol **limited**.

### 13.12 Readiness and recovery signals

**Encoded rule.** When permitted, incorporate **readiness signals** — resting HR, HRV, sleep, self-reported readiness (1–5), soreness (0–3 per muscle) — as **soft modifiers**, never hard prescriptions. The engine is **conservative and non-alarmist** and never presents them as medical assessments (§18).

**Evidence.** Readiness-guided autoregulation has support as a fatigue-management approach; HRV-guided training shows some benefit but with noise and individual variability [nsca_essentials, helms_2023]. **Confidence:** **limited-to-moderate**.

### 13.13 Cardiorespiratory training and concurrent training

**Encoded rule.** Program cardio via **FITT** with intensity expressed as an **HR zone (1–5)**, **%HRmax**, **RPE**, **pace/speed**, or **power**, in three shapes: **steady-state**, **intervals**, **open**. For **concurrent training**, manage **interference** heuristically: separate hard cardio from lower-body strength, prefer **lower-impact modalities** around heavy leg work, and flag when cardio load looks likely to blunt strength/hypertrophy adaptations.

**Evidence.** FITT and HR/RPE intensity prescription are standard [acsm_guidelines]; ACSM maps **moderate ≈ RPE 3–4** and **vigorous ≈ RPE 5–7** on a 0–10 scale. The **interference effect** is well-documented [acsm_guidelines, nsca_essentials]. **Confidence:** cardio prescription **strong**; interference heuristics **moderate**.

### 13.14 Warm-up protocols

**Encoded rule.** Auto-generate **warm-up sets** for main lifts: an optional general raise plus **specific ramp-up sets** to the first working load, scaled by working intensity. Warm-up sets are typed `warmup` and **excluded from volume accounting**. Scheme application (§9.9) can include or omit the ramp with one toggle.

**Evidence.** Specific warm-up ramp-ups are standard practice [nsca_essentials]. **Confidence:** **moderate**.

### 13.15 Individualization

**Encoded rule.** Individualize every default by **experience level**, **goal**, **equipment profile**, **constraints & contraindications**, and **the athlete's own logged history**.

**Evidence.** Individual variability in dose-response is large across all variables [pelland_2025, robinson_2024, iusca_2021]. **Confidence:** the *need* to individualize **strong**; specific heuristics **moderate**.

### 13.16 Summary table of encoded parameters

| Domain | Default / range | Primary citations | Confidence |
|---|---|---|---|
| Weekly volume (hypertrophy, per muscle) | MAV 10–20 working sets; MEV 4–8; MV ~6; MRV 18–25+ | pelland_2025, schoenfeld_2017, iusca_2021, rp_landmarks | strong (dose-response) / moderate (landmarks) |
| Load–rep (strength) | 1–6 reps, ≥85% 1RM | nsca_essentials | strong |
| Load–rep (hypertrophy) | ~5–15+ reps, 60–85%; effort/volume dominate | iusca_2021, schoenfeld_2017, nsca_essentials | moderate-strong |
| Effort (working sets) | ~1–3 RIR (RPE 7–9); failure sparing | helms_2016, robinson_2024, refalo_2024 | strong (tool) / moderate (bands) |
| Proximity to failure (hypertrophy) | 0–3 RIR band, diminishing near failure | robinson_2024, refalo_2023, refalo_2024 | strong (direction) |
| Proximity to failure (strength) | negligible; stay 1–3 RIR | robinson_2024 | strong |
| Frequency | ≥2×/muscle/week; secondary to volume (hypertrophy) | pelland_2025 | strong |
| Rest | strength 2–5 min; hypertrophy 1.5–3 min; endurance 30–90 s | schoenfeld_rest_2016, nsca_essentials | moderate-strong |
| Periodization | periodize; model is a judgment call | williams_2017, grgic_2017_periodization, moesgaard_2022 | strong / judgmentCall |
| Deload | ~every 4–8 wk or on triggers; to ~MV | rp_landmarks, nsca_essentials | moderate-limited |
| Cardio intensity | zones/RPE/%HRmax; mod≈RPE 3–4, vig≈5–7 | acsm_guidelines | strong |
| Concurrent training | manage interference | acsm_guidelines, nsca_essentials | moderate |
| 1RM estimation | Epley/Brzycki; valid ~2–10 reps | epley_1985, brzycki_1993, nsca_essentials | strong (low reps) |

## 14. Assistance capabilities

Each capability returns proposals with a cited `EngineRationale`, never silent changes.

### 14.1 Generate — drafting a plan

**Input.** A `PlanningRequest`: goal, experience level, days per week, session-length budget, equipment profile, constraints/contraindications, preferences, optional horizon and periodization/progression preference. In the athlete app much of this is prefilled from profile and history; in trainer mode it prefills from the `ClientRelationship`. In natural-language mode the LLM parses the request into this struct (§16).

**Algorithm (outline).**
1. **Set weekly volume targets per muscle** from goal and individualized landmarks.
2. **Select exercises** to cover required movement patterns and hit per-muscle volume, filtered by equipment and contraindications, favouring good SFR and balancing opposing patterns.
3. **Distribute volume across the available days** (≥2×/muscle where volume is moderate-high), assembling Sessions and ordering items.
4. **Prescribe sets per exercise**: rep targets and load mode by goal, effort targets in the goal-appropriate RIR band, rest by goal, warm-up ramp sets for main lifts.
5. **Add cardio/mobility** if requested or goal-appropriate, managing concurrent-training interference.
6. **Apply periodization/progression** across weeks if a mesocycle.
7. **Attach the rationale**: for each material decision, a `RationaleDecision` with claim, basis, citations, and confidence.

**Output.** A `Plan` (draft) with a full `EngineRationale`. Deterministic given the same inputs and KB version.

### 14.2 Critique / audit — inspecting any plan

**Input.** Any `Plan`, however authored, plus the athlete's history.

**Checks (each emits a flag with severity, explanation, citations, and a suggested fix).** Volume out of range; imbalance; missing pattern; intensity/goal mismatch; effort mismatch; inadequate rest; junk volume/redundancy; frequency; concurrent-training conflict; progression sanity; contraindication.

**Output.** A prioritized list of `CritiqueFinding`s with fixes. In trainer mode this is a pass run before sending; in the athlete app the same checks run automatically while building, surfacing gently. Critique never edits the plan.

### 14.3 Progress — the next step

**Input.** The active plan/week, logged results, the e1RM trend.

**Algorithm.** Apply the active progression model (§13.9). Compute **e1RM update suggestions** when a set qualifies (~1–10 reps, actual load recorded, completed, RPE ≥8 or AMRAP, improvement beyond a ~2.5–5% noise threshold) and raise them for accept/ignore. **Flag stalls** and propose a response.

**Output.** A proposed next week (or next-session load nudges) with rationale, plus any e1RM update suggestions.

### 14.4 Substitute — stimulus-preserving swaps

**Input.** An exercise to replace and the reason (equipment unavailable, pain, preference, variety).

**Algorithm.** Rank library alternatives by same **movement pattern**, overlapping **primary muscles**, **equipment fit**, similar **load mode**, comparable or better **SFR**; penalize contraindicated options.

**Output.** Ranked substitutes with a "preserves / trade-off" note, one-tap apply. Used live on the Watch/iPhone and in planning.

### 14.5 Autoregulate, detect deloads — responding to fatigue

**Autoregulation.** Between sessions, the engine reads actual-vs-target RPE and readiness signals: if work is consistently harder than prescribed or readiness is poor, it biases the next session/week toward backoff — as a **proposal** with rationale.

**Deload detection.** The engine watches the deload triggers (§13.11) and proposes a deload week with a clear, non-alarmist explanation. The author accepts, defers, or ignores.

### 14.6 Insights — evidence-based observations

**Read-only observations**, surfaced on Home and in review, each tied to the evidence:

- Volume-landmark: "Chest weekly volume has been below MEV (~6 sets) for 3 weeks — below the growth threshold; consider adding 3–4 sets."
- Balance: "Your pulling volume is ~40% of your pressing volume this block."
- Progress: "Estimated squat 1RM up ~8% over 6 weeks." / "Bench e1RM flat for 4 weeks — a stall."
- Effort: "Most working sets last week were RPE ≤6 — you may be leaving stimulus on the table."
- Consistency/adherence: "You completed 4/5 planned sessions for 3 weeks running."
- Recovery (permissioned): "Sleep averaged 5.5 h and readiness dipped this week."

Insights are **surfaced sparingly** and never as medical claims. In trainer mode, insights are computed **per client** and feed the roster triage (§30.2).

## 15. Planning-assistant workflows

### 15.1 Self-coached assisted planning (Plan tab, any device)

1. Athlete taps **Plan with coach**.
2. A short, structured prompt (tappable choices): goal, days this week, session length, equipment, anything to avoid. Prefilled; editable. Natural-language entry optional (§16).
3. Engine **generates** a week, shown with a **"Why this plan"** summary and expandable per-decision rationale (§17).
4. Athlete **edits** freely. Critique runs live and flags issues gently.
5. Athlete **schedules/activates** the week. Execution proceeds on the Watch.
6. During/after the week, **Progress** and **Insights** surface suggestions for next week.

This is free on every device (Principle 10).

### 15.2 Trainer assisted planning (iPad, Mac, or iPhone)

1. The trainer selects a client, opens **New plan** (or adapts a template/prior week).
2. Optionally **generate** a draft from the client's goal/history, or build by hand; either way the full per-set fidelity is available — via the grid and keyboard on iPad/Mac (§31), or via schemes, the prescription bar, and shorthand on iPhone (§32).
3. The trainer runs **Critique** before sending; the engine flags issues with fixes; the trainer accepts or overrides.
4. The trainer **sends**; %1RM resolves to concrete weights and snapshots; the plan lands in the client's Plan tab as coach-authored.
5. After execution, the trainer **reviews** prescribed-vs-actual; the engine surfaces exceptions, e1RM update suggestions, and deload/progress proposals.

**Device-independence is a requirement, not a convenience:** step 2 must be completable on a phone. §49 criterion 12 tests exactly this.

## 16. The LLM-as-interface layer

### 16.1 Role and hard boundary

A natural-language layer makes the engine approachable ("build me a 4-day hypertrophy week, dumbbells only, my knees are cranky") without changing the engine's authority. Its **only** two jobs:

1. **Parse** free-text into a structured `PlanningRequest` (or a critique/substitution/progression request).
2. **Narrate** the engine's structured, cited `EngineRationale` into readable prose.

The LLM **never** selects a load, volume, exercise, progression, or deload. If parsing is ambiguous it asks a clarifying question or falls back to the structured prompt.

**Not to be confused with shorthand entry.** The iPhone/iPad shorthand parser (§32.5) is a **deterministic grammar**, not an LLM: `bench 4x8 @70% rpe8 r2:30` is tokenized and validated by code, with a live preview and no inference. Shorthand works offline, on every device, with no model available — and it is the primary fast path for authoring. The LLM is an optional convenience layer above it.

### 16.2 Where inference runs

- **On-device (Apple Foundation Models)** for light parsing/narration — free, private, offline. Used only for bounded interface tasks with structured output and a **Tool** interface calling the engine's typed functions.
- **Private Cloud Compute** for heavier requests, preserving privacy.
- Availability is a **feature flag**; when unavailable, the app uses the structured prompt UI, shorthand, and template-based narration — the engine works identically without the LLM.

### 16.3 Why this is safe and differentiated

Because the safety-critical decisions are deterministic, cited, and gated (§12), the LLM cannot hallucinate a dangerous prescription or a fake citation into the plan. This is a categorical safety improvement over "AI generates the workout," and a market counter-position that a GPT wrapper cannot occupy.

## 17. Explainability and citations

- **Plan level.** A one-paragraph "Why this plan" summary (`EngineRationale.summary`).
- **Decision level.** An expandable list of `RationaleDecision`s: the **claim**, the **basis**, the **confidence** chip, and **tappable citations** that open the registry entry.
- **Insight/critique level.** Each insight and finding carries the same explanation-plus-citation structure.
- **Honesty about confidence.** Judgment calls are visibly labelled, with alternatives noted.

**Surface rules by idiom.** On iPad/Mac the rationale lives in the third column and is visible while editing. On iPhone it is a **bottom sheet at medium detent** that can be dragged to full — reachable from the same "Why this plan" affordance, and *never* collapsed away entirely: a generated plan on a phone must display its rationale entry point at all times, so evidence is not a casualty of small screens.

## 18. Safety, liability, contraindications, and pain handling

### 18.1 The app is a training tool, not a medical device

Cladiron supports training decisions for generally healthy people; it does **not** diagnose, treat, or rehabilitate injury or disease, and it says so plainly in onboarding and where relevant.

### 18.2 Human in the loop, always

The engine proposes; a human disposes. No engine output is auto-delivered to a client unreviewed, and no algorithm silently changes a trainer's prescription. **This holds identically on a phone:** the compact-width "Generate → Send" path always interposes a review step, and Send is never a single tap from Generate (§32.9).

### 18.3 Contraindications and pain

- **Injury/limitation profile.** The athlete (or trainer) records injuries/limitations and movements to avoid. The engine **filters exercise selection and substitution** and critique flags contraindicated movements.
- **Pain flag.** After any exercise or session, the athlete can flag pain (location, 0–10 severity, note). A pain flag surfaces prominently to the trainer, biases the engine toward substitution/backoff, and at higher severities prompts the app to **recommend stopping and consulting a professional**. The engine does **not** diagnose.
- **Conservative defaults** for beginners and sparse data.

### 18.4 Effort and failure safety

The engine **defaults away from failure** (working sets in the ~1–3 RIR band), reserves RPE-10 work for controlled contexts, and never prescribes grinding failure on high-skill or high-risk lifts by default.

### 18.5 Data-driven guardrails

- Implausible inputs are flagged for confirmation rather than silently propagated into %1RM prescriptions.
- The %-snapshot-at-send rule prevents a stale or updated e1RM from silently changing a live prescription mid-block.
- The append-only logging rule ensures a real logged set is never overwritten.
- **Shorthand safety:** the shorthand parser never guesses across an ambiguity threshold. `sq 5x5 @315` with two matching aliases yields a disambiguation chip row, not a silent pick (§32.5).

---
---

# PART IV — THE ATHLETE EXPERIENCE (iPHONE-FIRST, FREE)

This part specifies the self-coached experience: the app restructured from an **always-on live coach** into a **manual + assisted weekly planner**, aligned with the unified planning model (§8) and powered by the same expert system as trainer mode (Part III). Everything in this part is **free forever, with no upsells in these surfaces** (Principle 10, §44.2). It is described iPhone-first because that is where most athletes live; §20.4 covers how it expands on iPad.

## 19. The restructure: retiring the always-on coach

### 19.1 What is being removed

The **always-on live coach** — the reactive, in-the-moment coaching surface — is **retired**:

- The persistent "live coach" home surface and its real-time, set-by-set improvised suggestions.
- Any prescription behaviour that generated training in the moment rather than from a plan.
- The framing of the app as a companion that reacts continuously rather than a tool you plan with.

### 19.2 What is retained (and evolved)

- **Insights** are retained and evolved into evidence-based `Insight` cards (§14.6, §26).
- **Per-muscle progress** is retained and **moved to the Home page** (§21, §25) as a primary element.
- **Execution on the Watch** is retained and now driven by the **plan** (Part VI), including **partner rotation** (§23).
- The **expert system** is retained but repositioned: it **assists planning** and produces insights instead of improvising live.

### 19.3 What is added

- A **Plan tab**: the weekly planner where the athlete fully plans their week — by hand, from pre-made plans, or with expert-system assistance (§22).
- **Plan provenance**: a plan can come from **the user themselves or their personal trainer** (§24).
- **Partner sessions** as a first-class, free capability (§23).
- The **Home page** reconceived to show **the plan and progress** instead of a live coach (§21).

### 19.4 Rationale (recap)

The live coach conflated planning with execution, encouraged compulsive engagement over athlete agency, and did not map to the trainer product. A weekly planner fixes all three and makes the athlete app the same shape as trainer mode, so one engine and one plan object serve both.

### 19.5 What stays the same for the user's data

The restructure is a **UI and workflow change, not a data reset**. Existing logged history, exercise performance profiles (e1RM), and 20-muscle progress are preserved and migrated (§28.3).

## 20. Information architecture

### 20.1 The athlete tab set (compact)

Four tabs on iPhone:

1. **Home** — the plan (today + week) and per-muscle progress at a glance, with the top insight(s). The default tab. (§21)
2. **Plan** — the weekly planner: view/edit the current week, plan the next, use pre-made plans, plan with the coach expert system, browse insights. (§22)
3. **Progress** — per-muscle development, e1RM trends, volume vs landmarks, adherence, personal records. (§25)
4. **Profile / Settings** — goals, experience, equipment, injuries/limitations, units, HealthKit permissions, partners, trainer connection, **Trainer mode**, export, privacy.

**Execution** is not a persistent tab; it is entered by starting today's session and presents a focused session-runner (Part VI) with a Live Activity.

### 20.2 Where Trainer mode lives

Trainer mode is **not a fifth tab** for free users. It appears in Profile as a single row — *"Coach someone else"* — which explains the capability and the tier honestly. Turning it on (after Pro or trial starts) adds a **Clients** tab in position 2, shifting the athlete tabs right; the athlete surfaces are never removed or degraded. Turning it off returns the four-tab layout and leaves all roster data intact.

This ordering is deliberate: a coach's own training does not stop being important because they coach, and a trainer's Home page is still *their* Home page, not a business dashboard.

### 20.3 Rationale for the IA

The IA mirrors the mental model "see my plan and progress (Home) → plan my training (Plan) → understand my progress (Progress) → configure (Profile)," replacing "be coached live (old Home)."

### 20.4 The athlete app on iPad

On `regular` width, the athlete experience becomes a **two-column** layout: a sidebar with the four destinations (plus Clients in trainer mode) and a content column. The Plan tab shows the **week as a 7-column board** rather than a vertical list, with a session's items in a detail pane; the per-set editor uses the same **grid** as trainer mode (§31.3), because an athlete with a keyboard deserves the same speed a trainer gets. Everything else is a resize. There is no iPad-exclusive athlete capability and no iPhone-exclusive one.

## 21. The Home page (plan + progress)

Home answers **"what am I doing today (and this week)?"** and **"how is my training going?"**, and surfaces the single highest-signal insight. It contains **no live coach** and **no paywall**.

### 21.1 Sections (top to bottom)

1. **Today.** The current day's session(s): title, item summary ("5 exercises · ~52 min · incl. cardio"), status, and a prominent **Start**. Rest day gets a calm state with an optional light-activity suggestion. A session in progress gets a resume affordance and Live Activity. If the session has partners, their initials appear as a rotation chip.
2. **This week.** A compact 7-day strip: each day's planned session (or rest), completion status (done / upcoming / missed), today highlighted, and a week summary ("3/5 sessions done"). Tapping a day opens it in Plan.
3. **Muscle progress.** Compact `MuscleGroup` indicators show recent development and volume-vs-landmark status (below MEV / in MAV / near MRV). Tapping opens Progress (§25); broad regions are never the analytical unit.
4. **Top insight.** The single most relevant `Insight` card with its action button. At most one or two here.
5. **Plan provenance banner** (contextual). "This week's plan is from Coach Dana," only when trainer-authored.

### 21.2 Behaviour

- Home is **read-first**: it shows state and the day's action; editing happens in Plan. The primary action is **Start today's session**.
- Home reflects provenance transparently but treats trainer- and self-authored plans identically in layout.
- Empty state (new user, no plan): Home invites the athlete to **create a plan** — never to "start being coached live," and never to subscribe.
- **In trainer mode**, Home stays the trainer's *own* training page. Client status lives in the Clients tab; the only concession is an optional single line at the bottom — "3 clients need attention" — which is a navigation affordance, not a dashboard.

## 22. The Plan tab (manual + assisted weekly planner)

The Plan tab is the app's center of gravity and the athlete-facing sibling of the trainer planner. It offers three complementary paths that interoperate: **manual**, **pre-made plans**, and **coach-expert-system assisted** — plus **insights** integrated throughout.

### 22.1 Structure

- **Week view.** The current week as seven days; each day shows its planned session(s) or rest. The athlete can add/remove/reschedule sessions, edit a session's items and sets, and see the week's volume balance. A segmented control switches **This week** / **Next week** (history read-only). Mesocycle context appears as a small phase indicator ("Accumulation · week 2 of 4").
- **Session editor.** Opening a session reveals its ordered items; opening a strength item reveals its **set stack** on compact width or its **per-set grid** on regular width — the same model, two densities (§32.3, §31.3).
- **Plan actions** (top of the tab): **Plan with coach**, **Use a pre-made plan**, **New blank week**, **Repeat last week**, **Insights**.

### 22.2 Manual planning (the athlete builder)

The athlete can build entirely by hand, with the same expressive power the trainer has:

- **Add items**: `+ Strength`, `+ Cardio`, `+ Mobility`, `+ Instruction`.
- **Strength item**: choose an exercise from the bundled library (searchable, filterable by muscle/pattern/equipment), then edit its sets — each with **type** (warm-up/working/back-off/AMRAP/drop), **reps** (exact/range/AMRAP/duration/distance), **load** (absolute / **%1RM** with computed weight / bodyweight / band / machine / assisted / RPE-only), **RPE or RIR** target, and **rest**.
- **Fast paths**: **set schemes** (§9.9) such as `5×5`, `3×8–10`, `Top set + back-offs`, `Ascending pyramid`; **duplicate set**; **set-all-rest**; **shorthand entry** (§32.5) — all available to athletes, not just trainers.
- **Cardio item**: steady / interval / open, with modality, duration/distance, and intensity (HR zone / %HRmax / RPE / pace / power).
- **Mobility item**: name, rounds × timed/reps, each-side.
- **e1RM visibility**: when prescribing %1RM, the athlete's e1RM is shown and the computed weight appears beside the percentage; overriding the weight keeps the % intent.
- **Reorder / reschedule**: drag items within a session; move a session to another day by drag (regular) or **Move to day…** (everywhere).

### 22.3 Coach-expert-system assisted planning

- **Plan with coach** opens a short structured prompt (tappable goal, days, session length, equipment, avoid-list; prefilled from profile/history; optional natural-language entry).
- The engine **generates** a week with a **"Why this plan"** summary and expandable, cited rationale (§17).
- The athlete **edits** the generated week freely. **Critique** runs live and flags issues gently.
- **Progress assistance**: when planning next week, the engine proposes the next step from logged performance and e1RM, including e1RM update suggestions and any deload proposal.
- Assisted and manual are not modes to choose up front — generate then hand-edit, or hand-build then ask for a critique, freely.

**Free.** Generation, critique, progression, substitution, autoregulation, deload detection, and insights are all included at no cost when the plan is for the user (or their partner). There is no "unlock the coach" moment anywhere in this flow.

### 22.4 Pre-made plans

- **Use a pre-made plan** opens a browsable library of built-in templates (Appendix J), filterable by goal, experience level, days/week, and equipment. Each shows its structure and an **evidence note** with citations.
- Selecting a template **instantiates** it: %1RM loads resolve from the athlete's e1RM (prompting where unknown), provenance is `templateAuthored`, and it becomes **editable**.
- The engine can **individualize** a template on instantiation and explains what it changed.
- Athletes can **save their own** weeks/mesocycles as reusable templates.

### 22.5 Insights in the Plan tab

Beyond the single top insight on Home, the Plan tab hosts the **full insights view** (§26): current evidence-based observations, each with explanation, citation, and (where actionable) a button that stages a suggested change.

### 22.6 Scheduling and repeats

- **Reschedule** a session to another day (content unchanged).
- **Repeat** operations: repeat a session on selected days; repeat last week; carry a mesocycle forward with the engine applying the next week's progression.
- **Missed sessions** are tracked and feed adherence/insights; the athlete can move or drop them.

## 23. Partner sessions (free tier)

Training with a partner is a normal part of strength training and is explicitly **free** (§8.5). It is specified here because it is the capability most likely to be confused with coaching, and the distinction carries the business model.

### 23.1 Adding a partner

From a session (Plan tab or the Watch), **Add partner** offers: a name typed in place, a recent partner, or — if the partner also uses Cladiron — **Link** via a proximity/AirDrop-style handoff that connects the two apps for this session only. Linking is per-session and revocable; it creates no roster entry, no share, and no ongoing relationship.

### 23.2 Prescription sharing

An item can be:

- **Shared** — both lifters run the same prescription (default when the partner is unlinked; the app just needs somewhere to put their reps).
- **Per-performer** — each lifter gets their own sets via `performerOverrides` (§9.11). The editor shows a performer segmented control at the item header; switching it swaps the visible set stack/grid. For linked partners, per-performer %1RM resolves against **each lifter's own e1RM**, which is the whole point of linking.

### 23.3 Rotation execution

The runner (phone and Watch) advances **performer-by-performer within a set index**: A set 1 → B set 1 → A set 2 → …. The current lifter is shown in the largest type on the Watch with their colour; the rest timer is per-lifter and the app knows that B's set is A's rest. Sets are logged to the right `performer` automatically; a mis-tap is fixable from the set row.

### 23.4 Data separation

- The host's analytics (volume, e1RM, insights, progress) use **only** `performer == .owner`.
- A **linked** partner's sets mirror into their own app as their own `selfAuthored` results, feeding their own analytics.
- An **unlinked** partner's sets are retained inside the host's session record (so the session is a truthful record of what happened) and excluded from every host-level roll-up.
- Partner names are local strings; nothing about a partner is written to CloudKit sharing unless they are linked, in which case only the session's result records cross, in their own private database.

### 23.5 Promoting a partner to a client

If the host wants to *program for* the partner rather than train beside them, **Make a client** converts the `PartnerRef` into a `ClientRelationship` — which triggers the invite/share flow and the **Pro gate** (§44.3). The app states the difference plainly at that moment rather than letting the user discover it later: *"Partners train with you. Clients get plans from you on their own device — that's Cladiron Pro."*

## 24. Plan provenance in the athlete app

### 24.1 Self-authored (default)

Provenance is `selfAuthored`; the plan is fully editable; sync is single-user private only.

### 24.2 Trainer-authored (connected mode)

If the athlete connects with a personal trainer (§42), the trainer can send plans that appear in the athlete's Plan tab:

- Shown in the week view **attributed to the trainer**, with a subtle provenance banner on Home.
- The prescription is **execute-only for the client by default**: the athlete logs actuals and follows the plan. If the trainer enabled it, the athlete can **request a change**, but authority remains the trainer's.
- The athlete's **execution, logging, progress, insights, and export are identical** to self-authored.
- The athlete can **switch between** following their trainer's plan and self-planning; the model supports mixed weeks, though the default is clean separation.
- **The client pays nothing and sees nothing to buy.** A coached client's app has no paywall, no trial prompt, no Pro badge (§44.2).

### 24.3 Connecting and disconnecting

- **Connecting**: the athlete accepts a share invite (a link in Messages/Mail; §42). No account is created; identity is the Apple ID.
- **Disconnecting**: the athlete can end the relationship at any time; their historical data remains theirs (local + exportable), and they revert to self-authoring.

## 25. Progress and the per-muscle dashboard

Training-performance-based; no body measurements or photos.

### 25.1 Per-muscle progress (primary)

- A **body map / per-muscle view**: each major muscle group shows a **development trend** and a **volume-vs-landmark status** for the current week/block, using individualized landmarks.
- Tapping a muscle shows its detail: recent weekly volume vs landmarks, the contributing exercises, and the trend.
- This is the view summarized on Home and expanded here.

### 25.2 Strength progress (e1RM trends)

- Per-exercise **estimated 1RM trends** with confidence indication and the basis of the latest estimate.
- **Personal records** (best e1RM, best set) per exercise.

### 25.3 Volume and adherence

- **Weekly volume** per muscle vs landmarks over the block.
- **Adherence**: planned vs completed sessions over recent weeks.

### 25.4 How progress connects to planning

Every progress element is a potential **insight** and a potential **plan action**. The loop is: execute → progress updates → insights surface → plan next week.

## 26. Insights (retained)

Surfaced in three places: the **top insight on Home**, the **full insights view in Plan**, and **inline in Progress**.

- **High-signal and sparse.** One or two prominently; don't nag.
- **Evidence-anchored and honest.** Plain language, a citation, an honest confidence; never a medical claim.
- **Actionable where possible.** An insight that implies a plan change offers a button that stages it.
- **Not a live coach.** Reflective observations about training over time, not set-by-set nudges.

## 27. Execution from the plan

- The athlete starts **today's planned session** from Home (or directly on the Watch). The session-runner presents each item and set **from the plan**, in order, with prescribed reps/load/%e1RM/RPE/rest.
- The athlete **logs actuals** set-by-set; cardio runs against its target with live HR; mobility is checked off; partner rotation advances per §23.3.
- A **Live Activity / Dynamic Island** shows the current set and rest timer.
- On finish, results are saved locally (append-only), progress/insights update, and — if connected to a trainer — results sync back under the sync-timing rule.
- Execution is identical whether the plan is self-, template-, or trainer-authored, and whether the user is free or Pro.

## 28. Onboarding, first-run, and migration

### 28.1 New-user onboarding

1. **Welcome + scope note**: what the app is and what it is not (§18).
2. **Profile basics**: primary goal, experience level, days/week, equipment, units, anything to avoid.
3. **HealthKit permission** (optional): heart rate for cardio; recovery signals for readiness insights.
4. **First plan**: three doors — **plan with coach**, **use a pre-made plan**, or **build my own**.
5. **Watch setup** prompt for execution.

No step mentions purchasing. The first time Pro is mentioned at all is when the user asks for something that involves another person's device (§44.3).

### 28.2 First-run for a connected client

Shorter: accept the trainer share (§42), confirm units/Health permissions, land on Home showing the trainer's first plan. No goal/equipment interrogation is required, though the profile can still be filled for the athlete's own progress/insights.

### 28.3 First-run for a trainer

A user who arrives intending to coach (from the App Store listing, a referral, or by tapping "Coach someone else") gets a **second, additive onboarding**: display name as it will appear to clients, units, default rounding profile, and a one-screen explanation of the invite flow and what the client sees. It ends at **Add your first client**, which is the moment the trial starts (§44.3). Their own athlete profile is still requested (or skipped) separately — a coach is usually also a lifter.

### 28.4 Migration from the always-on-coach version

- **Data preserved.** All logged history, exercise performance profiles (e1RM), and canonical per-muscle progress carry forward unchanged, via an explicit versioned migration.
- **A one-time explainer.** "Coaching is now a planner — plan your week by hand, from a template, or with the coach's help; your history and progress are all here."
- **Insights continuity.** Retained insights immediately reflect existing history so the new surfaces feel populated.
- **No loss of capability.** Anything the live coach effectively did is now available — and better — through the planner's assistance and insights.
- **Entitlement continuity.** Users who previously purchased Cladiron Pro under the old packaging (which gated the coach's prescription) **keep everything they had and gain the new free-tier scope**; their existing purchase grants Trainer mode. No previously-paid capability is removed, and no previously-free capability becomes paid (§44.8).

---
---

# PART V — THE TRAINER SURFACE (iPAD, MAC, iPHONE)

> **v2.6 status: historical, non-normative.** This entire former trainer
> surface is retained for decision history only. Do not implement Trainer mode,
> clients, rosters, human-coach delivery, Pro gates, or trainer-specific Mac
> work. Active authoring is the user's own manual/template plan plus automated
> coach suggestions.

Trainer mode is the professional configuration of the same app: manage a roster of clients, plan for each with the full expert-system-assisted planner, review what clients actually did, maintain reusable templates, and export everything. v1.0 put this on a separate native Mac app; v2.0 puts it **on every device the trainer owns**, at three interaction densities that produce identical output (§2.3, §7.5).

This part is organized so that §31 (iPad) is the reference implementation, §32 (iPhone) is the compact-width re-expression, §33 is the command system they share, and §38 is what changes when the iPad build runs on a Mac.

## 29. Overview: one trainer app at three densities

### 29.1 The shape of the workbench

| Region | `regular` (iPad) | `mac` (native macOS) | `compact` (iPhone) |
|---|---|---|---|
| **Roster** | Column 1 of `NavigationSplitView`: clients with status dots, Templates section, Add client | Same, as a Mac sidebar with source-list styling | **Clients tab**, plus a nav-bar **client chip** with a quick switcher (§32.8) |
| **Work area** | Column 2: dashboard, week board, session/per-set grid, strength profile, or review | Same | Full-screen `NavigationStack` with the same destinations |
| **Inspector** | Column 3: rationale, critique findings, exercise info, set details | Same, resizable and hideable | Bottom sheet, medium/large detents |
| **Commands** | Menu bar + toolbar + ⌘-hold HUD + full keyboard | Menu bar + toolbar + full keyboard + right-click | Toolbar + context menus + keyboard (when attached) |
| **Windows** | Multiple scenes, tiling, Stage Manager | Multiple windows, restoration | One scene |

### 29.2 Modes (work-area contexts)

1. **Dashboard** (§30) — roster-wide "what happened / what needs attention."
2. **Planner / builder** (§31 iPad, §32 iPhone) — author and edit a client's plan.
3. **Strength Profile** (§31.7) — per-client e1RM per exercise, history, update suggestions.
4. **Workout Review** (§36) — prescribed-vs-actual for a completed session.
5. **Templates** (§35) — reusable weeks and programs.
6. **Export** (§37) — the Excel export flow.

### 29.3 The performance contract

No spinners for local operations, on any idiom. Opening a client, editing a set, generating or critiquing a plan, rendering the roster, and paging the week are instant against the local SwiftData store. Sync happens in the background and never blocks the UI. A trainer with 40 clients must be able to open the app, triage, and act in under ten seconds on a phone.

## 30. Client management and the dashboard

### 30.1 The roster

Clients are rows with initials/avatar, name, a one-line status ("Lower + Cond. · due today"), a status dot (assigned / in progress / completed / paused), and an optional colour tag. Search, filter (All / Needs attention / Active / Paused / Archived), and sort (name / needs attention / last activity) are available on every idiom. On iPad the roster is the sidebar; on iPhone it is the Clients tab, and the same filters live in a segmented control under the search field.

### 30.2 The dashboard (roster-wide)

The dashboard answers **"who trained, who didn't, and who needs my attention?"** Each client card shows:

- **Status** — completed / in progress / not started / due, with a timestamp.
- **Session pulse** — a compact per-set completion strip (done/now/pending cells).
- **Prescribed-vs-actual signal** — "18/18 sets · cardio ✓ · target RPE 7–8, actual 8–9."
- **Exceptions** — "⚠ squat felt harder than prescribed," "missed the top set," a **pain flag**, "no session logged in 8 days."
- **Suggestions** — an **e1RM update suggestion**, a **deload proposal**, a **progression** for next week.
- **Quick actions** — Review, Message, New/Send plan.

Everything is derived client-side from each client's shared zone — no server, no analytics backend.

**Compact adaptation.** On iPhone the same card is used, at two heights: a **triage height** (status, pulse, one exception line, one primary action) in the list, expanding on tap. The sort defaults to "needs attention" so the phone shows the most useful three cards without scrolling. Swipe actions on a card: Review (leading), Message / Snooze (trailing).

### 30.3 Per-client Overview

Current plan (with provenance and phase), recent sessions and adherence, current per-muscle volume vs landmarks, e1RM highlights, injuries/limitations on file, and any open suggestions. It is the trainer-side analogue of the athlete's Home page.

### 30.6 External clients (non-Cladiron and non-Apple devices)

“Add client” asks **Connect through Cladiron** or **Share externally**. External
works with Android, webmail, messaging apps, paper, or any computer. It creates
no shadow account or CloudKit participant. Overview shows an `External` badge,
last reported workout, phase/week, reported/planned count, next workout, packet
version/time, and one honest state: awaiting reply, received/needs entry, or
recorded. Cladiron never reads the inbox or claims delivered/opened. Actions are
**Share next plan**, **Record result**, and **Mark report received** (Appendix Z).

### 30.4 Adding and connecting clients

- **Add client:** create a `ClientRelationship` with display name and optional notes/goal/experience/equipment/injury profile and rounding profile. This creates the client's dedicated CloudKit **custom zone**. *(Gated: §44.3.)*
- **Invite client:** generate a `CKShare` link and send it via Messages/Mail; the client accepts in their Cladiron app. No account is created for either party.
- **Pause / archive / remove:** pausing keeps history but stops active planning; archiving retains history and **stops counting toward the Pro gate**; removing ends the relationship (the client keeps their local and exportable data).

### 30.5 Client-side privacy inside trainer mode

A trainer sees only what the share carries: the client's plans, results, notes, pain flags, and e1RM. They do **not** see the client's other plans (a client may self-author alongside), their partner sessions, their Health data, or anything from a previous coach. The client's app states plainly what is shared when they accept.

## 31. The full planner / builder on iPad

The iPad planner is the reference implementation of authoring: everything else is a re-expression of it. It edits the same `Plan` object at full fidelity, keyboard-first, with a pointer and a menu bar.

### 31.1 The week board and the session list

- The planner opens on the client's **current week** (or a new draft), shown as a **seven-column board**. Each column is a day; each card is a session with its item summary and status.
- **Add** a session to a day, title it, set its **goal** (which may differ per session for DUP), and fill it with **items**.
- **Drag** sessions between days; **duplicate** a session; **repeat** a session on selected days; **drag** an item from one session to another.
- A **Day/Session view** drills into one session's items and sets; the week board stays visible as a compact strip above.
- The week header shows **planned weekly volume per muscle vs landmarks** as a small bar row, so balancing is visible while editing rather than after.

### 31.2 Adding items

`+ Strength`, `+ Cardio`, `+ Mobility`, `+ Instruction`:

- **Strength** — pick an exercise from the bundled library (searchable; filter by muscle, pattern, equipment; "recently programmed for this client" first); the item exposes the **per-set grid**.
- **Cardio** — steady / interval / open, with modality and intensity (HR zone, %HRmax, RPE, pace, power).
- **Mobility** — name, rounds × timed/reps, each-side.
- **Instruction** — a free-text coaching note as its own item.

Every add path also accepts **shorthand** (§32.5) through the quick-add field (`⌘K`), which on a hardware keyboard is by far the fastest way to build.

### 31.3 The per-set grid (the core surface)

Each strength item presents a spreadsheet-like, per-set table. Columns: **Set # / Type / Reps / Load method / Target (%1RM) / Weight / RPE / Rest**. Every set is independently editable:

- **Type** — warm-up / working / back-off / AMRAP / drop (visually distinct; warm-ups excluded from volume).
- **Reps** — exact, range (8–10), AMRAP (optionally "≥ N"), duration, or distance.
- **Load method + Target + Weight** — absolute, **%1RM**, bodyweight, bodyweight-plus, assisted, band, machine setting, or RPE-only. For %1RM, entering a percentage computes the weight from the client's **e1RM** (shown inline); the computed **Weight** stays editable — overriding it keeps the % intent and shows the effective % (§31.4).
- **RPE / RIR** — the effort target (display preference per trainer; the two interconvert).
- **Rest** — per set, defaulting from the item/goal.

**Keyboard traversal** is the point of this surface: arrow keys move cell to cell, `Tab`/`Shift-Tab` move across fields, `Return` commits and drops to the next row, `⌘D` duplicates the row, `⌥↑/↓` moves a row, `⇧`-click and `⌘`-click multi-select, and typing a bare number in a focused cell replaces it. The full table is Appendix Y.

**Pointer affordances:** hover reveals the row's inline actions; right-click opens the row context menu (Duplicate, Delete, Convert to %1RM, Convert to absolute, Apply scheme…, Make warm-up); drag the row handle to reorder; drag a row onto another item to move it.

### 31.4 %1RM workflow and equipment-aware rounding

- The client's **e1RM** for the exercise is shown at the item header. Entering a percentage resolves the weight: `weight = round(e1RM × percent, increment)`.
- **Equipment-aware rounding** is configurable per client/exercise via a `RoundingProfile`: available increment (5 lb / 2.5 kg), microplates yes/no, dumbbell increment, machine stack values, and rounding mode (nearest / down / up). A calculated 132.5 lb might resolve to 135 lb with the effective % shown.
- **Override preserves intent:** typing a specific weight over a %-derived value retains the % as the intent and displays the effective %.
- **Snapshot at send:** when the plan is sent, all %1RM loads resolve to concrete weights and are **snapshotted** so the client sees fixed numbers that don't drift.

### 31.5 Speed features

- **Apply scheme…** (`⌘⇧P`) — generate a whole set list from a `SetScheme` (§9.9): straight sets, double-progression range, top set + back-offs, ascending/descending pyramid, wave, custom. Replace or append; warm-up ramp toggle.
- **Copy/paste an exercise (with all sets) between clients**, automatically **recalculating %-based weights** from the destination client's e1RM. On iPad this is also a **drag**: pick up the exercise and drop it on a roster row.
- **Convert selected sets** absolute↔%1RM; increment/decrement selected percentages from the keyboard (`⌘]` / `⌘[`).
- **Set-all-rest**, **duplicate last set**, **duplicate exercise**, **duplicate session**, **repeat week**.
- **Undo/redo** everywhere (`⌘Z` / `⇧⌘Z`), with a visible undo affordance in the toolbar for touch users.
- **Quick add** (`⌘K`) — the shorthand field (§32.5), scoped to the focused session.

### 31.6 Multi-window and side-by-side work

On iPad and Mac, the planner supports **multiple scenes**: open two clients in two windows and tile them, or keep a template window beside a client window. Drag-and-drop works **between** windows, including exercise copy-with-recalc. Stage Manager and the iPadOS windowing controls are supported without custom handling; the app declares sensible minimum window sizes so a narrow window degrades to the `compact` arrangement rather than a broken three-column layout.

### 31.7 The Strength Profile view

Per client: exercise, **est. 1RM**, updated date, and basis ("175 × 4"). Selecting an exercise reveals current e1RM, confidence, "derived from," formula, and recent performances each with their own e1RM, plus actions: **Set manually**, **Recalculate**, **Use recent best**. When a logged session qualifies, an **e1RM update suggestion** appears here and on the dashboard (accept/ignore) — never a silent overwrite. Always labelled **estimated**.

### 31.8 Sending a plan

**Send Plan** (a) resolves and snapshots %1RM loads from the client's current e1RM, (b) writes the plan into the client's shared zone with `trainerAuthored` provenance and the trainer's display name, (c) optionally notifies the client, and (d) confirms. Before sending, the trainer can **Preview** (the client's-eye view) and run **Critique** (§34).

## 32. The iPhone trainer builder (compact-width authoring)

This section is the heart of the revision. The requirement is unambiguous: **a trainer must be able to create a complete plan, set for set, entirely on an iPhone.** The design goal is not "a viewer with a few edits" and not "a shrunken grid" — both fail. It is a different *input model* that produces identical output, and that is, for the most common work, competitive with the keyboard.

### 32.1 The expressiveness rule (normative)

> Every field of every entity that can be authored on iPad can be authored on iPhone, without exporting, without a keyboard, and without switching devices. Compact width may change **how many interactions** an edit costs; it may never change **what can be expressed**.

This is testable, and §49 criterion 12 tests it: the acceptance fixture authors a five-exercise session with warm-up ramps, a %1RM top set, two back-offs with different RPE targets, an AMRAP finisher, per-set rest that differs on three sets, a cardio interval block, a mobility item, and an instruction — using only an iPhone — and asserts the resulting `Plan` is byte-identical (modulo IDs and `authoredOnIdiom`) to the same plan authored on iPad.

### 32.2 The five layers of compact authoring

The design works because it stacks five paths from coarse to fine, so the author only descends to the expensive layer for the parts that are actually unusual:

| Layer | What it does | Typical cost | When you use it |
|---|---|---|---|
| **1. Session sources** | Start from last week, a template, another client, or Generate | 1–2 taps for a whole session | Most weeks |
| **2. Set schemes** | Fill an exercise's entire set list from a named scheme | 2–3 taps per exercise | Most exercises |
| **3. Shorthand** | Type a whole exercise line (or paste a whole session) | 1 line of text per exercise | Fast typists; unusual prescriptions |
| **4. Chip rows + prescription bar** | Edit any single field of any single set | 2 taps per field | The 2–3 outlier sets per session |
| **5. Bulk apply** | Edit one field across many sets at once | 3 taps for N sets | "make all rest 2:30" |

The failure mode of every phone spreadsheet is that it offers only layer 4. The design's claim is that layers 1–3 absorb ~90% of real programming work, and layer 5 absorbs most of the rest.

### 32.3 The set stack and chip rows

A strength item on compact width renders its sets as a **set stack** — one row per set, each row a line of tappable **chips**:

```
┌──────────────────────────────────────────────┐
│  1. Back Squat            e1RM 200 lb   ⋯    │
│  ────────────────────────────────────────    │
│  ⠿  W1   [Warm] [8]  [40% · 80]   [—]  [1:00]│
│  ⠿  W2   [Warm] [5]  [55% · 110]  [—]  [1:30]│
│  ⠿   1   [Work] [8]  [70% · 140] [RPE 7][2:00]│
│  ⠿   2   [Work] [6]  [80% · 160] [RPE 8][2:30]│
│  ⠿   3   [Top ] [3]  [90% · 180] [RPE 9][3:00]│
│  ＋ Add set     ⚡︎ Scheme     ⌨︎ Shorthand      │
└──────────────────────────────────────────────┘
```

Rules:

- **Each chip is an independently tappable target** of at least 44×44 pt, and tapping it focuses that field in the prescription bar (§32.6). There is no "open the set in a modal to change one number."
- **Chips render value-first.** `70% · 140` shows both the intent and the resolved weight; `RPE 8` and `2:30` are self-labelling. Labels compress before numbers do.
- **Warm-up rows are visually recessive** (dimmed chips, hairline rule) so the working sets read as the substance of the item.
- **Leading grab handle** (`⠿`) for drag reorder; long-press anywhere else enters **selection mode** (§32.7).
- **Swipe leading → Duplicate.** **Swipe trailing → Delete / Convert %↔lb.**
- **Dynamic Type:** at accessibility sizes the chip line wraps to two lines per set rather than truncating; at the largest sizes the row becomes a two-line stacked layout with the same chips. No number is ever truncated or ellipsized.
- **VoiceOver:** each row is a container ("Set 3, top set, 3 reps at 90 percent, 180 pounds, RPE 9, rest 3 minutes") with each chip an element carrying an "adjustable" trait so rotor up/down changes values without opening the bar.

### 32.4 Layer 2 — set schemes

Tapping **⚡︎ Scheme** opens a sheet of scheme cards ordered by the session's goal affinity, each showing a one-line preview of what it will produce:

```
┌─ Apply a scheme ───────────────── Back Squat ─┐
│  ┌───────────────┐ ┌───────────────┐          │
│  │  5 × 5        │ │  Top + backoff│          │
│  │  @80% RPE8    │ │  1@90 · 2@80  │          │
│  │  rest 3:00    │ │  rest 3:00    │          │
│  └───────────────┘ └───────────────┘          │
│  ┌───────────────┐ ┌───────────────┐          │
│  │  3 × 8–10     │ │  Ascending    │          │
│  │  RPE 8 · 2:00 │ │  60/70/80/90  │          │
│  └───────────────┘ └───────────────┘          │
│  ── parameters ──────────────────────────────  │
│  Sets  ⊖ 5 ⊕   Reps  5    Load  80% ▾          │
│  Effort RPE 8 ▾  Rest 3:00 ▾  Warm-up ramp ✓   │
│  ── preview ─────────────────────────────────  │
│  W1 8×40% 80 · W2 5×55% 110 · W3 3×70% 140     │
│  1–5: 5 × 80% · 160 lb · RPE 8 · 3:00          │
│         [ Replace sets ]   [ Append ]          │
└────────────────────────────────────────────────┘
```

- The **parameter strip** is a single row of compact controls; changing any of them updates the preview immediately.
- **Warm-up ramp** is one toggle and generates the typed `.warmup` sets per §13.14 (excluded from volume).
- **Replace** or **Append**; both are a single undoable action recording `schemeApplied`, so **Re-apply scheme…** later reopens the sheet with the previous parameters rather than making the author reconstruct intent.
- Schemes are shared with iPad (`⌘⇧P`) and are savable: any hand-built set list can be **Saved as a scheme** from the item's `⋯` menu, which is how a coach's personal patterns become one-tap on the phone.

### 32.5 Layer 3 — shorthand entry

A deterministic, offline grammar that turns one line of text into a fully-formed strength, cardio, or mobility item. It is available from **⌨︎ Shorthand** in an item, from **Quick add** in a session, and from `⌘K` with a keyboard on any device.

**Grammar (informal):**

```
line      := alias  sets 'x' reps  [load] [effort] [rest] [flags] [note]
alias     := an ExerciseDef.shorthandAlias   e.g. bench, sq, rdl, ohp, pullup, lat pd
sets      := integer
reps      := integer | integer '-' integer | 'amrap' | integer 's' (seconds) | integer 'm' (meters)
load      := '@' ( percent '%' | number | 'bw' | 'bw+' number | '-' number (assisted)
                 | 'band:' name | 'mach:' setting | 'rpe' )
effort    := 'rpe' number(.5 steps) | 'rir' integer
rest      := 'r' ( seconds | m ':' ss )
flags     := 'warm' n   (prepend an n-step warm-up ramp)
           | 'amrap'    (mark the last set AMRAP)
           | 'drop'     (mark a drop set)
note      := '"' free text '"'
```

**Examples:**

| Typed | Produces |
|---|---|
| `bench 4x8 @70% rpe8 r2:30` | Bench press, 4 working sets, 8 reps, 70% of e1RM (resolved + shown), RPE 8, 150 s rest |
| `sq 5x5 @315 r3:00 warm3` | Back squat, 3 warm-up ramp sets + 5×5 at 315 lb, 3 min rest |
| `rdl 3x10-12 rpe8 r90` | Romanian deadlift, 3 sets of 10–12, RPE 8, 90 s |
| `pullup 3xamrap @bw` | Pull-up, 3 AMRAP sets at bodyweight |
| `dip 3x8 @bw+25` | Weighted dip, +25 lb |
| `lat pd 3x12 @mach:7` | Lat pulldown, machine setting 7 |
| `plank 3x45s` | Mobility/timed item, 3 × 45 s |
| `bike 20m z2` | Cardio, steady-state bike, 20 min, HR zone 2 |
| `bike 6x(1m z4 / 2m z1)` | Cardio intervals, 6 rounds, 1 min Z4 work / 2 min Z1 recovery |

**Behaviour that makes it usable rather than clever:**

1. **Echo-as-chips.** Under the input field, the parse is rendered live as the same chips the set stack will show. You see `[Work] [8] [70% · 140] [RPE 8] [2:30]` before you commit. This teaches the grammar by demonstration and removes the "did it understand me?" anxiety.
2. **Never guess across ambiguity.** If an alias matches two exercises, the echo line becomes a chip row of candidates to tap. If a token doesn't parse, the field marks that token, keeps everything else, and the item is created with the parsed parts (nothing is lost to a typo).
3. **Multi-line paste.** Paste a whole session (one exercise per line) and get a preview list with a per-line status; commit builds the session in one undoable action. This is how a coach moves a program out of Notes or a spreadsheet in seconds.
4. **Defaults come from the engine, and say so.** Omitted rest/effort fill from the session goal via the cited rules (R-RST-1, R-INT-2) and are marked with a small dotted underline meaning "engine default — tap to confirm or change."
5. **Deterministic, offline, no model.** This is a grammar in `CadenceCore`, unit-tested with a fixture corpus, available with airplane mode on and on every device. It is explicitly **not** the LLM layer (§16.1).
6. **Units follow the client.** `@315` means 315 in that client's unit; `@142.5kg` is explicit and converts.

### 32.6 Layer 4 — the prescription bar

Tapping any chip focuses that set and raises the **prescription bar**, a persistent bottom accessory that owns the edit. It replaces the modal set editor entirely.

```
┌──────────────────────────────────────────────┐
│ [Type] [Reps] ▸Load◂ [RPE] [Rest]            │  ← field picker
│                                              │
│   %1RM  ▾     80 %        =  160 lb          │  ← contextual control
│   ⊖  ⊕        ── slider/scrub ──   [ lb ]    │
│                                              │
│   ‹  Set 2 of 5  ›      ⋯        [ Done ]    │  ← set stepper
└──────────────────────────────────────────────┘
```

- **Field picker** (row 1) switches which field the bar is editing — the touch equivalent of moving across grid columns. The currently-focused chip highlights in the set stack above, which stays visible (the bar takes the bottom third at most).
- **Contextual control** (row 2) is field-appropriate: a keypad + steppers for reps; a load control that switches method (`%1RM / lb / BW / BW+ / Assisted / Band / Machine / RPE-only`) and shows the resolved weight live as the percentage changes; an RPE control in half-steps 6.0–10.0; rest presets (0:60 / 1:30 / 2:00 / 3:00) plus custom. Horizontal drag on the value area **scrubs** it for fast coarse adjustment; the steppers give exact control.
- **Set stepper** (row 3) is the crucial one: `‹ Set 2 of 5 ›` moves to the previous/next set **without dismissing the bar or changing the focused field**. This is the compact analogue of arrow-key traversal, and it is what makes editing five sets in a row cost five taps instead of thirty. `⋯` holds Duplicate / Delete / Convert / Make warm-up / Apply to all following sets.
- **Everything is undoable** and the bar never blocks the set stack from view; the stack scrolls to keep the focused row visible above the bar.

### 32.7 Layer 5 — bulk apply

Long-pressing a set row (or tapping **Select** in the item's `⋯` menu) enters selection mode: checkboxes appear, the header shows "3 sets selected," and shortcuts offer **All**, **All working**, **All warm-up**. The prescription bar then applies its edit to the entire selection — "set rest to 2:30 on all working sets" is three taps. Selection also enables bulk **Delete**, **Duplicate**, **Convert %↔absolute**, and **Shift % by ±n**.

### 32.8 Client switching and navigation on a phone

The sidebar is the thing a phone genuinely cannot have, so it is replaced by three affordances rather than one:

1. **The Clients tab** — the full roster, searchable and filterable, sorted by "needs attention" (§30.2).
2. **The client chip** — a persistent nav-bar control inside any client context showing initials + name. Tapping it opens a **quick switcher**: a compact list of recent clients with a search field, which keeps the current destination (if you're in Week view for Maya, switching to Daniel lands in Daniel's Week view). This is a two-tap client change from anywhere.
3. **Horizontal paging** — swiping left/right on the week header moves to the previous/next client in the current roster sort, same destination. This is how a trainer does a morning triage pass without returning to a list.

**Copying between clients** on a phone is the exercise/session `⋯` → **Copy to client…**, which shows a client picker followed by a **recalculation preview** ("Bench 4×8 @70% → 70% of Daniel's e1RM 245 = 170 lb"), then applies. The preview matters more on a phone than on iPad, because there is no second window to check the result against.

### 32.9 Send safety on a compact surface

**Generate never chains straight into Send.** The Send action always opens a **preflight sheet**:

```
┌─ Send to Maya Rodriguez ─────────────────────┐
│  Week of Mar 3 · 4 sessions · 22 exercises   │
│  Critique: 1 note (chest at low end of MAV)  │
│  % loads will freeze at these weights:       │
│    Squat top set 90% → 180 lb                │
│    Bench top set 85% → 190 lb                │
│  Client sees this as "from Coach Dana"       │
│              [ Preview ]   [ Send ]          │
└──────────────────────────────────────────────┘
```

This is required on every idiom but is specified here because compact width is where an accidental send is most likely, and because §18.2 (human in the loop) must not be weakened by a small screen.

### 32.10 What is honestly slower on a phone

Stating this plainly is part of the design; the app should not pretend otherwise, and the docs/onboarding should route people to the right device for the right job:

- **Building a multi-week mesocycle from scratch.** Feasible, but the week-to-week comparison a trainer wants is a two-column job. *Mitigation:* Generate a mesocycle and edit weeks individually; the phase indicator keeps orientation.
- **Bulk surgery across many clients.** "Change the Tuesday session for all 12 clients on this template" is an iPad operation. *Mitigation:* template edit + re-apply, which works on phone but with more confirmation steps.
- **Side-by-side comparison** (last week vs this week; two clients). *Mitigation:* an inline "vs last week" ghost row in the set stack shows prior actuals under each prescribed set — most of the value of a second column, in one column.
- **Long template authoring.** *Mitigation:* shorthand multi-line paste.

The app surfaces this once, in trainer onboarding, as a matter-of-fact note — never as a nag, and never as a reason to withhold capability.

### 32.11 Review and triage on a phone

Prescribed-vs-actual review (§36) on compact width uses **diff rows** rather than a table:

```
  Back Squat
  ┌────────────────────────────────────────┐
  │ Set 3   Rx  3 × 180 · RPE 9            │
  │         Did 2 × 180 · RPE 10   ⚠ Missed│
  └────────────────────────────────────────┘
```

The prescription is the top line, the actual is the bottom line, and the outcome chip (On target / Harder / Modified / Missed) is right-aligned and colour-**and**-label coded. Sets that matched exactly collapse into a single summary row ("Sets 1–2 on target"), so the screen shows the exceptions, which is what review is for.

### 32.12 One-handed ergonomics

- Primary actions (Send, Add, Done, the prescription bar) live in the **bottom third**.
- Destructive actions (Delete session, Remove client) live top-right or behind a swipe, requiring deliberate reach.
- The nav-bar client chip is reachable via the reachability gesture; nothing critical is exclusively at the top.
- All row targets are ≥44 pt; chips have ≥8 pt separation so adjacent-chip mis-taps are rare.

## 33. The command system: menus, keyboard, and pointer

### 33.1 One definition, three presentations

Commands are declared **once**, in a `CadenceCommands` structure in the app layer, as a tree of `CommandGroup`s with titles, actions, and key equivalents. That single declaration renders as:

- an **iPadOS menu bar** (pull down from the top, hover the pointer at the top edge, or Globe-M), with key equivalents shown beside each item;
- the **⌘-hold shortcut HUD** on iPad;
- a **real Mac menu bar** in the native macOS app, rendered from the same `.commands` tree (§38.2);
- **context menus** on long-press/right-click, for the subset that is item-scoped;
- and a **command palette** (`⌘K`) that searches every command by name — the fastest path for a trainer who knows what they want but not where it lives.

Nothing may be reachable *only* by keyboard: every command also has a touch path (toolbar, context menu, or `⋯`), because iPad without a keyboard and iPhone are first-class.

### 33.2 Menu structure

- **File** — New Plan, New Template, New Window, Import Template…, Export to Excel…, Print Plan…
- **Edit** — Undo/Redo, Cut/Copy/Paste, Duplicate Set, Duplicate Exercise, Duplicate Session, Select All Working Sets, Convert to %1RM, Convert to Absolute, Shift % ±, Find…
- **Client** — Add Client…, Invite Client…, Next/Previous Client, Pause Client, Archive Client, Client Settings…
- **Plan** — Generate with Coach…, Critique Plan, Apply Scheme…, Apply Progression, Insert Deload Week, Repeat Week, Save as Template, Preview as Client, Send Plan
- **View** — Week / Day, Show Inspector, Show Rationale, Show Critique, Show Volume Bars, Compact Rows, Toggle Sidebar
- **Window** (iPad/Mac) — standard windowing commands
- **Help** — Keyboard Shortcuts, Shorthand Reference, The Science (citation registry)

### 33.3 The keyboard model

Three layers, all documented in Appendix Y:

1. **Global/navigation** — `⌘1..4` destinations, `⌥⌘→ / ←` next/previous client, `⌘F` find, `⌘K` quick add / palette, `⌘\` toggle sidebar, `⌘⌥I` inspector.
2. **Grid traversal** — arrows, `Tab`, `Return`, `⌘D`, `⌥↑/↓`, `⇧`/`⌘` multi-select, `Space` toggle warm-up, `Delete`.
3. **Prescription verbs** — `⌘⇧P` apply scheme, `⌘⇧G` generate, `⌘⇧C` critique, `⌘⇧S` send, `⌘]` / `⌘[` nudge %, `⌘R` set-all-rest.

**Discoverability** is handled by the menu bar (which shows the equivalents), the ⌘-hold HUD, and a **Keyboard Shortcuts** help screen that is also reachable on iPhone, since a phone with a keyboard uses the same set.

### 33.4 Pointer and drag-and-drop matrix

| Drag | Drop target | Result |
|---|---|---|
| Set row | Another position in the item | Reorder |
| Set row | Another exercise item | Move the set |
| Exercise item | Another session | Move the exercise (loads preserved) |
| Exercise item | A roster row | **Copy to that client with %-recalc** |
| Exercise item | Another window | Same as above, across windows |
| Session card | Another day | Reschedule |
| Session card | Templates section | Save as template |
| Template | A roster row or day | Instantiate for that client/day |
| Client row | Another client row | (no-op; reordering is by sort) |

Hover highlights the drop target and shows a badge describing the result ("Copy · recalculate to Daniel"), so a destructive-looking drag is legible before release.

### 33.5 Hardware keyboards on iPhone

If a keyboard is attached to a phone, the app enables the full command set, shows the ⌘-hold HUD, and switches the set stack to support arrow traversal between chips. This is a small amount of work (the commands already exist) with an outsized payoff for the trainer who carries a folio keyboard.

### 33.6 Accessibility parity

Every keyboard command has a VoiceOver-reachable equivalent; Full Keyboard Access is supported on all idioms; Switch Control users get the same command palette. The prescription bar's controls are all adjustable elements. No command is gesture-only.

## 34. Expert-system assistance for trainers

The engine (Part III) is available throughout the planner on every idiom as an assistant that makes the trainer faster, more consistent, and more evidence-aligned — while they remain the coach of record who signs off on everything.

### 34.1 Generate a draft

From **Plan ▸ Generate with Coach…** (`⌘⇧G`), the trainer confirms the client's goal, experience, days, session length, equipment, and constraints/injuries (prefilled from the `ClientRelationship`), plus optional periodization and horizon. The engine drafts a week or mesocycle with a full **"Why this plan"** rationale. The trainer then edits at full fidelity.

**Compact adaptation:** the prompt is a single scrolling sheet of tappable rows with sensible prefills, and the generated week lands in the week list with the rationale as a bottom sheet. Generation on a phone is one of the strongest arguments for phone authoring — the blank-page problem is exactly what a small screen makes worse, and the engine removes it.

### 34.2 Critique before sending

**Plan ▸ Critique Plan** (`⌘⇧C`) runs the audit (§14.2) and returns prioritized findings — in the inspector on iPad, as a bottom sheet on iPhone, and as a summary line in the Send preflight everywhere. Each finding has an explanation, citations, severity, and a **suggested fix** the trainer can apply or dismiss. Critique never edits the plan.

### 34.3 Progress the client

**Plan ▸ Apply Progression** proposes next week from logged results and e1RM trend in the client's chosen progression model: load/rep/volume steps, e1RM update suggestions, and **stall flags** with proposed responses.

### 34.4 Substitute exercises

Replacing an exercise offers engine-ranked **stimulus-preserving substitutes** with trade-offs noted — for equipment limits, client preferences, or working around a niggle. On the phone this is the exercise `⋯` → **Substitute…**, and it is also available to the *client* mid-session (§39.6), which is the same ranking code.

### 34.5 Autoregulation and deloads

The engine surfaces **deload proposals** and **autoregulation backoffs** on the dashboard and in the client's Overview when triggers fire. **Insert Deload Week** inserts a programmed deload into the plan.

### 34.6 Respecting the coach's methodology

The engine is an assistant, not a dogma enforcer. Where the evidence is a **judgment call**, it offers options and defers to the trainer's stated methodology; critique distinguishes "this is outside the evidence-supported range" (a real flag) from "this differs from a common default" (not a flag). The trainer always signs off.

## 35. Templates, programs, and multi-client operations

### 35.1 Templates

Save any week or mesocycle as a `PlanTemplate` (author = trainer), with a title, goal, experience level, days/week, equipment profile, and an optional evidence note. Templates store prescriptions as %1RM/RPE so they **individualize on instantiation** to whichever client they're applied to. The Templates section lists built-in and trainer-authored templates on every idiom (a sidebar section on iPad; a segmented section of the Clients tab on iPhone).

**Set schemes** (§9.9) are the small sibling of templates and are saved and browsed in the same place.

### 35.2 Programs (multi-week)

A multi-week template is a **program**: an accumulation→intensification→deload mesocycle (or custom) with per-week progression intent. Applying a program schedules its first week and lets the trainer roll forward week-to-week with the engine applying each week's progression from logged results.

### 35.3 Multi-client operations

- **Copy a prescription/exercise/session between clients** with automatic %-recalculation — by drag on iPad/Mac, by **Copy to client…** with a recalculation preview on iPhone.
- **Apply a template to several clients** at once (each individualizes). On iPhone this is a multi-select client picker with a per-client resolution summary before commit.
- **Batch review** from the dashboard: step through clients needing attention (`⌥⌘→` on a keyboard; swipe-paging on a phone).
- **Duplicate a client's plan** as a starting point for a similar client.

## 36. Workout review

After a client executes, **Workout Review** shows the session **prescribed-vs-actual** — the payoff of storing prescription and result as separate records:

- A header summary: completion ("18/18 sets · 38 min · Completed 6:14 PM"), overall prescribed-vs-actual effort, and any exception.
- A per-exercise table (iPad/Mac) or diff rows (iPhone, §32.11): for each set, **Prescription** vs **Actual** vs **Result** — a labelled outcome (On target / Harder / Modified / Missed / Completed), colour- and text-coded.
- The client's **note** and any **pain flag** (location, severity), surfaced prominently.
- Cardio and mobility results.
- Actions: **Message client**, **Apply Progression** / **Adjust next workout**, **Accept e1RM suggestion**.

Review is where the trainer closes the loop: read what happened, react, and send the next plan.

## 37. Export and backup

### 37.1 Purpose

Per Principle 9, Cladiron exports the trainer's **entire dataset** to a single Excel workbook, anytime, from any device. This is both a genuine **backup** and a deliberate trust feature: a trainer can run their business from the spreadsheet if they ever leave, which removes switching-cost anxiety up front rather than trapping them.

### 37.2 What the export contains

**Export to Excel…** produces one `.xlsx`, generated from the local store (no server round-trip):

- **Tab 1 — Summary.** Client count, active clients, workouts assigned/completed, completion rate, average sessions per client, and a per-client mini-table. **Rollups are live Excel formulas**, so the totals update if the trainer keeps working in the spreadsheet.
- **Tab 2 — Customer List.** One row per client: connected date, status, workouts assigned/completed, completion %, last active, notes.
- **Tabs 3…N — one per client.** Strength profile (estimated 1RM per exercise) plus the full **workout history as prescribed-vs-actual**, one row per set: date, workout, exercise, set, type, target reps/load/%1RM/RPE, actual reps/load/RPE, result, notes (including pain flags). Cardio and mobility items appear as rows.

### 37.3 Delivery by idiom

- **iPhone / iPad:** the file is written to a temporary location and offered through the **share sheet** and **Save to Files**, plus an optional "Save to my iCloud Drive folder" default the trainer sets once.
- **Mac:** an `NSSavePanel`-backed save dialog with a remembered directory, plus the same share options.
- **Athletes** get the same export of *their own* data (free) — the export is not a Pro feature; only the *roster* portion of the workbook requires clients to exist (§44.6).

### 37.4 Implementation notes

### 37.5 Portable plan packets

External delivery creates a client-facing `ExternalPlanPacket` from the same
immutable send snapshot, then renders responsive HTML, accessible PDF, and plain
text locally. It includes position, next one-to-three workouts, concrete
prescriptions, trainer note, version/provenance, and structured reply fields.
Readiness, injury, and other sensitive fields are excluded by default and each
requires a separate preflight toggle. Appendix Z is normative.

The export reads only the local store and writes a workbook via a Swift xlsx writer, so it does **not** depend on the sync layer and works fully offline. Historical logged data is written as **values**; summary rollups as **formulas**. A live sample of the exact format is `Cladiron-Coaching-Export-Sample.xlsx`. Large rosters export on a background task with progress, and the operation is cancellable.

## 38. The native Mac app and Universal Purchase

### 38.1 What it is

The Mac build is a **native macOS app target** — SwiftUI for macOS, with AppKit reached where the platform expects it (menus, save panels, printing, Services). It is **not** a Catalyst destination of the iPad target, and it is **not** a separate product.

- **Shared:** `CadenceCore` (all of it) and `CadenceUI` (the great majority of views and every view model). The per-set grid, set stack, week board, roster cards, review rows, rationale and citation components, and the whole engine surface are the same code the iPhone and iPad run.
- **Per-target:** the **shell** only — the scene and window model, the `.commands` tree's platform rendering, table and control metrics, file panels, printing, and a small amount of `#if os(macOS)` refinement inside shared views.
- **Everything in §29–37 applies.** This section specifies only the deltas and the commercial mechanics.

### 38.2 What the Mac app does natively

| Mac convention | How it is delivered |
|---|---|
| **Menu bar** | The `CadenceCommands` tree (§33.1) renders as a real Mac menu bar through SwiftUI `.commands`. Standard menus (App, File, Edit, View, Window, Help) are populated; unused system items are removed rather than left dead. This is a *more* direct mapping than the iPad menu bar, not a port of it. |
| **Window management** | Multiple `WindowGroup` scenes; per-window state restoration across quit and relaunch; a declared minimum width so the three-column layout is never squeezed; `⌘N` opens a new client window; the title shows *Client — Week of …*. |
| **Toolbar** | A native unified-title-bar toolbar with customizable items. |
| **Tables** | The per-set grid uses the platform's native table behaviour: column resizing, sort where meaningful, standard multi-select semantics, and desktop row density by default. |
| **Right-click** | Context menus on set rows, exercise items, session cards, roster rows, and templates. |
| **Pointer** | Hover states, precise drag targets, resize handles on the inspector column, and drag-and-drop **between windows**. |
| **Text and keyboard** | Full keyboard access, standard field editing and selection behaviour, `⌘,` for Settings, and the Services menu. |
| **File handling** | `NSSavePanel` for export with a remembered directory, `NSOpenPanel` for template import, and drag a generated `.xlsx` straight to the Finder. |
| **Printing** | `Print Plan…` renders a clean week or session sheet — genuinely useful for in-person coaching. |
| **Metrics** | Mac type scale, control sizing, and 28 pt pointer hit targets (§O.4) — the platform's metrics, not a scaled iPad's. |

### 38.3 What the Mac app deliberately does not do

These three rules are what keep a second target from becoming a second product. They are load-bearing:

1. **No Mac-only capability, ever.** If a feature is worth having on the Mac it ships to iPad and iPhone in the same change. The mechanical enforcement is `CadenceUI`: a capability implemented there reaches all three idioms by construction, and a capability implemented in the Mac shell is by definition either chrome or a bug. CI asserts that no `CadenceUI` view is compiled out under `#if os(macOS)` (§50).
2. **No separate App Store product, price, or purchase.** One record, one bundle ID, one entitlement (§38.5).
3. **No divergent behaviour.** A plan authored on the Mac is byte-identical to the same plan authored on iPad or iPhone — the parity rule of §32.1 extends to all three directions, and criterion 12 is written to be run on any pair.

### 38.4 The honest cost of a second target

v2.0 chose Catalyst partly because "a solo developer cannot maintain two professional UIs." Shared SwiftUI shrinks that cost but does not erase it, and the spec should say so plainly:

- **Platform-conditional code** accumulates. Budget for it, review it, and keep it in the shell rather than sprinkled through `CadenceUI`.
- **A second test matrix.** The Mac target needs its own build, its own UI smoke pass, and its own accessibility audit (§38.6).
- **A second place for a regression to hide.** Every command, every drag target, every keyboard path now has two homes.
- **Release coordination.** Both binaries ship together under one record; a Mac-only regression blocks the iOS release too.

The mitigation is the discipline in §38.3, not optimism. If the platform-conditional surface grows past the shell, the decision in Q.1 should be revisited rather than quietly tolerated.

### 38.5 Universal Purchase (the commercial mechanics)

This is what makes "keep the Mac app" and "one product" compatible, and it has hard requirements:

- **Same bundle identifier** across the iOS and macOS targets. This is the mechanism, not a convention.
- **One App Store Connect record** with both platforms selected, and each platform build associated to it. Universal Purchase is available to **native macOS apps**, not only Catalyst ones.
- **One download entitlement.** A user who owns the app on iPhone owns it on Mac; there is no second download to buy.
- **One in-app purchase.** Cladiron Pro's product identifiers are shared. StoreKit 2 synchronizes transactions across a user's devices on their Apple ID, so a trial started on iPhone unlocks the Mac with no further action and no restore dance. §44.4 is the tier detail; §9.12 is the resolver.
- **A one-way constraint:** records that start out separate **can never be merged**. If Cladiron ever shipped a standalone Mac record, Universal Purchase would be permanently unavailable for it. Therefore the Mac target must be configured for Universal Purchase **from its very first release** (L.6). This is the single highest-consequence build-configuration decision in the specification.
- **Pricing surface stays one line.** Free to plan your own training on any device; Pro to coach other people, on all devices at once (§44.1).

### 38.6 Testing the Mac app

- **Command coverage:** every entry in Appendix Y fires from the Mac menu bar and from its key equivalent.
- **Grid:** full keyboard traversal, multi-select, column resize, and undo/redo.
- **Context menus** present on all five row types.
- **Windows:** multiple windows, state restoration across quit/relaunch, minimum-size behaviour, and drag-and-drop **between** two client windows with correct %-recalculation.
- **Files:** export through `NSSavePanel` with a remembered directory; template import through `NSOpenPanel`; print rendering of a week and a session.
- **Parity:** the criterion-12 fixture run Mac-vs-iPad and Mac-vs-iPhone.
- **Entitlement:** purchase on iOS, verify the Mac unlocks with no additional purchase (criterion 29).
- **Accessibility:** VoiceOver, Full Keyboard Access, and Dynamic Type equivalents audited on macOS in their own pass.

### 38.7 Why native rather than Catalyst (recorded decision)

Recorded in Q.1, with the full arc in §2.3. In short: Catalyst is the right tool for **porting an existing iPad app**, and Apple's guidance for a **new multi-platform app built from scratch** is native SwiftUI per platform. Cladiron is new; its view layer is already shared; and the one advantage Catalyst had over a native target in v2.0's analysis — "one app, one purchase" — is delivered just as well by Universal Purchase (§38.5), which native macOS apps can use. What remains is Catalyst's cost: a professional tool that reads as an iPad app in a window. Q.4 records the corresponding v2.1 bet — that the shared-SwiftUI native target stays cheap enough for a solo developer to maintain.

---
---

# PART VI — THE APPLE WATCH APP

The Watch app is where training is **executed**. It is the platform's signature surface and a core moat: incumbents' cross-platform architectures make their watch apps weak (crashes mid-workout, strength that doesn't sync from the wrist, lost unsaved work), whereas a purpose-built native watchOS strength-logging experience is exactly what a focused Apple-native product does best. The Watch depends on a lightweight **execution subset** of `CadenceCore` — the plan's items and sets, logging, timers, HR, partner rotation — not the planning/engine surface.

**The Watch is never gated.** Execution is free for everyone: athletes, partners, and coached clients alike (§44.6).

## 39. Execution model

### 39.1 Entry and the session runner

The athlete starts **today's planned session** from the Watch (or hands off from the phone). The session runner presents the session's **items in order** — strength, cardio, mobility, instructions — advancing through them, and within a strength item through its **sets** in order. The flow is designed for glanceability and minimal taps, with the **Digital Crown** as the primary input.

Execution runs under the shipped **`HKWorkoutSession` + `HKLiveWorkoutBuilder`** lifecycle so it remains active with the screen down, collects heart rate, and writes the workout to HealthKit. Do not replace this with `WKExtendedRuntimeSession`; the shipped implementation deliberately removed the invalid background-mode assumptions around that design. Rich sets remain local SwiftData records. WatchConnectivity provides low-latency, durable handoff to the phone, and CloudKit remains phone-owned. See Appendix AA.

### 39.2 Strength set execution

For each set the shipped Watch keypad shows the prescription compactly: **exercise name, set X of Y, target reps, target weight**, performer when present, warm-up state, and useful history. The Crown adjusts actual reps/weight when they differ; prescribed or performer-specific defaults make compliance a one-tap **Log Set** path. Do not replace this keypad with a new planner-derived runner (§AA.5).

### 39.3 Optional post-set RPE

After completing a set, an **optional** RPE entry appears: the Crown scrolls an RPE value (half-steps 6.0–10.0), with a clear **Skip**. This writes the set's `actualRPE` and feeds autoregulation and effort insights. Never mandatory.

### 39.4 Rest, cardio, and mobility

- **Rest timer.** A rest countdown with a **next-set preview** and **Skip rest**. Haptic on completion. In a partner session, the timer knows the partner's set is your rest.
- **Cardio.** Current block/round, timer, **live heart rate**, and the target (HR zone / %HRmax / RPE / pace), with the next segment previewed. Interval structures advance round by round. On completion: duration, average HR (and range), distance where available, and an optional overall RPE.
- **Mobility.** A checklist item (rounds × timed/reps, each-side) with a timer for durations.

### 39.5 Partner rotation on the wrist

When a session has partners (§23), the runner shows the **current lifter** in the largest type with their colour, and **Complete Set** advances to the next performer in the rotation rather than the next set index. A **Whose turn?** tap cycles manually if the group goes out of order. Each lifter's target is their own when the item carries `performerOverrides`. All results carry the right `performer`.

### 39.6 Finishing a session

On the last item, the athlete **finishes**. An **optional end-of-session RPE** may be captured. The runner ends the runtime session, writes the workout to HealthKit, marks the `Session` completed locally (append-only results), and — if connected to a trainer — **queues the write-back**, flushing when the session has ended and connectivity is available. A completion summary confirms (sets, cardio, duration, "synced to coach" when applicable).

### 39.7 Live substitution

If equipment is unavailable mid-session, the athlete can request a **substitute** from the Watch (or phone), which offers the engine's stimulus-preserving alternatives for one-tap swap; the actual exercise performed is recorded (and, for a trainer-authored plan, surfaced as a modification in review).

## 40. Feedback and readiness

- **Effort feedback** (per-set and per-session RPE) is the primary athlete-supplied signal; optional, low-friction, and drives autoregulation, effort insights, and e1RM update suggestions.
- **Readiness** can be captured as an optional quick check (1–5 tap, optional soreness) and/or read from HealthKit with permission. It is a **soft modifier** surfaced as an insight or a gentle "consider a lighter session" — never a hard prescription or a medical claim.
- **Attribution.** When executing a trainer-authored plan, the Watch shows a subtle "from your coach" source.

## 41. Sync, offline, complications, and widgets

### 41.1 Offline-first and the sync-timing rule

Execution **never depends on connectivity**: the plan is available locally on the Watch, logging writes to the local store, and a logged set is never lost. The Watch does not own a CloudKit path. Stable-ID strength/cardio events are queued through WatchConnectivity and reconciled idempotently by the phone; reachable messaging is optional acceleration only. Conflict policy for results is **append-only**.

### 41.2 Watch↔iPhone↔cloud data flow

- The athlete's **plan** flows iPhone → Watch (the current session's items/sets).
- **Results** flow Watch → iPhone → cloud: the Watch records locally and sends additive, stable-ID payloads through WatchConnectivity; the phone reconciles idempotently and, for connected clients, pushes to the trainer's shared zone. `transferUserInfo`/queued context is the durable path; reachable-only `sendMessage` may accelerate UI but is never the sole delivery mechanism.
- For **self-coached** athletes, results sync across their own devices via the private database.

### 41.3 Complications and widgets

- **watchOS complications:** "today's session" / "next up," launching the runner.
- **Live Activity / Dynamic Island (iPhone):** in-progress session and rest timer.
- **Home-screen/StandBy widgets (iPhone/iPad):** today's plan and per-muscle progress; **(Pro)** a roster widget showing how many clients need attention.
- **App Intents / Shortcuts:** "start today's workout," "what's my plan today," and (Pro) "what did *Maya* do yesterday."

---
---

# PART VII — CROSS-CUTTING CONCERNS

## 42. CloudKit sharing specification

> **v2.6 status: retired from the active plan.** The active product uses only
> private iCloud synchronization for the user's own devices. CKShare zones,
> client invitations, result return, and trainer/client sharing below are
> historical v2.5 requirements and must not be expanded.

The **serverless trainer↔client connection**: plan delivery and result return with **no custom server and no custom accounts**.

### 42.1 Model

- Identity is each user's **Apple ID**. No custom accounts, no username/password, no auth server.
- The trainer owns, in **their** iCloud, **one custom `CKRecordZone` per client**, created when the trainer adds the client.
- The trainer creates a **`CKShare`** rooted at that zone with the **client as a read-write participant**.
- The trainer **invites** the client by sending the share URL via Messages/Mail. The client taps the link, accepts in their Cladiron app, and becomes a participant — no account creation.
- Both apps then read/write records in the shared zone; Apple handles identity, transport, and access control.
- **Every device the trainer owns participates equally** — iPhone, iPad, and Mac all read and write the same zones, because ownership is by Apple ID (§10.3).

### 42.2 What lives in the shared zone

- **Trainer-authored:** the `Plan` and its full hierarchy, the `ClientRelationship` metadata, e1RM reference, and trainer notes/messages.
- **Client-authored (written back):** `SetResult`, `CardioResult`, `MobilityResult`, `Session` status/timestamps, `sessionRPE`, `PainFlag`, e1RM update acknowledgements, and change requests.
- **Only `exerciseKey` is synced for exercises** — display text lives in the bundled library on each device.
- **Never in the shared zone:** the client's partner sessions, their self-authored plans, their Health data, or their other coaching relationships (§30.5).

### 42.3 Provenance, snapshot, and edit rights across the boundary

- A plan written by the trainer carries `trainerAuthored(trainer:)` and the trainer's **display name** (the only trainer PII shared).
- **%1RM loads are resolved and snapshotted at send** from the client's current e1RM, so the client sees fixed numbers.
- The prescription is **execute-only for the client** by default; the client may attach **change requests** if the trainer enables it.

### 42.4 Conflict resolution and consistency

- **Results are append-only** — never overwritten by sync.
- **Plan edits** use last-writer-wins with the trainer as the effective author. Because a trainer may now edit the same draft on two of their own devices, drafts also carry a `lastEditedBy` stamp and the UI shows a non-modal notice (§10.2).
- **e1RM** updates merge, with the trainer's acceptance authoritative for future %1RM prescriptions.
- Sync is **eventually consistent**; change tokens / `CKFetchRecordZoneChanges` drive incremental sync. **The shared-zone layer is explicit code owned by `CadenceCore`** — unlike the private database, which is automatic SwiftData↔CloudKit mirroring (§10.2). Keeping these two paths visibly distinct is a design rule, not an accident of implementation.

### 42.5 Lifecycle

- **Invite / accept:** share link → client accepts → active participant.
- **Pause:** the trainer stops active planning; zone/share persist.
- **Archive:** history retained; the relationship stops counting toward the Pro gate (§44.3).
- **Disconnect / remove:** either party can end it. The **client keeps their local data** and can export it; CloudKit share revocation removes ongoing access.
- **Entitlement lapse:** if Pro lapses, shares are **not** revoked and clients are **not** disconnected; the trainer's authoring capability degrades (§44.6). A billing event must never break a client's access to the plan they are mid-way through.

### 42.6 Why serverless is the right call here

No backend to build, secure, scale, or pay for; no custom-account system; privacy by construction. The trade-offs — eventual consistency, sharing-flow constraints, the watchOS sync-timing caveat — are handled explicitly by the sync layer and the hard rules.

### 42.7 External delivery is not CloudKit sharing

External clients have no shared zone. The trainer exports a copy through a
system composer/share sheet and manually records what is reported back. A
browser share link is a non-goal: it requires hosted plan data, access control,
expiry/revocation, and a submission service. Never encode a plan into a URL or
upload it to a third party. “Share Plan” means PDF plus text/HTML, not hosting.

## 43. Privacy and data ownership

### 43.1 No telemetry, no tracking, no ads

**No analytics, no third-party trackers, no advertising, no data harvesting.** There is no behavioural profiling and nothing is sold or shared with advertisers. This includes the paywall: Cladiron does not instrument conversion funnels, does not A/B test pricing on users, and does not use engagement notifications to drive upgrades (§44.7).

### 43.2 Data location and ownership

- The athlete's data lives in **their** local store and **their** iCloud.
- The trainer's data (roster, drafts, templates) lives in **their** local store and **their** iCloud.
- There is **no vendor-controlled central database** of user training data. There is no server at all.

### 43.3 Permissions

- **HealthKit** access is **opt-in** and explained; the app functions without it.
- **Sharing** is explicit, user-initiated, and revocable by either party.
- **Partner linking** is per-session and revocable.

### 43.4 No lock-in as a privacy/ownership stance

**Excel export** (§37) makes the entire dataset portable at any time, for free users and Pro users alike. Ending a trainer relationship leaves the client with all their data.

### 43.5 Minimal shared PII

The only trainer PII shared with a client is a **display name**; the only client PII the trainer holds is what the trainer records. Apple IDs handle identity without the platform storing credentials.

### 43.6 Proprietary application and open foundation

Cladiron application code is proprietary and closed source. Privacy claims must
be supported by concrete product behaviour—no telemetry, no developer-operated
server, explicit permissions, private iCloud storage, and complete export—not by
claiming public auditability of the application source.

The in-app About/Help surfaces, App Store metadata, website, and repository docs
must include this exact statement:

> Cladiron is a proprietary, privacy-first application built on the open free-exercise-db-plusplus project. The exercise database, annotations, and related tooling remain freely available for use by other applications.

Those surfaces must link to the open project and clearly distinguish its license
from Cladiron's all-rights-reserved application code. Third-party attribution
and share-alike obligations for bundled assets remain unaffected.

## 44. Monetization: optional development contribution

> **v2.6 status: superseded.** There is no Pro tier, entitlement gate, trial,
> paywall, or client-gated feature in the active product. Replace this section's
> policy with one optional $9.99 “Contribute to development” consumable. A
> successful purchase adds a Supporter badge to Home and unlocks nothing.

### 44.1 Active v2.6 contribution policy

All product functionality is available without purchase. There is no Pro tier,
subscription, trial, entitlement resolver, paywall, or feature downgrade.

- The only planned purchase is the optional consumable **“Contribute to
  development”** at **$9.99**.
- A successful transaction records the contribution and displays a **Supporter**
  badge on the user's Home view.
- The purchase unlocks nothing and is never required for planning, automated
  coach assistance, templates, insights, execution, history, export, partner
  sessions, readiness, or private self-device sync.
- Contribution handling is local/private, non-analytics, and idempotent for
  duplicate transaction callbacks. Failure, cancellation, or no purchase leaves
  the core product unchanged.
- Home may acknowledge Supporter status, but no view may use it to gate or
  degrade a capability.

The remainder of the old §44 text is retained below as **historical v2.5
context only**. It is not an active product requirement and must not be
implemented.

### Historical v2.5 monetization policy (non-normative)

This historical text previously described Cladiron Pro, trials, and client
gating. It is superseded by the v2.6 contribution policy above.

### 44.1 The one-sentence rule

> **Training yourself is free, forever, in full. Coaching anyone else — even one person — is Cladiron Pro.**

### 44.2 What is free (normative list)

Everything below is free, **on every device including the Mac**, with **no upsell UI anywhere in these surfaces** (Principle 10). The native Mac app is not a trainer-only tool with a locked athlete mode: someone who never coaches anyone can download Cladiron on their Mac, plan their whole training year at the per-set grid, and never encounter a purchase.

- Logging, history, PRs, Progress, the per-muscle dashboard, assessments, and JSON/Excel export of your own data.
- **The complete weekly planner** — manual building at full per-set fidelity, pre-made plans, templates you save for yourself, set schemes, shorthand entry, scheduling, and repeats.
- **The complete expert system for your own training** — Generate, Critique, Progress, Substitute, Autoregulate, deload detection, e1RM suggestions, insights, and every cited rationale. The coach does not hold back for free users.
- **Partner sessions** — training with up to three partners, per-performer prescriptions, rotation execution, and linked-partner mirroring (§23).
- **Receiving coaching** — a client of a Pro trainer pays nothing and sees nothing to buy, forever.
- **The Watch app** in full, including partner rotation.
- Cloud sync of your own data across your own devices.

### 44.3 What Pro unlocks (normative list)

**Trainer mode**, in a single tier that covers iPhone, iPad, and Mac:

External clients count exactly like connected clients. Email/PDF delivery is not
a free workaround: authoring, sharing, and recording results for another person
use `authorForClient`, `sendPlan`, and `recordClientResult` capabilities.

- Creating and holding **one or more active clients** (`ClientRelationship` with `status ∈ {invited, active, paused}`).
- Inviting clients and creating shared zones.
- **Authoring and sending** plans to a client's device.
- The **roster dashboard**, per-client Overview, triage, and exceptions.
- **Prescribed-vs-actual review** of a client's sessions and the engine's per-client suggestions.
- **Multi-client operations** — copy-with-recalc, apply-a-template-to-many, batch review.
- Trainer **templates and programs** shared across clients.
- The **roster portion** of the Excel export and the roster widget.
- **Archived clients do not count.** A trainer who winds down to zero active clients and lets Pro lapse keeps their history, their own training, and their export (§44.6).

**The gate is the *relationship*, not the count.** There is no "1 client free" tier, no per-seat pricing, and no client-count ladder: one client and forty clients cost the same. This is deliberate — it removes the incentive to under-report, keeps the pricing page one line long, and makes the product honest for Rae (§6.1) as well as Dana.

### 44.4 Products and the trial

- Products and prices (**resolved 2026-08-11**):

| Product ID | Price | Notes |
|---|---|---|
| `guru.parso.cladiron.pro.annual` | **$99 / year** | The default, pre-selected option |
| `guru.parso.cladiron.pro.monthly` | **$12 / month** | ~$144/yr, so annual saves ~31% |
| `guru.parso.cladiron.pro.lifetime` | **$249 once** | ~2.5 years of annual |
| tip-jar consumables | various | **Unlock nothing**, ever |

- **Positioning of the number.** $99/yr is a deliberate undercut of the incumbents at the *low* end of a roster: platforms that charge per-client make one or two clients uneconomic, while Cladiron charges the same for one client as for forty (§44.3). A coach with a single client pays less than a month of most competitors; a coach with forty pays less than a week.
- **A 30-day free trial** on both subscription products, using StoreKit 2 introductory offers. It starts when the user first performs a gated action (typically **Add your first client**), not at install — so the clock measures real use, not shelf time.
- **Lifetime remains available indefinitely** — not a launch promotion, not a window that closes. It is defensible here in a way it is not for server-backed products, because the marginal cost of serving a lifetime user is genuinely zero: no backend, no per-user infrastructure, no per-request LLM spend (§44.4 note below, §16.2). It also matches the project's standing preference for one-time purchases and is a concrete expression of the no-lock-in stance.
- **StoreKit 2 only.** No RevenueCat, no server, no third-party SDKs — this is a privacy requirement, not a shortcut. Entitlement resolution lives in `CadenceCore/ProEntitlement.swift` and is consumed through one capability API (§9.12).
- **Universal Purchase**: the iOS and native macOS binaries share one bundle ID and one App Store record, so one subscription covers iPhone, iPad, and Mac, tied to the Apple ID. StoreKit 2 syncs the transaction across devices — a trial started on a phone unlocks the Mac with no restore step. **Clients may therefore be added, edited, and sent to from any of the three**, with iCloud keeping the roster, drafts, and templates in step (§10.2, §42.1). Mechanics and the no-merge constraint: §38.5, L.6.
- **No server, and no route back to one.** v1.0 reserved one exception for a thin billing/licensing endpoint; with entitlement resolved entirely by StoreKit 2 and the Apple ID, **that exception is withdrawn and the platform is fully serverless.** Client↔trainer *service* payment routing via Stripe (Guideline 3.1.3(d)) was the last remaining candidate to reintroduce a server, and it is **now a permanent non-goal** (resolved 2026-08-11, §3.2): trainers already collect payment however they like, and the serverless property — no backend to secure, no user data anywhere but the users' own iCloud — is worth more than the convenience. Being able to say "there is no server" without an asterisk is a product feature.
- **What lifetime therefore costs to serve.** Nothing recurring. This is the fact that makes an indefinite lifetime tier honest rather than a liability being deferred onto a future self.

### 44.5 One gate, one place

Every surface asks `CadenceCore` for a `TrainerCapability` rather than checking a boolean inline (§9.12). This is what keeps the tiering honest and testable: a CI check asserts that no view file references entitlement state directly, and a test enumerates every gated action and asserts each resolves through the capability API. (v1.0's dead `CoachGate` type is deleted; the gate is the capability resolver.)

### 44.6 Lapse, grace, and the read-only floor

If Pro lapses or the trial ends without conversion, the app degrades **gently and predictably**:

- Trainer surfaces become **read-only**: the roster, past plans, review history, and export remain fully visible and exportable. Nothing is hidden and nothing is deleted.
- **Authoring and sending** to a client are disabled, with a plain explanation and a single restore path.
- **Clients are not disconnected and shares are not revoked.** A client mid-block keeps their plan and keeps logging; their results still arrive; the trainer can still read them.
- The user's **own** training is entirely unaffected — full planner, full expert system, full Watch app.
- Offline: entitlement is valid from its last verification for 14 days before degrading, so a gym with no signal never locks a trainer out.

This is the hard floor: **entitlement never gates reading, executing, or exporting data the user already has** (§7.2).

### 44.7 Paywall conduct

- The Pro screen appears **only** in response to a user action that involves another person's device, or from the Profile row. It never interrupts training, never appears on Home, and never appears in a client's app.
- It states plainly what is free (§44.2) alongside what Pro adds — a paywall that advertises the free tier is unusual and is exactly the trust posture this product wants.
- **No dark patterns**: no countdown timers, no fake scarcity, no pre-checked upsells, no "are you sure you want to miss out" interstitials, and no notification-driven upgrade nags. One reminder before a trial converts, as Apple requires and as good manners require.
- **No analytics on the paywall** (§43.1). Pricing decisions come from direct feedback, not instrumented funnels.

### 44.8 Migration from the previous packaging

The prior packaging gated the *coach's prescription* for single users. Under 2.0 that capability becomes free. Therefore:

- Existing Pro purchasers **keep Pro** and gain Trainer mode at no additional cost; lifetime purchasers keep lifetime.
- No user loses a capability they had. No capability that was free becomes paid.
- A one-time, dismissible note explains the change to existing subscribers, including the honest statement that the thing they paid for is now free for everyone and their subscription now covers coaching others. Subscribers who no longer want Pro are told how to cancel — burying that would be exactly the kind of behaviour §44.7 forbids.

### 44.9 No ads, ever

There is no advertising in any app, and no advertiser can pay to influence plans or placement.

## 45. Units, localization, and accessibility

### 45.1 Units

- **Weight** supports **lb and kg** per user, and a trainer's and a client's units are independent — a plan authored in lb is presented to a kg client in kg, converted and rounded to that client's equipment increments.
- **Distance/pace/speed** support imperial and metric.
- **Rounding** is equipment-aware via `RoundingProfile` (§31.4).
- Unit conversions never silently distort a prescription: the author's intent (%1RM or absolute) is preserved and the presented number is rounded to the receiving athlete's equipment.
- **Shorthand** respects the active client's unit; an explicit suffix (`142.5kg`) overrides.

### 45.2 Localization

**Launch scope: English only, architecture localization-ready** (resolved 2026-08-11). Nothing hard-codes English, no string is baked into a view, and adding a locale is a content project rather than an engineering one — but no second locale ships in this plan.

- All user-facing strings externalized; date/number/weekday formatting locale-aware; week start locale-aware in display while storage is canonical Monday-first.
- The **exercise library** uses stable `exerciseKey`s with localizable display names **and localizable `shorthandAliases`**, so shorthand works in each locale and the alias-uniqueness CI check runs per locale.
- Keyboard shortcuts avoid bindings that collide with common non-US layouts; the shortcut table is reviewed per added locale.
- **The per-locale cost, stated so it is not a surprise later:** each new locale needs translated strings, a curated `shorthandAliases` set that passes the uniqueness check (§12.3), a keyboard-shortcut collision review, and a pass over the science copy — where confidence phrasing (P.3) and safety copy (P.4) must survive translation without becoming either vaguer or more certain than the evidence supports. Alias curation is the genuinely novel cost; it cannot be machine-translated, because aliases are how *lifters in that language* actually abbreviate lifts.

### 45.3 Accessibility

- Full **VoiceOver** support across all surfaces, including the Watch runner, the per-set grid, the **set stack and its chips** (each chip an adjustable element, §32.3), and the prescription bar.
- **Dynamic Type** everywhere; the per-set grid and set stack remain usable at accessibility sizes (chips wrap; numbers never truncate).
- **Full Keyboard Access** and **Switch Control** reach every command; nothing is gesture-only (§33.6).
- **Sufficient contrast** and non-colour-dependent status (result states carry text labels).
- **Reduced-motion** support.
- **Haptics** on the Watch for rest/interval transitions aid eyes-free execution.
- The **Digital Crown** and large tap targets make Watch logging usable mid-set.
- Accessibility is checked per idiom: an audit pass exists for compact, regular, mac, and watch, because a layout that passes on iPad can fail on a phone.

## 46. Error handling, edge cases, empty states, notifications

### 46.1 Empty and first-run states

- **New self-coached user, no plan:** Home invites plan creation (assisted / pre-made / manual) — never "start live coaching," never "subscribe."
- **New trainer, no clients:** the Clients tab invites adding a client and browsing templates, and states the trial terms once, plainly.
- **New client, no plan yet from trainer:** Home shows "Your coach hasn't sent a plan yet" with the connection confirmed.
- **Sparse e1RM data:** %1RM prescriptions fall back to RPE-only with a prompt to establish e1RM; the engine flags low-confidence estimates.
- **Shorthand with an unknown alias:** the item is still created from the parsed parts, with the exercise slot marked for selection.

### 46.2 Sync and connectivity edge cases

- **Offline execution and authoring:** fully supported; results and edits queue and flush on reconnect.
- **Share not yet accepted:** the trainer can build and queue a plan; it delivers on acceptance.
- **Same draft open on two of the trainer's devices:** a non-modal "also being edited on your iPad" note; last-writer-wins with an undo path; results never affected.
- **Conflicting edits:** results are append-only; plan edits last-writer-wins with the trainer authoritative.
- **iCloud unavailable / signed out:** the app remains fully usable locally; sync/sharing indicate they need iCloud without blocking planning/execution/logging/export.
- **e1RM changed after send:** the client's live plan does not change (snapshot-at-send).
- **Entitlement unverifiable offline:** valid for 14 days from last verification, then read-only trainer surfaces (§44.6).

### 46.3 Data-integrity guardrails

- **Implausible inputs** prompt confirmation before propagating into %1RM prescriptions.
- **Append-only results** — a logged set is never overwritten by a later edit or by sync.
- **Schema changes are additive only** (optional/defaulted, no destructive migration), so an older store and an older JSON export both keep working; a failed migration fails safe with the prior store preserved.
- **Cache keys use SHA-256** (never Swift `Hasher`, which reseeds per launch).
- **Scheme application and shorthand commits are single undoable actions**, so a mis-tap on a phone never costs more than one `⌘Z`/Undo.

### 46.4 Notifications

- **Client:** optional reminders for today's session; a notification when a trainer sends a new/updated plan; sparse and opt-in.
- **Trainer:** optional notifications when a client completes a session, flags pain, or hasn't trained in a while.
- **Billing:** exactly one trial-ending reminder. No other monetization notification exists.
- All notifications are opt-in and configurable; the platform does not use notifications to drive compulsive engagement or upgrades.

### 46.5 Failure messaging

Error copy is plain and non-blaming, tells the user what happened and what they can do, and never attributes behaviour to internal mechanics. Safety-relevant refusals are handled with care and point to appropriate professional help rather than attempting diagnosis. Entitlement messages state the fact and the remedy without pressure ("Sending plans needs Cladiron Pro. Your roster and history stay available.").

---
---

# PART VIII — DELIVERY

This part sequences the build for a solo developer working plan-first and handing implementation to an agentic coding tool. It defines phases (dependency-ordered), concrete work-streams, acceptance criteria, and the testing that makes the platform's guarantees real.

## 47. Phased implementation plan

The build order is chosen so each phase produces something usable and de-risks the next. The active roadmap is single-user: manual self-planning comes first, automated coach assistance follows, and later work deepens the same individual-user experience.

### 47.0 Reconciled shipped baseline (2026-09-02)

The implementation does **not** start from an empty Phase 0. The current iPhone
and Watch app already supplies SwiftData/private-iCloud persistence, full workout
logging and history, partner rotation, HealthKit/BLE/cardio/interval execution,
export/import, StoreKit scaffolding, citations, and the DB++ integration described
above. The DB++ engine-adoption work is complete and verified by the training
engine contract tests.

Before new feature work, preserve these invariants:

- exact DB++ 1.15.4 pin and a single `TrainingEngineBridge` import boundary;
- 873 built-in catalog records and the 20-muscle ontology;
- deterministic explicit-date engine calls and persisted-plan re-evaluation;
- DB++ package evidence resolved into app citation identifiers;
- app-owned readiness, pain, recovery, and eligibility gates remain authoritative;
- no runtime network path, additive-only persistence, and Swift 6 concurrency;
- proprietary Cladiron copy and the open-project boundary in §43.6.
- the shipped 20-case `MuscleGroup` ontology and DB++ direct `1.0` / indirect
  `0.5` / stabilizer `0.0` credit policy; `BodyRegion` is grouping/search only;
- the collapsed-by-default strength cards, full-screen set editor, performer-
  specific history/default precedence, per-performer pending sets, and stable
  alternating partner order proven through gym field testing;
- `plannedExercisePrescriptions` and its legacy prescription fallback as the
  adapter from a plan into a live `WorkoutSession`; planning must not create a
  parallel runtime set-entry model;
- the Watch `HKWorkoutSession` lifecycle, local-first writes, durable/idempotent
  WatchConnectivity messages, phone reconciliation, pause/resume, finish/save,
  cancel/discard, warm-up/cool-down, audio/haptics, and unit preferences;
- the shipped Watch cardio suite and phone reconciliation, including honest
  sensor-conditional HR/distance display and exactly-once completion merge.

Phase labels below describe remaining product capability, not permission to
replace working foundations. Each work stream begins with a gap test against the
shipped code and marks already-satisfied acceptance criteria as verified.
Appendix AA is the normative preservation and integration contract. If a new
planner mockup conflicts with the shipped training loop, Appendix AA wins.

### Phase 0 — Foundations and sync proof

**Goal:** close only the remaining gaps in the already-shipped spine—especially
the future unified `Plan` model and private self-device sync proof—without
replacing working persistence, Watch execution, or the DB++ bridge.

**Build:**
- `CadenceCore` **data model** (§9) including `SetScheme` and `PerformerRef`/`PartnerRef`, with domain invariants (private-init prescription types stubbed). Do not add new Pro/entitlement types.
- **Local store**: SwiftData models with CloudKit-compatible shapes (all optional/defaulted, optional inverse relationships, no `@Attribute(.unique)`, stable UUID + updatedAt + originDevice), additive-only schema evolution, SHA-256 keys.
- **Single-user CloudKit private sync** across the user's own devices, including
  stable plan/result convergence and the shipped boundary that only the phone
  bridges Watch results into CloudKit. There is no sharing proof or client zone.
- The **Watch execution adapter**: prove that the unified plan can populate the shipped Watch strength/cardio inputs without changing its `HKWorkoutSession`, WatchConnectivity, local persistence, or completion semantics.
- Test with one iPad, one iPhone, one Watch, including a set logged in Airplane Mode arriving after reconnect.

### Phase 1 — The athlete app (free, universal)

**Goal:** ship the restructured athlete experience on iPhone **and iPad**: retire the live coach, deliver the **Plan tab** (manual + pre-made + schemes + shorthand), Home, Progress, partner sessions, execution, and migration. **No engine assistance yet.**

**Build:**
- **Four-tab IA** on compact and the **two-column** iPad arrangement (§20).
- **Plan tab**: manual builder — the **set stack + prescription bar** on compact (§32.3, §32.6) and the **per-set grid** on regular (§31.3); **set schemes** (§9.9, §32.4); **shorthand entry** (§32.5); pre-made plans; scheduling/repeats.
- **Home**: today + week + **per-muscle progress** + provenance banner.
- **Progress**: 20-muscle dashboard, e1RM trends, volume vs landmarks, adherence.
- **Partner sessions** (§23) end-to-end, including Watch rotation.
- **Execution from the plan** on Watch/iPhone with Live Activity.
- **Migration** from the live-coach version preserving history/e1RM/per-muscle progress and every existing unplanned/manual workout path.

**Outcome:** a complete, free, shippable self-planning app on two idioms. The compact authoring system ships in the individual-user context, where it gets real use and feedback before later platform polish.

### Phase 2 — The scientific coach expert system

**Goal:** extend the shipped DB++-backed deterministic automated coach into the
revised Plan-tab experience. Generation, observations, suggestions, adaptation,
progression, citation resolution, and contract tests already exist; implement
only the missing unified-plan workflows, critique/autoregulation depth, and UI.

**Build:**
- **EvidenceGate**: citation registry seeded (Appendix A), private-init prescription types enforced, **CI citation-resolution + rule-coverage + alias-uniqueness gates** (§12).
- **Knowledge base** (§13), each rule cited.
- **Generate**, **critique**, **progress**, **substitute**, and **insights** (§14), wired into the Plan tab and Home/Progress insights.
- **Explainability**: "Why this plan," per-decision rationale with confidence and tappable citations, including the compact bottom-sheet presentation (§17).

**Outcome:** the free app now offers automated coach-assisted planning and
evidence-based insights — the core value proposition, live for every athlete.

### Phase 3 — Self-planning depth and optional supporter contribution

**Goal:** make the individual user's planning loop deep, coherent, and
pleasant without introducing any feature gate.

**Build:**
- Complete cardio, mobility, instruction, periodization, mesocycle, and repeat
  planning within the same self-authored plan model.
- Add richer automated coach critique, progression, substitution,
  autoregulation, deload detection, and cited insights.
- Add optional StoreKit 2 handling for the **$9.99 “Contribute to development”**
  consumable; after successful purchase, persist/display the **Supporter** badge
  on Home. No entitlement resolver, trial, paywall, or capability gate.
- Keep exports, partner sessions, private self-device sync, and all shipped
  execution paths available regardless of supporter status.

**Outcome:** a complete self-planning product with an optional, non-functional
support contribution.

### Phase 4 — Platform polish for the individual user

**Goal:** improve self-planning and execution across the supported Apple
surfaces without adding a human-coaching or client-delivery product.

**Build:**
- iPad/larger-surface self-planning only where it shares the individual user's
  plan model and does not become a trainer workbench.
- Bounded natural-language interface over deterministic planning requests;
  the automated engine remains the only prescription authority.
- HealthKit readiness, complications, widgets, App Intents, Handoff, and
  accessibility/performance polish.
- Retire or migrate obsolete trainer/client/Pro compatibility code when safe;
  do not add new behavior to it.

**Outcome:** one coherent self-planned experience across the supported Apple
surfaces, with no human-coach delivery surface.

### Phasing principles

- Each phase ships something usable; manual self-planning lands before deeper
  automated coach assistance and platform polish.
- **The compact authoring system ships in Phase 1**, alongside the self-planned
  app, where it gets real use and feedback.
- The **shared core and engine are built once** and serve every supported surface.
- The hard rules are shipped-execution preservation, private self-device sync,
  user control over automated suggestions, cited deterministic prescriptions,
  and no purchase-gated core functionality.

## 48. Work-stream specifications

Work-streams (WS) are the units handed to the coding tool. Each has a scope, key dependencies, and its own acceptance signal.

> **Active v2.6 filter:** the trainer/client, sharing, external-delivery, Pro,
> and Universal Purchase work streams below are retained as historical v2.5
> entries only and are **retired**. Do not implement or extend them. Active
> work is limited to self-plan authoring, private self-device sync, automated
> coach assistance, optional supporter contribution, and Apple-platform polish.

### v2.6 active work-stream set

- `WS-CORE-MODEL`, `WS-STORE`, and `WS-SYNC-PRIVATE`: self-owned plan/result
  data, additive persistence, and private sync across the user's devices.
- `WS-EXECUTION-COMPAT`, `WS-WATCH-EXEC`, and `WS-PLAN-BUILDER`: preserve the
  shipped loop while completing manual, template, partner, and scheduled plans.
- `WS-SETSTACK`, `WS-SETGRID`, `WS-SCHEMES`, `WS-SHORTHAND`, and `WS-COMMANDS`:
  self-planning authoring at supported widths.
- `WS-EVIDENCE-GATE`, `WS-KNOWLEDGE-BASE`, `WS-ENGINE-*`, `WS-INSIGHTS`,
  `WS-AUTOREG`, `WS-LLM`, and `WS-READINESS`: deterministic automated-coach
  suggestions, critique, progression, rationale, and readiness assistance.
- `WS-REVIEW`, `WS-TEMPLATES`, `WS-EXPORT`, and `WS-SUPPORTER-CONTRIBUTION`:
  personal review/templates/export plus the optional $9.99 contribution that
  only adds the Home Supporter badge.

The following v2.5 work streams are explicitly retired: `WS-SHARE`,
`WS-TRAINER-SHELL`, `WS-DRAGDROP`, `WS-EXTERNAL-CLIENTS`,
`WS-PRO-ENTITLEMENT`, `WS-IPHONE-TRAINER`, `WS-MAC-NATIVE`, and
`WS-UNIVERSAL-PURCHASE`. `WS-PARTNERS` remains only for partner execution and
must not contain a promote-to-client path.

- **WS-CORE-MODEL** (Phase 0). The `CadenceCore` data model (§9) including schemes, performers, and entitlement types, plus domain-invariant scaffolding. *Done when:* the full model compiles, round-trips through Codable, and invariant types reject un-cited prescriptions in unit tests.
- **WS-STORE** (Phase 0). SwiftData models, CloudKit-compatibility conformance, additive schema evolution, append-only result enforcement, SHA-256 keys. *Done when:* all entities persist/query; a versioned migration runs; a fuzz test confirms no result overwrite.
- **WS-SYNC-PRIVATE** (Phase 0). Single-user CloudKit private-database sync, including trainer roster/draft sync across the user's own devices. *Done when:* two devices of one user converge; append-only results verified; a draft edited on two devices resolves with a visible notice and no data loss.
- **WS-SHARE** (Phase 0 proof → Phase 3 production). CloudKit sharing: per-client zone, `CKShare`, invite/accept, read-write participant, snapshot-at-send. *Done when:* a plan written by "trainer" is read by "client," results flow back, snapshot holds when e1RM changes, **and the same zone is writable from a second trainer device**.
- **WS-EXECUTION-COMPAT** (Phase 0, blocking every planning work stream). Freeze Appendix AA fixtures around the shipped iPhone strength editor, partner defaults/rotation, cardio, muscle credits, Watch lifecycle, and reconciliation. Add only the adapter from `Plan`/`PrescribedSet` into `plannedExercisePrescriptions` and existing Watch payloads. *Done when:* criteria 40–45 pass before and after every planner phase; no runtime screen or service is forked.
- **WS-WATCH-EXEC** (Phase 0 → Part VI). Preserve and extend the shipped Watch execution subset: `HKWorkoutSession`, session hub, full-screen set keypad, warm-up/cool-down, finish/save/cancel, partner rotation, rest/interval timers, live HR, cardio completion, and durable idempotent phone reconciliation. *Done when:* a full strength session (solo and partner) and cardio session execute with the phone unreachable, survive relaunch, and reconcile exactly once when connectivity returns.
- **WS-SHELL-ADAPTIVE** (Phase 1). The idiom ladder (§7.5): tab/split-view arrangements, size-class routing, Home, Progress, Profile, migration. *Done when:* the same scene renders correctly at compact, regular, and (later) mac, and no capability is conditional on idiom.
- **WS-SETSTACK** (Phase 1). The compact set stack, chip rows, swipe actions, selection mode, and the **prescription bar** (§32.3, §32.6, §32.7). *Done when:* every `PrescribedSet` field is editable from the bar; set-to-set stepping preserves the focused field; VoiceOver adjustable chips work; Dynamic Type wraps without truncating numbers.
- **WS-SETGRID** (Phase 1 → Phase 3). The regular-width per-set grid with keyboard traversal and multi-select (§31.3). *Done when:* the full traversal table (Appendix Y) works and multi-select bulk edit matches the compact bulk-apply results exactly.
- **WS-SCHEMES** (Phase 1). `SetScheme` model, built-in library, the scheme sheet, preview, replace/append, re-apply, save-as-scheme (§9.9, §32.4). *Done when:* every built-in scheme produces the documented set list, application is one undoable action, and re-apply round-trips parameters.
- **WS-SHORTHAND** (Phase 1). The deterministic shorthand grammar, echo-as-chips, ambiguity chips, multi-line paste, engine-default marking (§32.5). *Done when:* a fixture corpus of 100+ lines parses to expected items; ambiguous aliases never auto-resolve; unknown tokens degrade gracefully; the alias-uniqueness CI gate passes.
- **WS-PARTNERS** (Phase 1). Partner model, per-performer prescriptions, rotation execution, data isolation, linked mirroring, promote-to-client (§23). *Done when:* host analytics exclude partner sets; a linked partner's sets appear in their own app; promotion triggers the gate.
- **WS-PLAN-BUILDER** (Phase 1). Session/item authoring, pre-made plans, scheduling/repeats, Move-to-day. *Done when:* an athlete can hand-build and instantiate-a-template week and execute it on both idioms.
- **WS-EVIDENCE-GATE** (Phase 2). Citation registry, private-init enforcement, CI gates. *Done when:* CI fails on an un-cited or unresolved-citation rule; passes clean otherwise.
- **WS-KNOWLEDGE-BASE** (Phase 2). Encoded rules/parameters (§13) with citations. *Done when:* parameters resolve and individualize from history in tests.
- **WS-ENGINE-GENERATE / -CRITIQUE / -PROGRESS / -SUBSTITUTE** (Phase 2). The four capabilities (§14.1–14.4) + rationale. *Done when:* deterministic outputs match the Appendix H fixtures with complete cited rationale.
- **WS-INSIGHTS** (Phase 2). Insight generation + sparse surfacing, per-athlete and per-client. *Done when:* volume/balance/progress/effort/adherence insights compute and surface sparsely.
- **WS-TRAINER-SHELL** (Phase 3). Trainer mode toggle, Clients tab/sidebar, roster, dashboard, Overview, Strength Profile. *Done when:* a trainer can manage clients and triage from the dashboard on iPad.
- **WS-COMMANDS** (Phase 3). `CadenceCommands`, iPad menu bar, ⌘-hold HUD, command palette, context menus, shortcut help (§33, Appendix Y). *Done when:* every command fires from menu, keyboard, and a touch path; a test enumerates the table.
- **WS-DRAGDROP** (Phase 3). The drag matrix (§33.4) including copy-with-recalc onto a roster row and across windows. *Done when:* every row of the matrix behaves as specified with a legible drop badge.
- **WS-REVIEW** (Phase 3). Prescribed-vs-actual review + actions, table and diff-row presentations. *Done when:* a completed session renders prescription/actual/result with notes/pain flags on both idioms.
- **WS-EXTERNAL-CLIENTS** (Phase 3 → Phase 4 Mac adapter). External delivery
  mode, immutable packet snapshot, HTML/PDF/text renderers, compose/share
  adapters, packet preflight/history, and manual append-only result entry
  (Appendix Z). *Done when:* criteria 35–39 pass, golden fixtures pass, and no
  network, Contacts, or inbox API is introduced.
- **WS-TEMPLATES** (Phase 3). Templates/programs/multi-client apply. *Done when:* a template individualizes to a client on apply; a program rolls forward; multi-apply shows per-client resolution.
- **WS-EXPORT** (Phase 3). Excel export matching the sample, with share-sheet and (Phase 4) `NSSavePanel` delivery. *Done when:* the workbook matches the sample structure with live summary formulas and zero formula errors.
- **WS-PRO-ENTITLEMENT** (Phase 3). StoreKit 2 products, 30-day trial, `ProEntitlement` resolver, `TrainerCapability` API, lapse/grace, paywall screen and conduct rules (§44). *Done when:* every gated action routes through the capability API (CI-checked); trial starts on first gated action; lapse leaves trainer surfaces read-only and clients connected; a previously-Pro user retains everything (§44.8).
- **WS-IPHONE-TRAINER** (Phase 4). Roster triage on compact, client chip + quick switcher + swipe paging, compact review, Copy-to-client preview, Send preflight. *Done when:* acceptance criterion 12 passes.
- **WS-MAC-NATIVE** (Phase 4). The native macOS target: Mac shell over `CadenceUI`, `.commands` menu bar, native table metrics, scene/window model with restoration, save/open panels, printing, right-click, multi-window drag-and-drop, Services. *Depends on:* WS-SETGRID, WS-COMMANDS, WS-TRAINER-SHELL. *Done when:* the §38.6 test plan passes, the criterion-12 parity fixture passes Mac-vs-iPad and Mac-vs-iPhone, and the CI check confirms no `CadenceUI` view is compiled out under `#if os(macOS)`.
- **WS-UNIVERSAL-PURCHASE** (Phase 4, but decided in Phase 3). Shared bundle ID, one App Store Connect record covering both platforms, shared StoreKit product identifiers, cross-platform entitlement verification. *Depends on:* WS-PRO-ENTITLEMENT. *Done when:* a Pro purchase made on iOS entitles the Mac app with no additional purchase and no manual restore (criterion 29), and the record is configured for Universal Purchase before the first Mac submission.
- **WS-AUTOREG** (Phase 5). Autoregulation + deload detection. *Done when:* triggers fire correctly and proposals are non-alarmist.
- **WS-LLM** (Phase 5). NL-interface layer. *Done when:* free-text requests parse to `PlanningRequest`; the engine's output is identical to the structured-prompt and shorthand paths; the LLM never emits a prescription.
- **WS-READINESS** (Phase 5). HealthKit readiness signals as soft modifiers. *Done when:* readiness biases proposals softly and never as a medical claim.

## 49. Acceptance criteria

### v2.6 active acceptance criteria

The following are the current acceptance criteria. The v2.5 Trainer mode and
client-delivery criteria retained below are historical and non-normative; they
must not be implemented.

1. A user can build and edit a complete weekly plan manually, from a template,
   or by accepting/editing an automated coach suggestion.
2. The automated coach generates, critiques, progresses, substitutes, and
   explains proposals deterministically with cited rationale; it never silently
   changes the user's plan and never acts as a human coach.
3. Manual planning, templates, automated coach assistance, insights, execution,
   history, partner sessions, export, and readiness features work without a
   Pro entitlement, trial, paywall, or purchase.
4. There is no active Trainer mode, client relationship, roster, invite/accept
   flow, CKShare delivery, external-client packet, or human-coach result path.
5. Private iCloud sync converges the user's own plans/results across supported
   devices; it does not create cross-user sharing zones.
6. A successful optional **$9.99 “Contribute to development” consumable**
   records the contribution and displays a **Supporter** badge on Home. It
   unlocks no feature, is not required for any workflow, and cannot make core
   functionality unavailable when absent.
7. Supporter badge display and contribution handling do not introduce analytics,
   advertising, a paywall, or a direct entitlement check in planning views.

The criteria numbered 12–45 below are the retained v2.5 history. Criteria 12–39
that describe trainers, clients, Pro, external delivery, or Universal Purchase
are retired by v2.6; the execution-compatibility criteria remain useful only
where they concern the user's own plan and shipped training loop.

**Athlete app (Phases 1–2):**
1. A self-coached athlete can build a week by hand with per-set prescriptions (distinct reps/load/%1RM/RPE/rest/type per set) and execute it on the Watch — **on iPhone and on iPad**.
2. The athlete can instantiate a **pre-made plan**, whose %1RM loads resolve from their e1RM, and edit it.
3. Applying a **set scheme** produces the documented set list in one undoable action, and re-applying restores its parameters.
4. **Shorthand** `bench 4x8 @70% rpe8 r2:30` creates the exact item it echoes, offline, with no model available.
5. A **partner session** logs both lifters' sets to the correct performer, keeps the host's volume/e1RM free of partner sets, and requires no purchase.
6. **Home** shows today + the week + **per-muscle progress**, with no live coach and no upsell.
7. The engine **generates** a week with a **cited "Why this plan"** rationale and per-decision confidence; the rationale is reachable on a phone at all times.
8. The engine **critiques** a plan and flags volume-out-of-landmark, imbalance, missing pattern, effort/rest issues, and contraindications, each with a citation and a fix.
9. The engine **progresses** the athlete from logged results and raises **e1RM update suggestions** only on qualifying sets (accept/ignore; never silent).
10. Every prescription rule resolves to a **registered citation** (CI enforces citation-resolution + rule-coverage + alias-uniqueness).
11. Migration from the live-coach version preserves all history, e1RM, and progress.

**Trainer mode (Phases 3–4):**

12. **The compact-authoring parity test.** A trainer authors, **using only an iPhone**, a session containing: a warm-up ramp, a %1RM top set, two back-offs with different RPE targets, an AMRAP finisher, per-set rest differing on three sets, a cardio interval block, a mobility item, and an instruction — and the resulting `Plan` is identical (modulo IDs and `authoredOnIdiom`) to the same plan authored on iPad. **No capability may be iPad-only.**
13. A trainer can select a client and see that client's **estimated 1RM per exercise**.
14. Create an exercise with **five sets whose reps, %, calculated load, target RPE, and rest all differ** — on iPad via the grid **and** on iPhone via the prescription bar.
15. Generate a **60/70/80/90% pyramid** in one operation, on any idiom.
16. **Override one calculated load without losing the % target**.
17. Assign a workout containing **strength and cardio**; the client completes it on iPhone/Watch with optional per-set RPE.
18. **Duplicate a workout to another client and recalculate all %1RM loads** from that client's profile — by drag on iPad/Mac and by Copy-to-client with a preview on iPhone.
19. Review **prescribed-vs-actual** with deviations and problem flags clearly shown, as a table on iPad and as diff rows on iPhone.
20. **Send** resolves and **snapshots** %1RM to concrete weights behind a preflight sheet; a later e1RM change does not alter the live plan.
21. **Export** the entire dataset to one `.xlsx` (Summary + Customer List + per-client prescribed-vs-actual), good enough to operate from the spreadsheet alone, with zero formula errors — from iPhone, iPad, and Mac.
22. **Every command in Appendix Y** fires from the iPad menu bar, from the keyboard, and from a touch path; the Mac build fires all of them from its menu bar.
23. The **native Mac app** passes §38.6: menu coverage, grid keyboard traversal, right-click menus, window restoration, `NSSavePanel` export, printing, and cross-window drag — and the criterion-12 parity fixture passes Mac-vs-iPad and Mac-vs-iPhone.
24. **No Mac-only capability exists.** CI confirms no `CadenceUI` view is compiled out under `#if os(macOS)`, and every command in Appendix Y is present on all three idioms.
25. **A client can be added, edited, and sent to from iPhone, iPad, and Mac**, and the roster, drafts, and templates converge across all three via the private database (§10.2).

**Monetization (Phase 3–4):**

26. Adding a **first client** starts a **30-day trial**, not a purchase prompt; the trial clock begins at that action, not at install.
27. With **no entitlement**, every capability in §44.2 works on **every** surface including the Mac, and **no upsell appears** in Home, Plan, Progress, execution, or a coached client's app.
28. On **lapse**, trainer surfaces become read-only, **clients remain connected**, results keep arriving, export still works, and the user's own training is untouched.
29. **Universal Purchase holds:** a Pro purchase or trial started on iOS entitles the native Mac app with **no additional purchase and no manual restore**, and vice versa; both binaries resolve the same StoreKit products under one App Store record.
30. **No view references entitlement state directly**; every gated action resolves through the `TrainerCapability` API (CI-checked).
31. A user who previously purchased Pro under the old packaging **retains everything and gains Trainer mode** (§44.8).

**Cross-cutting:**

32. All planning/execution/logging/review/export work **offline**; results are **append-only**; Watch strength/cardio results survive unreachable-phone and relaunch scenarios and reconcile exactly once through stable IDs.
33. No analytics/tracking/ads anywhere, including the paywall.
34. Accessibility audits pass **per idiom** (compact, regular, mac, watch), including chip-level VoiceOver in the set stack and full keyboard access everywhere.
35. An external client can be created without an Apple device, email, Contacts permission, account, or CloudKit share; the client still counts for Pro.
36. One immutable snapshot renders HTML, PDF, and text fixtures with identical position, workouts, loads, version, and reply fields; user text is escaped and no remote resource exists.
37. iPhone/iPad **Share Plan** supplies PDF + activity-specific text, while **Compose Email** supplies editable HTML + PDF when Mail is available; cancel sends nothing and fallback Share/Copy/Files/Print remain usable.
38. A trainer can record completed-as-written, deviations, substitutions, unplanned exercise, effort, pain, duration, and notes; saving creates append-only `reportedExternal` results without mutating the packet/plan.
39. The roster never claims delivered/opened and distinguishes prepared, shared by user action, awaiting reply, received-needs-entry, and recorded; no inbox access, pixel, hosted link, or delivery server exists.
40. A planned strength session materializes through the existing `WorkoutSession` prescription adapter and opens the same collapsed exercise cards and full-screen set editor as an unplanned session; no second runtime UI or result model exists.
41. Per-exercise/per-set reps and canonical kilogram loads survive Plan → live session → Watch/phone result → history/export; legacy `plannedRepLadder`/`prescribedLoadKg` sessions remain executable.
42. With partners, pending sets alternate in stable roster order, each row opens for its named performer, and changing performer immediately applies that person's same-exercise/current-session/history defaults without borrowing the owner's history.
43. Weekly progress is calculated for the shipped 20 `MuscleGroup` cases using DB++ volume eligibility and direct/indirect/stabilizer roles; `BodyRegion` is never persisted or displayed as the analytical volume dimension.
44. The existing manual start, quick-start, exercise search, swap, add/remove set, warm-up, finish/save, cancel/discard, history-edit, cardio, and partner paths still pass their pre-planner regression fixtures with no plan present.
45. A real Watch completes strength and cardio with the phone unreachable; local data, `HKWorkoutSession`, HR, audio/haptics, units, cooldown, summary, and cancel semantics remain intact, and duplicate/out-of-order WatchConnectivity delivery produces one phone workout.

## 50. Testing and QA

> **v2.6 testing boundary:** remove Trainer mode, client-sharing, Pro,
> Universal Purchase, and external-client tests from the active matrix. Add
> automated-coach determinism, no-gating, private self-sync, and Supporter
> contribution/badge tests. The v2.5 entries below are historical unless they
> concern the user's own plan, execution, or shipped compatibility contract.

- **No-gating test:** every core planning, automated-coach, execution, history,
  export, partner, and readiness action remains available with no purchase,
  no trial, and no entitlement.
- **Supporter contribution test:** a successful $9.99 consumable transaction
  displays the Supporter badge on Home and unlocks nothing; cancellation,
  failure, duplicate callbacks, and no-purchase states leave core behavior
  unchanged.
- **Scope test:** CI fails if active product code adds Trainer mode, client
  relationship, roster, CKShare, external-client delivery, Pro entitlement,
  trial, or paywall behavior.
- **Automated-coach determinism test:** identical structured input and knowledge
  base version produce identical suggestions and cited rationale; suggestions
  remain user-accepted edits rather than silent mutations.

- **Evidence-gate CI (blocking):** citation-resolution, rule-coverage, and **shorthand alias-uniqueness per locale**.
- **Entitlement CI (blocking):** no direct entitlement reads in views; every gated action enumerated and routed through `TrainerCapability`.
- **Compact-authoring parity test:** the criterion-12 fixture, run headlessly by driving the same model-level actions the compact UI issues, plus a UI test that performs the real taps.
- **Engine determinism tests:** same `PlanningRequest` + KB version → identical plan and rationale.
- **Shorthand corpus tests:** 100+ lines including malformed input, ambiguity, unit suffixes, intervals, and multi-line paste.
- **Scheme tests:** every built-in scheme's output; undo restores prior sets exactly; re-apply round-trips parameters.
- **Knowledge-base / critique / progression / e1RM tests:** as v1.0.
- **Snapshot test:** changing e1RM after send does not alter a live plan's loads.
- **Sync/offline tests:** two-device convergence (private and shared); a set logged offline arrives after reconnect; **a trainer draft edited on iPad and iPhone converges without loss**; append-only holds under conflict.
- **Execution compatibility suite (blocking):** Appendix AA golden fixtures for planned/unplanned session materialization, collapsed/expanded strength entry, performer-specific defaults, swaps, muscle credits, Watch payloads, legacy fallback, and export/import. Run it before implementing each planning slice and after it lands.
- **Watch lifecycle/reconciliation test:** `HKWorkoutSession` start/pause/resume/end/discard, local persistence, unreachable phone, relaunch, duplicate/out-of-order strength events, and exactly-once cardio completion. CloudKit remains phone-owned.
- **Partner isolation test:** host volume/e1RM exclude partner sets; linked partner receives their own results.
- **Universal Purchase test:** purchase or start a trial on iOS, then launch the native Mac app on the same Apple ID and confirm it is entitled with no additional purchase and no manual restore — and the reverse direction (criterion 29). Run against a real sandbox account, not only StoreKit configuration files.
- **No-Mac-only-capability check (blocking):** no `CadenceUI` view is compiled out under `#if os(macOS)`; every Appendix Y command resolves on all three idioms.
- **Cross-device roster test:** add a client on the Mac, edit the draft on iPad, send from iPhone; assert convergence and a single coherent plan (criterion 25).
- **External packet golden tests:** fixed packet → canonical HTML, extracted PDF
  text, and plain text; assert identical values/order/version, HTML escaping,
  deterministic filenames, pagination, and zero remote URLs/images/scripts/forms.
- **Composer adapter tests:** Mail configured/unavailable, completion/cancel/fail,
  iPad popover anchoring, Mac service unavailable, temp-file cleanup, and only
  `.sent` automatically setting `lastSharedAt`.
- **External result tests:** completed-as-written cloning, partial actuals,
  substitution/unplanned items, duplicate-save idempotence, append-only
  provenance, and inclusion in review/engine history.
- **Entitlement lifecycle tests:** trial start/expiry, lapse → read-only, offline validity window, restore, previously-Pro migration, and the "clients stay connected on lapse" invariant.
- **Export test:** workbook structure matches the sample; recalc reports zero formula errors.
- **Unit-conversion tests:** a plan authored in lb presents correctly to a kg client without distorting the % intent; shorthand respects client units.
- **Command coverage test:** every Appendix Y entry has a menu item, a key equivalent where specified, and a touch path.
- **Native Mac test plan:** §38.6.
- **Accessibility audits:** VoiceOver/Dynamic Type/contrast/Full Keyboard Access across all four idioms.

## 51. Analytics stance, risks, and open questions

### 51.1 Analytics and telemetry stance

There is **no analytics or telemetry** in any app (Principle 8, §43.1) — including no paywall or funnel instrumentation. Product decisions come from direct user feedback and the founder's judgment. If any diagnostic capability is added, it is strictly local, opt-in, and never includes training content.

### 51.2 Risks

- **Compact authoring may not be good enough.** The whole revision rests on the claim that layers 1–3 (§32.2) absorb most programming work. *Mitigation:* the system ships to athletes in Phase 1, a year of feedback before trainers depend on it; criterion 12 keeps parity honest; §32.10 states the limits openly.
- **The second target's cost.** A native Mac app is real ongoing work: platform-conditional code, a second test matrix, and coordinated releases. *Mitigation:* the shared `CadenceUI` package, the no-Mac-only-capability rule (§38.3) with its CI check, and the honest accounting in §38.4. If the platform-conditional surface grows past the shell, revisit Q.1 rather than tolerate it.
- **Universal Purchase is a one-way door.** Separate App Store records can never be merged, so a mis-configured first Mac release permanently forfeits one-purchase-covers-everything. *Mitigation:* it is a Phase 4 work-stream done-condition and an L.6 hard constraint, not a launch-day detail.
- **Losing the "desktop-grade tool" signal.** Some trainers equate professionalism with a desktop app. *Mitigation:* the Mac build exists and is real; positioning leads with "programs anywhere," not "we dropped the Mac app."
- **Tiering leaves money on the table.** Giving the whole expert system away free removes the most obvious upsell. *Mitigation:* it is also the strongest acquisition and word-of-mouth lever, and the trainer tier is where willingness to pay actually lives; Q.3 keeps pricing level open.
- **A one-client coach may balk at $99/yr.** *Mitigation:* the 30-day trial, the $249 lifetime option, and a tier that is honest rather than metered (§44.3). If Rae-type users churn at the gate, the fix is a cheaper entry price, not a metered tier that punishes growth.
- **CloudKit sharing UX friction.** Share-link invite/accept can confuse non-technical clients. *Mitigation:* invest in the connection UX; the client app is otherwise zero-friction.
- **External reporting is manual and fallible.** Replies may be late, incomplete,
  or transcribed incorrectly. *Mitigation:* structured reply fields,
  completed-as-written, review, and explicit `reportedExternal` provenance.
- **Mail/share behavior varies.** HTML and activity handling are inconsistent.
  *Mitigation:* PDF is canonical, text is always available, HTML is progressive
  enhancement, and adapter/golden tests cover Appendix Z's matrix.
- **On-device LLM availability.** *Mitigation:* the LLM is strictly an interface, and shorthand gives a deterministic fast path that needs no model.
- **Evidence evolves.** *Mitigation:* the versioned, cited knowledge base makes updates auditable.
- **Scope discipline.** *Mitigation:* Principle 11 and the explicit non-goals (§3.2).
- **Liability.** *Mitigation:* human-in-the-loop, evidence-gating, conservative defaults, contraindication filtering, and the clear not-a-medical-device boundary.

### 51.3 Open questions

**None outstanding at the product level.** Every business and architecture decision this specification raised was resolved on 2026-08-11; the closure table is Q.3. What remains is not a question but a set of **things to learn from shipping**, each already attached to a bet in Q.4:

- Whether **compact authoring** is genuinely good enough for real programming, or whether trainers retreat to iPad to build (§32.10, Q.4).
- Whether a **native Mac target stays cheap** for a solo developer — measured by how much `#if os(macOS)` leaks out of the shell (§38.4, Q.4).
- Whether **$99/yr converts** the one-client coach, or whether that persona needs a cheaper entry point (§44.3, Q.4).
- Whether giving the **whole expert system away free** drives adoption that pays for itself through the trainer tier (§44.2, Q.4).

The only genuinely deferred *design* item is cosmetic: whether the iPad athlete experience should offer a dedicated planning window separate from the tab structure — a windowing nicety, not a capability, and safely decided during implementation.

---
---

# APPENDICES

## Appendix A — Evidence and citation registry

The human-readable form of the `Citation` registry seeded into `CadenceCore` (§12.1). Every knowledge-base rule references one or more of these IDs; the EvidenceGate CI verifies that each ID resolves and each entry carries a DOI/URL.

> **Implementation note on DOIs.** The bibliographic details below identify each source; the exact DOI/URL string **must be confirmed against the source at implementation time** and stored in the registry. This is what the citation-resolution CI gate checks.

| ID | Source | Finding used | Kind | Confidence |
|---|---|---|---|---|
| `pelland_2025` | Pelland, Robinson, Remmert, et al. "The Resistance Training Dose-Response: Meta-Regressions on Weekly Volume and Frequency for Hypertrophy and Strength." *Sports Medicine* (2025). | Robust dose-response of weekly volume with diminishing returns; frequency ~negligible for hypertrophy when volume-equated, positive with diminishing returns for strength. | metaAnalysis | strong (dose-response) |
| `schoenfeld_2017` | Schoenfeld, Ogborn, Krieger. "Dose-response relationship between weekly resistance training volume and increases in muscle mass." *J Sports Sci* 35(11):1073-1082 (2017). DOI:10.1080/02640414.2016.1210197 | Higher weekly set volume → greater hypertrophy (graded relationship). | metaAnalysis | strong |
| `iusca_2021` | Schoenfeld et al. Hypertrophy training recommendations / IUSCA position stand (2021). | Hypertrophy across a wide load/rep range when effort is matched; volume as primary driver; ≥2×/wk frequency practically useful. | positionStand | moderate-strong |
| `robinson_2024` | Robinson, Pelland, Remmert, et al. "Exploring the Dose-Response Relationship Between Proximity to Failure and Hypertrophy/Strength." *Sports Medicine* 54:2209-2231 (2024). DOI:10.1007/s40279-024-02069-2 | Hypertrophy increases closer to failure (diminishing near failure; peak ~0–3 RIR); strength negligibly affected. | metaAnalysis | strong (direction) |
| `refalo_2023` | Refalo et al. "Influence of Resistance Training Proximity-to-Failure on Muscle Hypertrophy and Strength: A Systematic Review." *Sports Medicine* 53(3):649-665 (2023). | Failure not required for hypertrophy; leaving reps in reserve can match failure with less fatigue. | positionStand | moderate-strong |
| `refalo_2024` | Refalo et al. RCT on proximity-to-failure and quadriceps hypertrophy (2024). | 1–2 RIR matched training to failure for quad hypertrophy over 8 weeks. | rct | moderate |
| `helms_2016` | Helms et al. "Application of the RIR-Based RPE Scale for Resistance Training." *Strength Cond J* 38(4):42-49 (2016). DOI:10.1519/SSC.0000000000000218 | The RPE 1–10 scale mapped to reps-in-reserve. | positionStand | strong (tool) |
| `helms_2023` | Helms et al. RPE- vs percentage-based load prescription comparison (2023). | RPE-based loading non-inferior to %-based for strength/hypertrophy in matched programs. | rct | moderate |
| `grgic_2017_periodization` | Grgic et al. "Effects of Linear and Daily Undulating Periodized Resistance Training on Hypertrophy: Meta-Analysis." *PeerJ* 5:e3695 (2017). DOI:10.7717/peerj.3695 | LP vs DUP: no meaningful difference for hypertrophy (d ≈ −0.02). | metaAnalysis | strong |
| `williams_2017` | Williams et al. "Comparison of Periodized and Non-Periodized Resistance Training on Maximal Strength: Meta-Analysis." *Sports Medicine* 47:2083-2100 (2017). DOI:10.1007/s40279-017-0734-y | Periodized > non-periodized for maximal strength. | metaAnalysis | strong |
| `moesgaard_2022` | Moesgaard et al. Periodization effects on strength/hypertrophy (volume-equated) (2022). *Sports Medicine* 52:1647-1666. | Volume-equated periodization models broadly similar. | metaAnalysis | moderate |
| `rp_landmarks` | Renaissance Periodization (Israetel et al.). Volume-landmark framework (MV/MEV/MAV/MRV), SFR and deload practitioner model. | Practitioner operationalization of weekly per-muscle set landmarks and deload/SFR heuristics. | practitionerFramework | moderate-limited |
| `acsm_guidelines` | American College of Sports Medicine. *ACSM's Guidelines for Exercise Testing and Prescription* (current ed.). | FITT prescription; intensity via HR/RPE; concurrent-training considerations. | textbook | strong |
| `nsca_essentials` | Haff & Triplett (eds.). *Essentials of Strength Training and Conditioning*, NSCA (current ed.). | Load–rep continuum; program-design acute variables; 1RM estimation; rest/warm-up standards. | textbook | strong |
| `schoenfeld_rest_2016` | Schoenfeld et al. "Longer interset rest periods enhance muscle strength and hypertrophy in resistance-trained men." *J Strength Cond Res* 30(7):1805-1812 (2016). DOI:10.1519/JSC.0000000000001272 | Longer inter-set rest (≥~2 min) supports strength/hypertrophy. | rct | moderate-strong |
| `epley_1985` | Epley, B. *Poundage Chart* (1985). | Epley 1RM estimate: 1RM = w × (1 + reps/30). | practitionerFramework | strong (low reps) |
| `brzycki_1993` | Brzycki, M. "Strength testing: predicting a one-rep max from reps-to-fatigue." *JOPERD* 64(1):88-90 (1993). DOI:10.1080/07303084.1993.10606684 | Brzycki 1RM estimate: 1RM = w × 36/(37 − reps). | practitionerFramework | strong (low reps) |

## Appendix B — Formula reference

### B.1 Estimated 1RM (e1RM)

- **Epley** (default): `e1RM = weight × (1 + reps / 30)` [epley_1985]
- **Brzycki**: `e1RM = weight × 36 / (37 − reps)` [brzycki_1993]
- **Blended**: average of Epley and Brzycki.
- **Validity window:** most accurate ~2–10 reps; above ~10 reps estimates are down-weighted / flagged low-confidence [nsca_essentials].
- **Worked example:** 175 lb × 4 → Epley 198.3; Brzycki 190.9; displayed ≈ 195 lb.

### B.2 %1RM load resolution

- `workingWeight = round(e1RM × percent, increment)`, rounding mode nearest / down / up, per the client's `RoundingProfile`.
- **Effective %** after rounding = `workingWeight / e1RM`, displayed for transparency.
- **Override:** typing an absolute weight retains the % intent and shows the effective %.
- **Snapshot at send:** the resolved weight is frozen into `calculatedWeight`; later e1RM changes do not alter it.
- **Worked example:** e1RM 200 lb, 67% with 5-lb increment → 134 → 135 lb, effective 67.5%. Override to 130 → intent stays "67%," effective shown 65%.

### B.3 RPE ↔ RIR

- `RPE = 10 − RIR` [helms_2016]. Anchors: 10 = 0 RIR; 9 = 1; 8 = 2; 7 = 3. Half-steps supported.

### B.4 Volume accounting

- A working set contributes **1.0 direct** to each primary muscle and **0.5 fractional** to each meaningful secondary muscle; warm-up sets contribute 0; **partner sets contribute 0 to the host** (§9.11).
- **Weekly per-muscle volume** = Σ(direct + fractional) over the week's owner working sets.
- Compared against individualized `VolumeLandmarks`, seeded from evidence defaults [rp_landmarks, schoenfeld_2017, pelland_2025].
- **Worked example:** bench (primary chest; secondary front delts, triceps) at 4 working sets → chest +4.0, front delts +2.0, triceps +2.0.

### B.5 e1RM update suggestion trigger

Fires when a logged set satisfies **all**: ~1–10 completed reps; actual load recorded; set completed; actual RPE ≥ 8 or marked AMRAP; estimated improvement exceeds a ~2.5–5% noise threshold. Presented for accept/ignore; never silent.

### B.6 Heart-rate zones (cardio)

Zones 1–5 as fractions of HRmax (approx.): Z1 ≤ 60%, Z2 ~60–70%, Z3 ~70–80%, Z4 ~80–90%, Z5 ≥ 90%. Moderate ≈ RPE 3–4; vigorous ≈ RPE 5–7 [acsm_guidelines]. Measured HRmax overrides the estimate.

### B.7 Shorthand token resolution (new in 2.0)

```
resolveLine(text, client) -> ParsedItem
  tokens        := lex(text)                     // whitespace-delimited, quotes preserved
  alias         := longest-prefix match against ExerciseDef.shorthandAliases (locale-scoped)
  if matches > 1 -> return .ambiguous(candidates) // never auto-resolve
  sets × reps   := required; reps may be range | amrap | Ns | Nm
  load          := optional; '%' → percent1RM resolved via B.2 with client's RoundingProfile
  effort        := optional; rpe|rir → interconverted via B.3
  rest          := optional; 'r' + seconds | m:ss
  unfilled fields ← engine defaults by session goal (R-RST-1, R-INT-2), marked as defaults
  return .parsed(item, warnings)
```

Deterministic and total: any input yields either a parsed item (possibly with warnings) or a structured ambiguity/parse error; the parser never throws away the tokens it understood.

## Appendix C — Exercise library schema and seed list

### C.1 Schema

The authoritative catalog is the pinned DB++ package exposed only through `TrainingEngineBridge`, not a second app-owned seed decoder. An app-facing `ExerciseDef` carries stable key, display/search aliases, kind, DB++ direct/indirect/stabilizer muscle roles, volume eligibility, movement classification, equipment, defaults, laterality, load modes, and stimulus/fatigue metadata. Only stable identity and user-authored overrides travel with a workout. Catalog refreshes follow the bridge contract and stable-ID migration tests in Appendix AA.

### C.2 Historical examples (non-normative)

The table below survives only as shorthand/parser examples from the pre-DB++
draft. It is not a seed list and must not be copied into code. Names such as
`frontDelts`, `rearDelts`, `back`, `abs`, and `obliques` are legacy display/search
terms that DB++ maps into canonical `shoulders`, `middle_back`, `abdominals`,
and related roles. Runtime catalog values and roles always win.

Load modes: A=absolute, %=percent1RM, BW=bodyweight, BW+=bodyweight-plus, As=assisted, Bd=band, M=machine setting.

| Key | Display | Aliases | Pattern | Primary | Secondary | Equip | Load modes | SFR |
|---|---|---|---|---|---|---|---|---|
| `barbell_back_squat` | Back Squat | squat, sq, bs | squat | quads, glutes | hamstrings, lowerBack | barbell | A, % | moderate |
| `barbell_front_squat` | Front Squat | front squat, fsq | squat | quads | glutes, abs | barbell | A, % | moderate |
| `goblet_squat` | Goblet Squat | goblet | squat | quads, glutes | abs | dumbbell/kettlebell | A | high |
| `leg_press` | Leg Press | lp, legpress | squat | quads, glutes | hamstrings | machine | A, M | high |
| `barbell_deadlift` | Conventional Deadlift | deadlift, dl | hinge | glutes, hamstrings | back, lowerBack, traps | barbell | A, % | low |
| `romanian_deadlift` | Romanian Deadlift | rdl | hinge | hamstrings, glutes | lowerBack, back | barbell/dumbbell | A, % | moderate |
| `hip_thrust` | Barbell Hip Thrust | hip thrust, ht | hinge | glutes | hamstrings | barbell | A | high |
| `back_extension` | Back Extension | back ext | hinge | glutes, hamstrings | lowerBack | bodyweight | BW, BW+ | high |
| `walking_lunge` | Walking Lunge | lunge | lunge | quads, glutes | hamstrings | dumbbell/barbell/bodyweight | A, BW, BW+ | moderate |
| `bulgarian_split_squat` | Bulgarian Split Squat | bss, split squat | lunge | quads, glutes | hamstrings | dumbbell/barbell | A, BW+ | moderate |
| `barbell_bench_press` | Barbell Bench Press | bench, bp | horizontalPush | chest | frontDelts, triceps | barbell | A, % | moderate |
| `dumbbell_bench_press` | Dumbbell Bench Press | db bench, dbbp | horizontalPush | chest | frontDelts, triceps | dumbbell | A | high |
| `incline_db_press` | Incline DB Press | incline db | horizontalPush | chest, frontDelts | triceps | dumbbell | A | high |
| `pushup` | Push-up | pushup | horizontalPush | chest | frontDelts, triceps | bodyweight | BW, BW+ | high |
| `machine_chest_press` | Machine Chest Press | mach press | horizontalPush | chest | frontDelts, triceps | machine | A, M | high |
| `overhead_press` | Overhead Press | ohp, press | verticalPush | frontDelts | sideDelts, triceps | barbell | A, % | moderate |
| `db_shoulder_press` | DB Shoulder Press | db press | verticalPush | frontDelts | sideDelts, triceps | dumbbell | A | high |
| `barbell_row` | Barbell Row | row, bb row | horizontalPull | back, lats | rearDelts, biceps | barbell | A, % | moderate |
| `db_row` | One-Arm DB Row | db row | horizontalPull | back, lats | rearDelts, biceps | dumbbell | A | high |
| `seated_cable_row` | Seated Cable Row | cable row | horizontalPull | back, lats | rearDelts, biceps | cable | A, M | high |
| `pullup` | Pull-up | pullup, pu | verticalPull | lats, back | biceps | bodyweight | BW, BW+, As | moderate |
| `lat_pulldown` | Lat Pulldown | lat pd, pulldown | verticalPull | lats | back, biceps | cable/machine | A, M | high |
| `assisted_pullup` | Assisted Pull-up | asst pullup | verticalPull | lats, back | biceps | machine | As, M | high |
| `farmer_carry` | Farmer's Carry | farmers | carry | traps, forearms | abs, glutes | dumbbell/kettlebell | A | moderate |
| `plank` | Plank | plank | isolation | abs | obliques | bodyweight | BW (duration) | high |
| `hanging_leg_raise` | Hanging Leg Raise | hlr | isolation | abs | obliques | bodyweight | BW | high |
| `barbell_curl` | Barbell Curl | bb curl | isolation | biceps | forearms | barbell/ez | A | high |
| `db_curl` | Dumbbell Curl | curl, db curl | isolation | biceps | forearms | dumbbell | A | high |
| `triceps_pushdown` | Triceps Pushdown | pushdown | isolation | triceps | — | cable | A, M | high |
| `overhead_triceps_ext` | Overhead Triceps Extension | oh tri | isolation | triceps | — | dumbbell/cable | A | high |
| `lateral_raise` | Lateral Raise | lat raise, side raise | isolation | sideDelts | frontDelts | dumbbell/cable | A | high |
| `rear_delt_fly` | Rear Delt Fly | rear delt | isolation | rearDelts | back | dumbbell/cable | A | high |
| `leg_curl` | Leg Curl | leg curl | isolation | hamstrings | calves | machine | A, M | high |
| `leg_extension` | Leg Extension | leg ext | isolation | quads | — | machine | A, M | high |
| `calf_raise` | Standing Calf Raise | calf | isolation | calves | — | machine/dumbbell | A, M | high |
| `cable_fly` | Cable Fly | fly | isolation | chest | frontDelts | cable | A, M | high |
| `face_pull` | Face Pull | face pull | isolation | rearDelts | traps | cable/band | A, Bd, M | high |
| `run` | Run | run | cardioCyclic | (cardio) | — | — | — | — |
| `bike` | Bike | bike | cardioCyclic | (cardio) | — | cardioMachine | — | — |
| `row_erg` | Rowing Erg | erg | cardioCyclic | (cardio) | — | cardioMachine | — | — |

Aliases must be unique per locale (CI gate, §12.3). Mobility items are freeform `MobilityItem`s, not library entries.

## Appendix D — Muscle-group and movement-pattern taxonomy

### D.1 Movement patterns

`squat`, `hinge`, `lunge`, `horizontalPush`, `verticalPush`, `horizontalPull`, `verticalPull`, `carry`, `rotation`, `isolation`, `cardioCyclic`. A well-formed general strength/hypertrophy week covers squat, hinge, a horizontal push and pull, a vertical push and pull, and targeted isolation, with pressing and pulling volumes roughly balanced.

### D.2 Muscle groups

The exact `MuscleGroup` raw values are: `abdominals`, `abductors`, `adductors`,
`biceps`, `calves`, `chest`, `forearms`, `glutes`, `hamstrings`, `lats`,
`lower_back`, `middle_back`, `neck`, `quadriceps`, `shoulders`, `traps`,
`triceps`, `tibialis`, `rotator_cuff`, and `hip_flexors`. Volume, targets,
insights, and progress are tracked at this granularity. Broad `BodyRegion` values
are picker/search grouping only.

### D.3 Equipment

`barbell`, `dumbbell`, `kettlebell`, `machine`, `cable`, `bodyweight`, `band`, `ez`, `trapBar`, `cardioMachine(activity)`. The equipment profile filters exercise selection and substitution; `loadModes` per `ExerciseDef` constrain the UI (a pull-up never offers %1RM).

## Appendix E — Consolidated data-type catalog

**Identity & provenance:** `PlanID`, `TemplateID`, `PlanProvenance`, `TrainerRef`, `AuthorRef`, `AuthoringIdiom`.

**Plan structure:** `Plan`, `PlanWeek`, `PlanDay`, `Session`, `WorkoutItem`. Enums: `TrainingGoal`, `PlanHorizon`, `PlanStatus`, `SessionStatus`, `Weekday`, `ProgressionIntent`.

**Strength prescription:** `StrengthItem`, `PrescribedSet`, `SetKind`, `RepTarget`, `LoadPrescription`, `WeightUnit`, `SupersetGroupID` (reserved).

**Schemes (2.0):** `SetScheme`, `SetSchemeID`, `SchemeKind`, `SchemeParams`, `EffortSpec`, `LoadSpec`.

**Results:** `SetResult`, `CardioResult`, `MobilityResult` (all append-only, all carrying `PerformerRef`).

**Partners (2.0):** `PerformerRef`, `PartnerRef`.

**Cardio:** `CardioItem`, `CardioPrescription`, `SteadyState`, `Intervals`, `IntervalSegment`, `OpenActivity`, `CardioActivity`, `CardioIntensity`, `PaceUnit`, `SpeedUnit`, `TalkTestLevel`.

**Mobility & instruction:** `MobilityItem`, `InstructionItem`.

**Exercise library & taxonomy:** `ExerciseKey`, `ExerciseDef` (with `shorthandAliases`), `MuscleGroup`, `MovementPattern`, `Equipment`, `ItemKind`, `LoadMode`, `SFRTier`.

**Performance & progress:** `ExercisePerformanceProfile`, `OneRMEstimatePoint`, `EstimateConfidence`, `EstimateSource`, `OneRMFormula`, `MuscleVolumeWeek`, `VolumeLandmarks`, `LandmarkBasis`.

**Readiness & feedback:** `ReadinessSignal`, `PainFlag`.

**Templates & relationships:** `PlanTemplate`, `TemplateAuthor`, `ExperienceLevel`, `ClientRelationship`, `ClientStatus`, `InjuryNote`, `RoundingProfile`, `RosterTag`.

**Entitlement (2.0):** `ProEntitlement`, `EntitlementState`, `TrainerCapability`.

**Engine & evidence:** `EngineRationale`, `RationaleDecision`, `EvidenceConfidence`, `CitationID`, `Citation`, `CitationKind`, `PlanningRequest`, `CritiqueFinding`, `KnowledgeBaseVersion`.

**Parsing (2.0):** `ParsedItem`, `ShorthandWarning`, `AliasCandidate`.

## Appendix F — Glossary

- **1RM** — one-repetition maximum.
- **Accumulation / intensification** — mesocycle phases.
- **AMRAP** — as many reps as possible.
- **Autoregulation** — adjusting load/volume to daily readiness, typically via an RPE target.
- **Block periodization** — sequencing focused blocks.
- **Chip row** — the compact-width representation of one set as tappable value chips (§32.3).
- **CadenceCore** — the shared Swift package.
- **CKShare / custom zone** — CloudKit constructs used to share a per-client record zone without a server.
- **Compact / regular / mac** — the three UI idioms (§7.5).
- **Concurrent training** — training strength and endurance in the same period.
- **Deload** — a planned reduction in volume/intensity.
- **Double progression** — progress reps within a range, then add load.
- **DUP / WUP** — daily / weekly undulating periodization.
- **e1RM** — estimated 1RM; always labelled *estimated*.
- **EvidenceConfidence** — strong / moderate / limited / judgmentCall.
- **EvidenceGate** — the mechanism ensuring every prescription rule carries a registered citation.
- **FITT** — Frequency, Intensity, Time, Type.
- **Fractional set** — a working set's 0.5 contribution to a secondary muscle.
- **Idiom** — which shape the app is in; drives layout, never capability.
- **Insight** — an evidence-anchored, read-only observation about training.
- **Item** — a component of a session.
- **Mac Catalyst** — Apple's technology for shipping an iPad app as a Mac app. Cladiron **does not use it**: v2.0 planned to, v2.1 ships a native macOS target instead (§2.3, §38.7). The term appears here only because the decision history refers to it.
- **Universal Purchase** — one App Store record and one bundle ID spanning the iOS and macOS binaries, so a single download entitlement and a single in-app purchase cover every platform (§38.5).
- **`CadenceUI`** — the shared SwiftUI view-layer package; what makes a second app target affordable and what mechanically enforces "no Mac-only capability" (§7.1, §38.3).
- **MV / MEV / MAV / MRV** — maintenance / minimum-effective / maximum-adaptive / maximum-recoverable weekly per-muscle set volumes.
- **Mesocycle** — a multi-week training block.
- **Partner** — someone training beside you in the same session; free (§23).
- **Client** — someone you author and deliver plans for; requires Pro (§44).
- **Prescription bar** — the persistent compact-width editor for the focused set (§32.6).
- **Provenance** — who authored a plan.
- **RIR / RPE** — reps in reserve / rating of perceived exertion.
- **Set scheme** — a named, parameterized generator for a whole set list (§9.9).
- **Shorthand** — the deterministic text grammar for authoring items (§32.5).
- **Snapshot at send** — freezing %1RM to concrete weights when a plan is sent/started.
- **Trainer mode** — the Pro configuration of the app.
- **`HKWorkoutSession`** — the shipped watchOS workout lifecycle for background execution, live metrics, and HealthKit save; rich strength data remains in Cladiron's local model.

## Appendix G — Changelog

- **v2.5 (this document) — plan onto the proven training loop.** Makes shipped
  DB++ muscle accounting and field-tested iPhone/Watch strength/cardio behavior
  normative compatibility constraints. Adds `WS-EXECUTION-COMPAT`, criteria
  40–45, Appendix AA's source seams/adapter/migration/device gates, and two
  continuity mockups. Corrects obsolete body-part and `WKExtendedRuntimeSession`
  assumptions: the Watch uses `HKWorkoutSession`, durable WatchConnectivity, and
  phone-owned CloudKit. Planning authors prescriptions; existing execution owns
  results.
- **v2.4 (this document) — universal client delivery.** Adds external clients
  who need no Apple device, account, or Cladiron install. Defines one immutable
  plan packet rendered as HTML/PDF/text, deliberate Mail/share handoff on all
  trainer idioms, privacy preflight, honest status semantics, structured replies,
  manual append-only result entry, six mockups, criteria 35–39, the
  `WS-EXTERNAL-CLIENTS` work stream, and implementable Appendix Z. Hosted links,
  inbox access, tracking, and a delivery server remain non-goals.
- **v2.3 (this document) — DB++ baseline and proprietary boundary.** Reconciles
  the roadmap with the shipped `free-exercise-db-plusplus` 1.15.4 integration:
  one bridge import, 873 exercises, 20 muscles, deterministic planning/history/
  adaptation primitives, evidence resolution, and app-owned readiness and
  eligibility composition. Makes Cladiron proprietary and closed source,
  removes GPL/App Store-exception assumptions, requires consistent About/Help
  and metadata language, and keeps the exercise database, annotations, and
  related tooling openly reusable. Recasts Phases 0 and 2 as gap-closing work
  over the shipped baseline rather than greenfield engine/database builds.
- **v2.2 (this document) — decisions resolved.** No new design; closes every open question the spec carried. **Persistence follows the shipped app**: SwiftData mirrored to CloudKit via `NSPersistentCloudKitContainer`, replacing v1.0's GRDB-plus-hand-written-sync (§10.1–10.2, Q.1, W.2/W.3) — a decision that removed the single most expensive line in the document. **Packages renamed** to `CadenceCore` / `CadenceUI` / `CadenceCommands` per the repo's naming rule, with *Cladiron* reserved for user-facing copy. **Adopted as the product roadmap**, with `CLAUDE.md` gaining a roadmap pointer while continuing to describe shipped behaviour. **Prices set** at $99/yr, $12/mo, $249 lifetime, with lifetime available indefinitely (§44.4). **Stripe service-payment routing and group/cohort programming are now permanent non-goals** (§3.2) — the platform is unconditionally serverless. **iPadOS 26 stays a presentation difference**, not a floor (L.1). **English at launch**, architecture localization-ready, with the per-locale cost stated (§45.2). All policy defaults ratified. Q.3 is now a closure table rather than an open list, and §51.3 carries bets to check rather than questions to answer.
- **v2.1 — "one product, four native surfaces."** Reverses exactly one v2.0 decision: the **Mac app returns, and returns native**. Rather than reaching the desktop through Mac Catalyst, Cladiron ships a **native macOS target** that shares `CadenceCore` and a new **`CadenceUI`** view-layer package with the iOS target, and that is distributed in the **same App Store record under the same bundle ID via Universal Purchase** (§38.5) — so the Mac is not a second product, a second price, or a second purchase. The Mac app is **fully functional and free for planning your own training**; the only in-app purchase remains **Cladiron Pro**, which unlocks **clients**, addable from iPhone, iPad, or Mac with iCloud keeping the roster and drafts in sync (§44.4). Adds the no-Mac-only-capability rule with a CI check (§38.3), the honest second-target cost accounting (§38.4), the Universal Purchase mechanics and the **records-can-never-be-merged** constraint (§38.5, L.6), a native Mac test plan (§38.6), `WS-MAC-NATIVE` and `WS-UNIVERSAL-PURCHASE` (§48), and acceptance criteria 24, 25, and 29. Everything else v2.0 established is unchanged: mobile-first trainer capability, the compact authoring model, partner sessions, and the free/Pro line. The full decision arc (v1.0 native → v2.0 Catalyst → v2.1 native under Universal Purchase) is recorded in §2.3 and Q.1 rather than overwritten.
- **v2.0 — "one app, every screen."** Eliminates the separate native macOS trainer app; moves the full trainer surface into the **iPad** app (three-column, keyboard-first, menu bar, pointer, multi-window) and ships it to the desktop via **Mac Catalyst** (§2.3, Part V, §38). Adds **complete trainer functionality on iPhone** through a new compact-width authoring system — set stack + chip rows, the prescription bar, set schemes, deterministic shorthand entry, bulk apply, client chip + quick switcher, Send preflight (§32) — governed by a normative **expressiveness rule** (§32.1) and an acceptance test for parity (§49 criterion 12). Adds **set schemes** (§9.9) and **shorthand** (§32.5, B.7) as first-class model + interaction concepts available to athletes and trainers alike. Adds **partner sessions** as a modelled, free capability (§23, §9.11) and defines the **partner ≠ client** boundary (§8.5). Rewrites monetization (§44): **Cladiron Pro now gates coaching other people only** — any client requires Pro, with a **30-day trial**, one purchase covering iPhone/iPad/Mac — while **all self-coached use, including the entire expert system, becomes free forever**; adds lapse/grace rules, paywall conduct rules, and a migration guarantee (§44.8). **Withdraws the thin billing endpoint**, making the platform fully serverless. Re-sequences delivery so the compact authoring system ships in Phase 1 with the free app (Part VIII). Rewrites Appendix K (iPad/iPhone/Catalyst screens and a new mockup catalog), Appendix L (targets), Appendix O (adaptive layout), and adds **Appendix Y** (keyboard and menu command reference). Carries forward unchanged: the expert system and its evidence base (Part III, Appendices A/H/I/U/V), the data model spine, CloudKit sharing, the Watch app, export, and the privacy stance.
- **v1.0 (`cladiron-mvp/CLADIRON_PLATFORM_SPEC.md`).** First complete platform specification: the expert system in depth, the single-user iPhone restructure from live coach to weekly planner, a separate Mac trainer app, the Watch execution model, CloudKit sharing, and a phased delivery plan.
- **v0.2 (`MVP_DESIGN.md`).** Per-set coaching-tool revision: set as the atomic prescription unit; %1RM/e1RM; cardio; mobility; pain flags; substitution; templates; Excel export.
- **v0.1.** Initial trainer-platform MVP sketch.

## Appendix H — Worked examples: the expert system in action

Illustrative of expected behaviour; they double as acceptance fixtures. Numbers are examples; the engine individualizes.

### H.1 Generate a hypertrophy week (full walkthrough)

**Request.** Sam (intermediate), hypertrophy, 4 days/week, ~60-min sessions, full gym, no contraindications, upper/lower split, RPE-based effort. e1RM known (squat 300, bench 225, deadlift 365, OHP 145 lb).

**Step 1 — Weekly volume targets.** MAV band: chest 12, back/lats 14, quads 12, hamstrings 10, glutes 10, shoulders 12, biceps 10, triceps 10, calves 8, abs 8. *[pelland_2025, schoenfeld_2017, iusca_2021, rp_landmarks]* Confidence: dose-response strong; numbers moderate.

**Step 2 — Frequency.** Split each muscle across **2 sessions/week**. *[pelland_2025]* Strong.

**Step 3 — Exercise selection.** Cover horizontal + vertical push and pull, squat, hinge, plus isolation; balance pressing and pulling; prefer good SFR for accessories:
- **Upper A:** barbell bench, one-arm DB row, incline DB press, lat pulldown, lateral raise, triceps pushdown, DB curl.
- **Lower A:** back squat, Romanian deadlift, leg press, leg curl, standing calf raise, hanging leg raise.
- **Upper B:** overhead press, barbell row, DB bench, pull-up, rear-delt fly, overhead triceps extension, barbell curl.
- **Lower B:** deadlift, front squat, Bulgarian split squat, leg extension, seated calf raise, plank.
*[nsca_essentials, iusca_2021, rp_landmarks]*

**Step 4 — Sets/effort/rest.** Compounds 3–4 × 5–8; accessories 3 × 8–12; effort ~1–3 RIR (top sets RPE 8); rest 2–3 min compounds, 1.5–2 min accessories; **warm-up ramps** on main compounds. *[robinson_2024, refalo_2024, helms_2016, schoenfeld_rest_2016, nsca_essentials]*

**Step 5 — Cardio/mobility.** None required; optional Zone-2 1–2×/week away from lower-body days. *[acsm_guidelines]*

**Step 6 — Periodization.** Week 1 of a 5-week mesocycle (4 accumulation + 1 deload); add ~1 set to lagging muscles and/or small load increases weekly. *[williams_2017, grgic_2017_periodization, rp_landmarks]* Model = judgmentCall.

**Output — narrated summary:** "A 4-day upper/lower hypertrophy week. Each muscle is trained twice at 10–14 weekly working sets — inside the productive volume range for an intermediate lifter — with compounds at 5–8 reps and accessories at 8–12, all at about 1–3 reps in reserve. Rest is 2–3 minutes on the big lifts to protect your working volume. It's week 1 of a 5-week block that adds a little volume each week before a deload."

**2.0 note — how this looks on a phone.** The generated week lands in the week list; the rationale is a bottom sheet reachable from "Why this plan"; each session opens to a set stack already fully populated. The athlete's most common next action — nudging two loads and one rest — costs six taps via the prescription bar.

### H.2 Generate a strength mesocycle

**Request.** Strength focus, 4 weeks, 3 days/week, squat/bench/deadlift emphasis, %1RM prescription.

- **Week 1 (accumulation):** main lifts 4×5 @ ~75–80% e1RM, RPE ≤8.
- **Week 2:** 4×4 @ ~80–83%, RPE ~8.
- **Week 3 (intensification):** 5×3 @ ~85%, RPE ~9 top sets; trim accessories.
- **Week 4 (deload/realize):** 3×2 @ ~80% (or a light AMRAP single to update e1RM), volume to ~MV.

*[williams_2017, nsca_essentials, robinson_2024, helms_2016]* LP here is one valid option; DUP offered as an alternative (judgment call).

### H.3 Critique a flawed plan

**Input:** a 3-day "full body" week with 22 weekly chest sets vs 6 back; no hinge; five biceps isolations totalling 18 sets; 45-second rest on heavy squats; every working set at RPE 10.

1. **Imbalance (high).** Chest ~3.7× back. *Fix:* move ~8 sets to pulling. *[iusca_2021, nsca_essentials]*
2. **Missing pattern (high).** No hinge. *Fix:* add RDL or hip thrust, 3 sets. *[nsca_essentials]*
3. **Volume over MRV / junk volume (moderate).** Biceps 18 sets across five near-identical isolations. *Fix:* consolidate to ~9–12. *[pelland_2025, rp_landmarks]*
4. **Inadequate rest (moderate).** 45 s on heavy squats. *Fix:* 2–3 min. *[schoenfeld_rest_2016]*
5. **Effort too high (moderate).** All sets RPE 10. *Fix:* RPE 7–9. *[robinson_2024, refalo_2023]*

Critique proposes; it edits nothing.

### H.4 Progress from logged data

**Logged (double progression, bench 8–10 @ 185):** 10, 10, 9 reps, RPE 8/8/9.
- **Proposal:** 8–10 @ **190 lb** next week. *[nsca_essentials]*
- **e1RM suggestion:** 10 × 185 @ RPE 8 → Epley ≈ 247 vs prior 240 (+2.9%) → **"Bench e1RM 240 → 247? Accept / Ignore."** *[epley_1985]*
- **Stall contrast:** 8, 7, 6 @ 185, RPE 9/10/10 for three weeks → stall flag with deload/variation proposal. *[rp_landmarks]*

### H.5 Autoregulate and detect a deload

**Signals over 3 weeks:** actual RPE creeping above target at fixed loads; volume near MRV; two sessions missed; sleep averaging 5.5 h.

- **Autoregulation:** "Squat felt harder than prescribed the last two sessions at the same weight — back off ~5% today and keep RPE ≤8." *[helms_2023, robinson_2024]*
- **Deload proposal:** drop to ~MV, reduce intensity ~10%, framed as fatigue management. *[rp_landmarks, nsca_essentials]*

### H.6 Substitute an exercise

**Request:** replace back squat (no rack; dumbbells + leg press available).

1. **Leg press** — preserves squat pattern, quads/glutes; less stabilizer demand, higher SFR.
2. **Goblet squat** — preserves pattern with dumbbells; loading limited.
3. **Bulgarian split squat** — knee-dominant unilateral; more balance demand, higher per-leg fatigue.

### H.7 End-to-end trainer scenario (2.0: across three devices)

**Dana coaches Maya (returning intermediate, hypertrophy, right-knee history).**

1. **Generate — iPad, Sunday evening.** *Generate with Coach* for Maya with the knee contraindication on file; the engine drafts an upper/lower week preferring knee-friendlier quad work. Dana edits in the grid with the keyboard, runs **Critique**, and sends. Total time: eight minutes, hands never leaving the keys.
2. **Adjust — iPhone, Tuesday, on the gym floor.** Maya mentions her knee is stiff. Dana opens the phone, taps the client chip → Maya, opens Wednesday's session, taps the split squat `⋯` → **Substitute…**, picks leg press, and re-sends. Total time: forty seconds, standing up.
3. **Review — iPhone, Wednesday night.** The roster shows Maya's card with a pain flag. Dana taps through to compact review diff rows and sees exactly which sets went sideways.
4. **Progress — Mac, Thursday.** At her desk, Dana tiles Maya's window beside a template window, drags a replacement accessory across, accepts an e1RM suggestion, applies progression, and prints the week for their in-person session.

The plan object is the same throughout; the only thing that changed was which screen was nearest.

## Appendix I — Engine algorithms (implementable detail)

Deterministic given athlete state and knowledge-base version; every emitted prescription attaches citations via the builders (§12.2).

### I.1 Volume computation

```
func weeklyVolume(for athlete, week) -> [MuscleGroup: (direct, fractional)]:
    tally = empty
    for session in week.sessions:
        for item in session.strengthItems:
            def = library[item.exerciseKey]
            for set in item.workingSets where set.performer == .owner:   // partners excluded
                for m in def.primaryMuscles:   tally[m].direct     += 1.0
                for m in def.secondaryMuscles: tally[m].fractional += 0.5
    return tally

func volumeStatus(muscle, total, landmarks) -> Status:
    if total < landmarks.mev:  return .belowMEV
    if total in landmarks.mav: return .inMAV
    if total >= landmarks.mrv: return .nearOrAboveMRV
    return .betweenMEVandMAV
```

### I.2 Generate

```
func generatePlan(request: PlanningRequest, athlete) -> Plan:
    targets  = volumeTargets(goal: request.goal, level: athlete.level, landmarks: athlete.landmarks)
    patterns = requiredPatterns(request.goal)
    pool     = library.filter(equipment ⊆ request.equipment && not contraindicated(athlete.injuries))
    selected = selectExercises(pool, targets, patterns,
                               preferHighSFRForAccessories: true, balanceOpposingPatterns: true)
    sessions = distribute(selected, targets, days: request.daysPerWeek, sessionMinutes: request.sessionLength)
    for item in sessions.strengthItems:
        item.sets = prescribeSets(goal: sessionGoal(item), level: athlete.level,
                                  e1RM: athlete.e1RM[item.exerciseKey],
                                  effortBand: rirBand(request.goal), restByGoal: rest(request.goal))
        item.prepend(warmupRamp(item, e1RM))
    if request.wantsConditioning: addConditioning(sessions, avoidNearLegDays: true)
    plan = assembleWeeks(sessions, horizon: request.horizon,
                         model: request.periodization ?? .accumulationIntensificationDeload)
    plan.rationale = buildRationale(decisions)
    return plan
```

Where a generated item's set list matches a built-in `SetScheme`, the generator records `schemeApplied` so the author can re-parameterize it in one action (§32.4) rather than editing five rows.

### I.3 Critique

```
func critique(plan, athlete) -> [CritiqueFinding]:
    findings = []
    vol = weeklyVolume(athlete, plan.currentWeek)
    for (m, total) in vol:
        if total < landmarks(m).mev:  findings += flag(.belowMEV, m, fix: addSets,  cite: [iusca_2021, schoenfeld_2017])
        if total >= landmarks(m).mrv: findings += flag(.overMRV,  m, fix: trimSets, cite: [pelland_2025, rp_landmarks])
    if imbalanced(pressVolume, pullVolume): findings += flag(.imbalance, fix: rebalance, cite: [nsca_essentials])
    for p in requiredPatterns(plan.goal) where !covered(p, plan):
        findings += flag(.missingPattern(p), fix: addExerciseFor(p), cite: [nsca_essentials])
    for item in plan.strengthItems:
        if goalMismatch(item, plan.goal):            findings += flag(.intensityMismatch, ...)
        if allSetsAtRPE10(item):                     findings += flag(.effortTooHigh, cite: [robinson_2024, refalo_2023])
        if restTooShortForHeavyCompound(item):       findings += flag(.inadequateRest, cite: [schoenfeld_rest_2016])
        if contraindicated(item.exerciseKey, athlete.injuries): findings += flag(.contraindication, severity: .high)
    findings += concurrentTrainingConflicts(plan)
    findings += implausibleProgression(plan, athlete.e1RM)
    return prioritize(findings)
```

### I.4 Progression models

```
func nextStep(item, loggedResults, model, e1RM) -> Proposal:
    switch model:
      case .linear:             return allRepsHit(loggedResults) && maxRPE(loggedResults) <= item.targetRPE
                                       ? addLoad(item, increment) : hold(item)
      case .doubleProgression:  return topOfRepRangeHit(loggedResults)
                                       ? addLoadResetReps(item) : addRepsWithinRange(item)
      case .percentBased:       return applyPlannedPercentIncrease(item, week)
      case .rpeAutoregulated:   return holdRPETarget(item, adjustEstimatedLoad: e1RMTrend)
      case .volumeProgression:  return weeklyVolume(muscle) < mrv ? addOneWorkingSet(muscle) : proposeDeload()

func e1RMSuggestion(set, currentE1RM) -> Suggestion?:
    guard set.performer == .owner, set.reps in 1...10, set.completed,
          (set.rpe >= 8 || set.isAMRAP), set.actualLoad != nil
    est = epley(set.actualLoad, set.reps)
    if (est - currentE1RM)/currentE1RM > noiseThreshold: return .suggest(from: currentE1RM, to: round5(est))
    return nil

func stallCheck(exerciseHistory) -> Flag?:
    if noLoadOrRepProgress(over: 3 weeks) && effortRising: return .stall(suggest: [deload, variation])
```

### I.5 Substitution ranking

```
func substitutes(for key, reason, athlete) -> [Substitute]:
    target = library[key]
    candidates = library.filter(e ->
        e.movementPattern == target.movementPattern
        && overlaps(e.primaryMuscles, target.primaryMuscles)
        && e.equipment ⊆ athlete.equipment
        && not contraindicated(e.key, athlete.injuries))
    scored = candidates.map(e -> (e, score:
        musclesOverlap(e, target) * w1 + loadModeSimilarity(e, target) * w2
        + sfrPreference(e) * w3 - fatiguePenalty(e) * w4))
    return scored.sortedDescending().map(withTradeoffNote)
```

### I.6 Autoregulation and deload detection

```
func deloadCheck(athlete) -> Proposal?:
    triggers = 0
    if performanceDeclining(over: 2..3 sessions):      triggers += 1
    if actualRPE_above_target_at_fixed_load(recent):   triggers += 1
    if weeklyVolume_nearOrAbove_MRV(for: 2+ weeks):    triggers += 1
    if readinessPoor(sleep, hrv, selfReport):          triggers += 1
    if painFlagPresent(recent):                        triggers += 1
    if triggers >= threshold:
        return .deload(reduceVolumeTo: ~MV, reduceIntensity: ~10%,
                       explanation: fatigueManagement, cite: [rp_landmarks, nsca_essentials])
    return nil
```

### I.7 Insight generation

```
func insights(athlete) -> [Insight]:
    out = []
    for (m, total) in weeklyVolume(athlete):
        if belowMEV(m, total, sustained: 3 weeks): out += insight(.volumeLow(m), action: addSetsInPlan, cite: [iusca_2021])
    if imbalance(press, pull): out += insight(.imbalance, action: addPulling)
    for ex in trackedLifts:
        if e1RMTrendUp(ex):        out += insight(.progress(ex))
        if e1RMFlat(ex, 4 weeks):  out += insight(.stall(ex), action: deloadOrVary)
    if mostWorkingSetsEasy(lastWeek): out += insight(.effortLow, cite: [robinson_2024])
    if adherenceStrong(3 weeks):      out += insight(.encouragement)
    if readinessDip(permissioned):    out += insight(.recovery)
    return rankBySignal(out).topFew()
```

In trainer mode, `insights(client)` runs per client and feeds roster triage; the same ranking decides which single line appears on a compact client card.

### I.8 Scheme expansion (new in 2.0)

```
func expand(scheme: SetScheme, item, athlete) -> [PrescribedSet]:
    sets = []
    if scheme.params.includeWarmupRamp, let top = firstWorkingLoad(scheme, athlete):
        sets += warmupRamp(toward: top, steps: rampSteps(top))       // typed .warmup, cite: [nsca_essentials]
    switch scheme.kind:
      case .straightSets:            sets += repeat(n: params.workingSets, oneWorkingSet(params))
      case .doubleProgressionRange:  sets += repeat(n: params.workingSets, rangeSet(params))
      case .topSetBackoffs(let pct): sets += [topSet(params)] + repeat(n: params.workingSets - 1,
                                                 backoff(of: topSet, percent: pct))
      case .ascendingPyramid:        sets += ladder(params.loadSpec.percents, repsDescending: true)
      case .descendingPyramid:       sets += ladder(params.loadSpec.percents.reversed(), repsAscending: true)
      case .wave:                    sets += waves(params)
      case .emom:                    sets += minuteBlocks(params)
      case .custom:                  sets += params.explicitSets
    return sets.applyingDefaults(rest: params.restSeconds ?? rest(goal),    // cite: [schoenfeld_rest_2016]
                                 effort: params.effort ?? rirBand(goal))    // cite: [helms_2016, robinson_2024]
```

Expansion is pure and total; applying it is one undoable action that records `schemeApplied` with the parameters used.

## Appendix J — Built-in pre-made plan library

Templates store prescriptions as %1RM/RPE so they **individualize to the athlete's e1RM on instantiation**. Each carries an evidence note with citations.

### J.1 Beginner Full Body 3× (strength/general, beginner)
Three full-body sessions/week, linear load progression, one exercise per fundamental pattern. Compounds 3×5 starting ~65–70% e1RM (or RPE 7). *Why it works [williams_2017, nsca_essentials, robinson_2024]:* novices progress fastest with frequent full-body practice, simple linear overload, and effort short of failure. Equipment: barbell (dumbbell variant provided).

### J.2 Upper/Lower 4× Hypertrophy (hypertrophy, intermediate)
Per-muscle volume 10–16 sets/week in the MAV band; compounds 5–8 reps, accessories 8–12; effort 1–3 RIR; double/volume progression across 5 weeks + deload. *Why it works [pelland_2025, iusca_2021, robinson_2024, refalo_2024, rp_landmarks].* Mirrors H.1. Equipment: full gym.

### J.3 Push/Pull/Legs 6× (hypertrophy, advanced)
Higher weekly volumes approaching upper MAV/MRV; deload every 5–6 weeks with explicit MRV cautions. *Why it works [pelland_2025, rp_landmarks].* Equipment: full gym.

### J.4 3× Strength Block (strength, intermediate)
%1RM waves across a 4-week LP block, accessories for weak points. *Why it works [williams_2017, nsca_essentials, robinson_2024].* Mirrors H.2. Equipment: barbell.

### J.5 Dumbbell-Only Full Body 3× (hypertrophy/general, beginner–intermediate)
Full-body dumbbell sessions covering the patterns; load modes constrained to absolute/bodyweight-plus; double progression. *Why it works [iusca_2021, nsca_essentials].* Equipment: dumbbells only.

### J.6 General Fitness 3× + Conditioning (generalFitness, beginner–intermediate)
Two–three full-body strength sessions plus 2× Zone-2 cardio and optional intervals; conditioning separated from leg strength. *Why it works [acsm_guidelines, nsca_essentials].*

### J.7 Time-Crunched 30-Minute Full Body 3× (general/hypertrophy, any level)
Compact sessions built around high-SFR compounds with short-but-adequate rest and antagonist pairing. *Why it works [rp_landmarks, iusca_2021].*

### J.8 Partner Full Body 3× (new in 2.0; general/hypertrophy, any level)
Designed for two lifters sharing a bar and a rack: paired exercises with rotation-friendly rest (one lifter's set is the other's rest), per-performer loads via `performerOverrides`, and a session length that assumes alternation. *Why it works [schoenfeld_rest_2016, nsca_essentials]:* alternating sets makes adequate inter-set rest automatic rather than aspirational, which is the most common failure mode of time-pressed training. Free, like all partner functionality. Equipment: barbell + rack.

Users (and trainers) can save their own weeks/mesocycles as templates, and any hand-built set list as a **scheme** (§32.4).

## Appendix K — Detailed screen specifications and the mockup catalog

Screen-by-screen specs for the primary surfaces, complementing the per-screen visual mockups in `mockups/index.html`. Each screen lists its purpose, key elements, states, interactions, and matching visual file. Layouts are SwiftUI-native and platform-idiomatic. **Where a screen exists at more than one density, both mockups are listed and the spec states what differs.**

### K.0 Visual mockup catalog

Open `mockups/index.html` for the browsable catalog. Individual files live in `docs/plans/cladiron-mvp-revised/mockups/`, one per implementation screen.

**iPad — trainer workbench (`regular`)**

| Screen | Mockup | Spec anchor |
|---|---|---|
| Roster + dashboard | `ipad-roster-dashboard.html` | K.1 / §30 |
| Client overview | `ipad-client-overview.html` | §30.3 |
| Week board (3-column) | `ipad-builder-week.html` | K.2 / §31.1 |
| Per-set grid + inspector | `ipad-builder-set-grid.html` | K.3 / §31.3 |
| Menu bar, ⌘-hold HUD, palette | `ipad-menu-shortcuts.html` | K.4 / §33, App Y |
| Generate with Coach | `ipad-generate-with-coach.html` | §34.1 |
| Critique inspector | `ipad-critique-inspector.html` | §34.2 |
| Strength profile | `ipad-strength-profile.html` | §31.7 |
| Workout review | `ipad-workout-review.html` | K.9 / §36 |
| Templates + schemes | `ipad-templates-schemes.html` | §35, §9.9 |
| Copy-to-client drag | `ipad-copy-to-client-drag.html` | §33.4, §35.3 |
| Two clients, two windows | `ipad-multiwindow.html` | §31.6 |
| Invite client | `ipad-invite-client.html` | §30.4 / §42 |
| Choose connected/external delivery | `ipad-add-client-delivery.html` | K.14 / §30.6 / App Z |
| Export | `ipad-export.html` | §37 |
| Athlete planner on iPad (free) | `ipad-athlete-planner.html` | §20.4 |

**Mac — native macOS (`mac`)**

| Screen | Mockup | Spec anchor |
|---|---|---|
| Builder in a Mac window | `mac-builder.html` | K.5 / §38 |
| Dashboard + menu bar | `mac-dashboard.html` | §38.2 |
| Export via save panel + print | `mac-export.html` | §37.3, §38.2 |
| Athlete planner (free on Mac) | `mac-athlete-planner.html` | K.5a / §38.1, §44.2 |
| External packet sharing | `mac-external-share.html` | K.14 / App Z |

**iPhone — athlete (free, `compact`)**

| Screen | Mockup | Spec anchor |
|---|---|---|
| Home | `iphone-home.html` | K.6 / §21 |
| Plan week | `iphone-plan-week.html` | K.7 / §22.1 |
| Session editor — set stack | `iphone-session-setstack.html` | K.8 / §32.3 |
| Proven strength runtime | `iphone-proven-strength-runtime.html` | K.15 / App AA |
| Prescription bar (focused) | `iphone-prescription-bar.html` | K.8 / §32.6 |
| Scheme picker | `iphone-scheme-picker.html` | §32.4 |
| Shorthand entry | `iphone-shorthand.html` | §32.5 |
| Bulk select + apply | `iphone-bulk-select.html` | §32.7 |
| Exercise picker | `iphone-exercise-picker.html` | §31.2 |
| Move session to day | `iphone-move-session.html` | §8.4 |
| Assisted planning + rationale sheet | `iphone-assisted-planning.html` | §22.3, §17 |
| Progress | `iphone-progress.html` | §25 |
| Partner session | `iphone-partner-session.html` | §23 |
| Onboarding | `iphone-onboarding.html` | §28 |
| About and licensing boundary | `iphone-about-licensing.html` | §43.6 |
| Trainer plan received (client view) | `iphone-trainer-plan.html` | §24.2 |
| Active set runner | `iphone-active-set.html` | §27 |
| After-set rest | `iphone-after-set.html` | §27 |

**iPhone — trainer mode (Pro, `compact`)**

| Screen | Mockup | Spec anchor |
|---|---|---|
| Roster triage | `iphone-trainer-roster.html` | K.10 / §30.2 |
| Client week + client chip | `iphone-trainer-client-week.html` | K.11 / §32.8 |
| Client quick switcher | `iphone-client-switcher.html` | §32.8 |
| Review — diff rows | `iphone-trainer-review.html` | §32.11 / §36 |
| Copy to client + recalc preview | `iphone-copy-to-client.html` | §32.8 / §35.3 |
| Send preflight | `iphone-send-preflight.html` | §32.9 |
| Pro paywall + 30-day trial | `iphone-pro-paywall.html` | K.12 / §44.7 |
| Lapsed: read-only trainer surfaces | `iphone-trainer-lapsed.html` | §44.6 |
| External client Overview | `iphone-external-client-overview.html` | K.14 / §30.6 |
| External packet preflight + composer | `iphone-external-share-preflight.html` | K.14 / App Z |
| Record external result | `iphone-record-external-result.html` | K.14 / App Z.8 |

**Cross-platform artifact**

| Screen | Mockup | Spec anchor |
|---|---|---|
| HTML/PDF/text plan packet | `external-plan-packet.html` | K.14 / App Z.5 |

**Apple Watch**

| Screen | Mockup | Spec anchor |
|---|---|---|
| Root today plan | `watch-root.html` | §39.1 |
| Strength start | `watch-strength-start.html` | §39.1 |
| Set execution | `watch-set.html` | §39.2 |
| Post-set RPE | `watch-post-set-rpe.html` | §39.3 |
| Rest timer | `watch-rest.html` | §39.4 |
| Partner rotation | `watch-partner-rotation.html` | §39.5 |
| Cardio target | `watch-cardio-target.html` | §39.4 |
| Cardio complete | `watch-cardio-complete.html` | §39.4 |
| Mobility item | `watch-mobility.html` | §39.4 |
| Session RPE | `watch-session-rpe.html` | §39.6 |
| Complete summary | `watch-complete.html` | §39.6 |
| Substitute exercise | `watch-substitute.html` | §39.7 |
| Proven execution continuity | `watch-proven-execution-continuity.html` | K.15 / App AA |

### K.1 iPad — roster and dashboard

**Mockup.** `ipad-roster-dashboard.html`
**Purpose.** Roster-wide triage: who trained, who didn't, who needs attention.
**Elements.** Column 1: search, filter segmented control, client rows with status dots and colour tags, Templates section, Add client. Column 2: client cards with status, session pulse strip, prescribed-vs-actual signal, exception line, engine suggestions, quick actions. Column 3 (optional): the selected card's detail. Toolbar: New plan, Generate, Export.
**States.** Populated / empty (add your first client, trial terms stated once) / lapsed (read-only banner) / syncing.
**Interactions.** Select client → context; sort by needs-attention; `⌥⌘→` next client; drag a template onto a client row to instantiate.

### K.2 iPad — week board

**Mockup.** `ipad-builder-week.html`
**Purpose.** See and shape the whole training week.
**Elements.** Seven day columns with session cards (title, item summary, status); a weekly per-muscle volume bar row in the header with landmark markers; phase indicator; toolbar (Generate, Critique, Preview, Send).
**States.** Draft / sent / partially executed / deload week (visually marked).
**Interactions.** Drag sessions between days; drag items between sessions; duplicate/repeat; open a session → grid; keyboard: `⌘1..7` jump to day.

### K.3 iPad — per-set grid and inspector

**Mockup.** `ipad-builder-set-grid.html`
**Purpose.** Full-fidelity, keyboard-first per-set authoring.
**Elements.** Item header (exercise, e1RM chip, scheme chip, `⋯`); grid columns Set / Type / Reps / Method / %1RM / Weight / RPE / Rest; multi-select; inspector with rationale, critique findings, and exercise info; quick-add field (`⌘K`).
**States.** Editable / preview-as-client (read-only) / lapsed read-only / multi-select active.
**Interactions.** Full traversal (Appendix Y); right-click row menu; drag row handle; override %-weight keeps intent; `⌘⇧P` apply scheme.

### K.4 iPad — command surfaces

**Mockup.** `ipad-menu-shortcuts.html`
**Purpose.** Show that the trainer command set is discoverable without a Mac.
**Elements.** The pulled-down iPadOS menu bar with Plan and Edit menus open showing key equivalents; the ⌘-hold shortcut HUD; the `⌘K` command palette with fuzzy results.
**Interactions.** Every command also has a touch path (§33.1).

### K.5 Mac — builder

**Mockup.** `mac-builder.html`
**Purpose.** Demonstrate that the desktop app is native and is nonetheless the same product.
**Elements.** Mac window chrome and unified toolbar; real menu bar rendered from the shared `.commands` tree; three-column layout at desktop density; right-click context menu open on a set row; resizable inspector.
**Differences from iPad.** Row density, pointer-sized hit targets, native table behaviour, `NSSavePanel` export, printing, window title showing client + week, Services.
**Sameness with iPad.** The grid, the prescription model, the engine surface, and the rationale/citation components are literally the same `CadenceUI` views — a fact the mockup states explicitly, because it is the design constraint (§38.3).

### K.5a Mac — athlete planner (free)

**Mockup.** `mac-athlete-planner.html`
**Purpose.** Evidence for the clause that the Mac app is *fully functional for planning individual workouts* without any purchase.
**Elements.** Two-column athlete layout (Home / Plan / Progress / Profile sidebar + content); the same per-set grid the trainer uses; week volume bars; an insight card with citations; Apply-scheme and Plan-with-coach in the toolbar; a "no purchase needed" statement of the free tier.
**States.** Free (shown) / Pro (adds a Clients item to the sidebar). No paywall appears on this screen in either state.

### K.6 iPhone — Home

**Mockup.** `iphone-home.html`
**Purpose.** "What am I doing today / this week?" and "how is my training going?" — no live coach, no upsell.
**Elements.** Today card (title, summary, duration, Start; partner chip if applicable); This-week strip; canonical per-muscle progress indicators; top insight card; provenance banner when trainer-authored.
**States.** Loaded / empty / session-in-progress / rest day / offline / trainer-mode (one optional "3 clients need attention" line at the bottom).

### K.7 iPhone — Plan week

**Mockup.** `iphone-plan-week.html`
**Purpose.** Plan the week on a phone.
**Elements.** Action row (Plan with coach / Pre-made / Blank / Repeat / Insights); This-week / Next-week segmented control; week-balance card; seven day rows with session summary and status; add affordance per day.
**Interactions.** Tap a day → session editor; `⋯` → Move to day…, Duplicate, Delete; long-press a session for a context menu.

### K.8 iPhone — session editor, set stack, and the prescription bar

**Mockups.** `iphone-session-setstack.html` (stack at rest), `iphone-prescription-bar.html` (a set focused, Load field active), `iphone-scheme-picker.html`, `iphone-shorthand.html`, `iphone-bulk-select.html`.
**Purpose.** Author every field of every set on a phone (§32).
**Elements.** Ordered item list with `+ Strength / + Cardio / + Mobility / + Instruction`; per strength item a header (exercise, e1RM chip, `⋯`) and a **set stack** of chip rows; footer actions `+ Add set`, `⚡︎ Scheme`, `⌨︎ Shorthand`; the **prescription bar** with field picker, contextual control, and `‹ Set n of m ›` stepper.
**States.** Editable / locked (trainer-authored, client view) / selection mode / low-e1RM (%1RM offers RPE-only fallback) / partner per-performer segmented control.
**Interactions.** Tap a chip → focus that field in the bar; step across sets without dismissing; swipe row for duplicate/delete/convert; long-press → bulk select; drag handle to reorder.
**Accessibility.** Chips are adjustable elements; chip rows wrap at accessibility sizes; numbers never truncate (§32.3).

### K.9 Review

**Mockups.** `ipad-workout-review.html`, `iphone-trainer-review.html`
**Purpose.** Prescribed-vs-actual.
**Elements (iPad).** Header summary; per-exercise table with Prescription / Actual / Result columns; client note and pain flag; cardio/mobility results; actions.
**Elements (iPhone).** Diff rows with Rx over Did and a right-aligned outcome chip; matched sets collapse into a summary row so exceptions dominate the screen.

### K.10 iPhone — roster triage

**Mockup.** `iphone-trainer-roster.html`
**Purpose.** Triage a roster standing up, in under ten seconds.
**Elements.** Search + filter segmented control; client cards at triage height (name, status, pulse strip, one exception line, one primary action); sorted by needs-attention.
**Interactions.** Swipe leading → Review; swipe trailing → Message / Snooze; tap → client context.

### K.11 iPhone — client context and switching

**Mockups.** `iphone-trainer-client-week.html`, `iphone-client-switcher.html`
**Purpose.** Replace the sidebar with two-tap client switching.
**Elements.** Nav-bar client chip (initials + name); week list; toolbar (Generate, Critique, Send); the quick switcher sheet with recents and search.
**Interactions.** Tap chip → switcher (keeps the current destination); swipe left/right on the week header → previous/next client in the current sort.

### K.12 iPhone — the Pro gate

**Mockups.** `iphone-pro-paywall.html`, `iphone-trainer-lapsed.html`
**Purpose.** Present the gate honestly (§44.7).
**Elements.** A plain statement of the rule ("Training yourself is free. Coaching others is Pro."); a two-column free-vs-Pro list where the *free* column is not diminished; the three products with the 30-day trial clearly marked; restore purchases; a link to the pricing rationale.
**Forbidden elements.** Countdown timers, urgency copy, pre-selected upsells, "are you sure you want to miss out" interstitials, any appearance inside athlete or client surfaces.
**Lapsed state.** A single non-blocking banner over read-only trainer surfaces stating that clients remain connected and data remains exportable.

### K.13 Watch

**Mockups.** the prior twelve screens plus `watch-proven-execution-continuity.html`.
- **Set screen.** Exercise, set index, performer/history context, target/default reps + weight, warm-up, Crown adjustment, and **Log Set** into rest/rotation.
- **Post-set RPE (optional).** Crown scrolls RPE 6.0–10.0 (half-steps); Save / Skip.
- **Rest.** Countdown + next-set preview + Skip; haptic on complete.
- **Partner rotation.** Current lifter's name and colour dominate; "Complete Set" advances the rotation; per-lifter targets.
- **Cardio / cardio complete / mobility / session RPE / complete / substitute** as v1.0.

### K.14 External-client delivery and reporting

**Mockups.** `ipad-add-client-delivery.html`,
`iphone-external-client-overview.html`, `iphone-external-share-preflight.html`,
`external-plan-packet.html`, `iphone-record-external-result.html`, and
`mac-external-share.html`.

**Purpose.** Let a trainer coach any client without accounts, a Cladiron install,
or an Apple device while retaining one plan/review model and honest serverless
behavior.

**Required states.** Delivery choice; external Overview in awaiting/needs-entry/
recorded states; packet content/privacy preflight; ready-to-share choice; Mail
configured/unavailable; share/composer cancel/sent/fail; HTML/PDF/text preview;
manual completed-as-written; deviations/substitution/unplanned item; review and
append-only save; native Mac Mail/share/save/print.

**Accessibility.** Packet meaning never depends on color, tables have semantic
headers and linear reading order, PDF text is selectable, HTML remains legible
with images disabled, preflight toggles name the included sensitive field, and
every share route has a visible text label rather than an icon alone.

### K.15 Planning-to-execution continuity

**Mockups.** `iphone-proven-strength-runtime.html` and
`watch-proven-execution-continuity.html`.

**Purpose.** Make the boundary visually unambiguous: set-stack/grid/shorthand
screens author a prescription, while execution continues through the shipped
strength and cardio runtime. The iPhone mockup is the normative collapsed →
expanded → performer-specific-editor transition. The Watch mockup is the
normative session-hub → set/cardio → locally-saved transition.

**Forbidden substitution.** Do not reuse the planner's chip row as a live logged
set row; do not hide manual Add Exercise, finish, cancel, warm-up, partner, or
history controls when a plan exists; do not imply the phone must be reachable.
Static density may adapt, but the behaviors and data seams in Appendix AA do not.

## Appendix L — Platform requirements and deployment

### L.1 Deployment targets

- **iOS / iPadOS:** deployment floor **iOS 17** for the athlete app, so it reaches a broad installed base. **Trainer-mode command surfaces that depend on the iPadOS menu bar and windowing require iPadOS 26+**, and degrade to a toolbar-plus-palette command model below that — a capability *presentation* difference, not a capability difference (§33.1).
- **watchOS:** a floor aligned with the iOS floor's paired watchOS.
- **macOS:** a **native macOS target** (SwiftUI for macOS, AppKit where the platform expects it), supporting the current and prior major release. There is **no Mac Catalyst build** — one App Store record carries one macOS binary, and it is the native one (§38.7).
- **Devices:** iPhone and Apple Watch for a connected athlete; any email-, messaging-, PDF-, or print-capable device for an external client; iPhone, iPad, and Mac for the trainer. On-device LLM features are gated by availability (L.4).

### L.2 Capabilities and entitlements

- **iCloud / CloudKit** — private database and sharing. No custom auth.
- **HealthKit** — read heart rate and optional recovery signals; write workouts. Opt-in.
- **App Groups** — share the local store/config between the app, its Watch app, and extensions.
- **Background modes** — HealthKit workout processing on watchOS through the valid target configuration; CloudKit push/fetch on the phone; Live Activity updates on iPhone. Do not re-add the invalid Watch background mode removed by commit `8dcbd56`.
- **StoreKit 2** — Cladiron Pro; entitlement tied to the Apple ID; universal purchase across iPhone/iPad/Mac.
- **App Intents / SiriKit** — athlete and (Pro) roster intents.
- **Push notifications** — opt-in reminders and trainer↔client events.
- **Multiple scenes** (`UIApplicationSupportsMultipleScenes`) — required for iPad multi-window; the Mac target uses multiple `WindowGroup` scenes natively.
- **macOS entitlements** — App Sandbox, user-selected file read/write for export and template import, printing, and iCloud/CloudKit with the same container as iOS.
- **Shared bundle identifier** across the iOS and macOS targets — the mechanism behind Universal Purchase (§38.5, L.6).
- **System composition and sharing** — `MessageUI` and `UIActivityViewController` on iOS/iPadOS; `NSSharingService`, `NSSharingServicePicker`, `NSSavePanel`, and printing on macOS. These require no Contacts or mailbox entitlement: Cladiron supplies an export item, the trainer chooses a destination, and the operating system owns sending. The app must not request Contacts access for this feature.

### L.3 Performance targets

- **No spinners for local operations** on any idiom.
- **Instant launch to today's session** from cold launch or complication tap.
- **Watch responsiveness** under a live workout session; nothing lost if connectivity drops.
- **Deterministic engine latency**: generation/critique complete in well under a second for a week.
- **Compact authoring latency**: chip tap → prescription bar focused in < 100 ms; scheme apply on a 12-set item < 50 ms; shorthand echo updates per keystroke without dropped frames.
- **Roster scale**: 100 clients renders and filters without lag on the oldest supported iPhone.

### L.4 Feature flags

- **`GlassFeature.isEnabled`** — Liquid Glass materials on newer OSes, standard materials on the floor.
- **`MenuBarFeature.isEnabled`** — iPadOS menu bar; falls back to toolbar + command palette.
- **On-device LLM flag** — the natural-language layer; the app is fully functional without it (shorthand and the structured prompt remain).
- **HealthKit-readiness flag**.
- **`TrainerModeFeature`** — not a flag but a capability (§9.12); listed here to note it is *never* implemented as a build flag.

### L.5 Project structure and build

- **Swift Package `CadenceCore`** — model, engine, citation registry, entitlement resolver, sync abstractions. The Watch target depends on a lightweight execution subset.
- **Swift Package `CadenceUI`** — the shared SwiftUI view layer and view models used by both app targets. New in v2.1; it is what makes the native Mac target affordable and what the no-Mac-only-capability CI check inspects (§38.3).
- **App targets** — a universal iOS/iPadOS app with its embedded Watch app, plus a **native macOS app target**. Both app targets share the **same bundle identifier** and the same App Store record (§38.5). The Mac target contains shell code only; product features live in `CadenceUI`/`CadenceCore`.
- **Persistence** — SwiftData mirrored to CloudKit via `NSPersistentCloudKitContainer`; additive-only schema evolution; SHA-256 cache keys.
- **CI** — builds **both app targets** (iOS/iPadOS and native macOS) plus the Watch app; runs the evidence-gate checks (citation-resolution, rule-coverage, alias-uniqueness), the entitlement checks (no direct entitlement reads in views; every gated action enumerated), the **no-Mac-only-capability check** (no `CadenceUI` view compiled out under `#if os(macOS)`), the compact-authoring parity fixture across all three idiom pairs, and the engine/sync/export suites. Grep/AST gates enforce product rules (evidence gate, no-`Hasher`, no-analytics, no-inline-entitlement, no-Mac-only) as build invariants.
- **No server**, at all (§44.4).

### L.6 App Store considerations

- **One app record, Universal Purchase, and this is a one-way door.** The iOS and native macOS binaries share a bundle ID and live in a single App Store Connect record with both platforms selected. **Records that begin separate can never be merged**, so Universal Purchase must be configured before the *first* Mac submission — get this wrong once and one-purchase-covers-everything is permanently forfeit for this product. Treat it as a launch blocker, not a setting. This also resolves v1.0's open "two apps vs one app with trainer mode" question decisively: one record, one app, Trainer mode as an in-app subscription rather than a separate SKU.
- **The macOS binary is the native target.** A record carries one macOS build; there is no scenario in which both a Catalyst and a native Mac build ship.
- **Subscription metadata** must describe the free tier accurately; the App Store description leads with what is free.
- **Privacy nutrition labels** are minimal and truthful: no tracking, no analytics, no third-party sharing; data lives in the user's iCloud. HealthKit usage is disclosed and opt-in.
- **Not a medical device** (§18) is reflected in metadata and copy.
- **Review notes** should explain the partner-vs-client distinction, since a reviewer may otherwise wonder why "add a person" is sometimes free and sometimes gated.

## Appendix M — State machines and the edge-case matrix

### M.1 Session-execution state machine

```
            start                     finish
 planned  ─────────▶  inProgress  ─────────────▶  completed
    │                     │  │
    │ skip                │  │ abandon (app killed / user quits mid-session)
    ▼                     │  ▼
 skipped                  │  inProgress (resumable)  ──resume──▶ inProgress
    ▲                     │
    └──────── (a planned session whose day passes unexecuted → missed, feeds adherence)
              (mid-session substitution does not change status; it edits the item performed)
              (partner rotation advances performer within a set index; status is unaffected)
```

### M.2 Sync state machine (per record set)

```
 localDirty ──push attempt──▶ pushing ──ack──▶ synced
     ▲                          │
     │                          └─fail/offline─▶ queued ──connectivity──▶ pushing
     │
 remoteChange ──fetch──▶ merging ──(field-appropriate policy)──▶ synced
```

- **Result records** merge under **append-only**.
- **Plan edits** merge under last-writer-wins with the trainer as effective author for shared zones; a trainer's own two devices additionally stamp `lastEditedBy` and surface a notice.
- **e1RM** merges with the trainer's acceptance authoritative.
- **The hard rule:** the Watch never writes CloudKit. Live workout events remain local and queue durable WatchConnectivity payloads; only the phone reconciles them into its SwiftData/CloudKit store.

### M.3 Entitlement state machine (new in 2.0)

```
   free ──first gated action──▶ trial(30d) ──purchase──▶ pro
     ▲                              │                     │
     │                              │ expires             │ lapse / refund
     │                              ▼                     ▼
     └──────────────────── proExpiredGrace ◀──────────────┘
                                   │  (trainer surfaces read-only; clients stay connected;
                                   │   own training unaffected; export unaffected)
                                   └──restore/repurchase──▶ pro
```

- `free` never blocks athlete capability.
- `proExpiredGrace` is not a countdown to deletion; it is a stable terminal state until the user restores.
- Offline: the last verified entitlement is honoured for 14 days before entering grace.

### M.4 Edge-case matrix

| Situation | Behaviour |
|---|---|
| Log a set in Airplane Mode | Persisted locally (append-only); queued; flushes on reconnect. |
| App killed mid-session | Logged sets persisted; session resumable from last set. |
| e1RM changed after a plan was sent | Live plan unchanged (snapshot-at-send). |
| Client hasn't accepted the share yet | Trainer can build and queue; delivers on acceptance. |
| Trainer edits the same draft on iPad and iPhone | Last-writer-wins with a non-modal notice and undo; results unaffected. |
| iCloud signed out / unavailable | App fully usable locally; sync/sharing indicate they need iCloud. |
| %1RM prescribed with unknown e1RM | Falls back to RPE-only with a prompt; engine flags low confidence. |
| Implausible logged load | Prompts confirmation before driving an e1RM suggestion or future %1RM. |
| High-severity pain flag | Surfaced prominently; engine biases to backoff/substitution and recommends consulting a professional. |
| Trainer relationship ended | Client keeps local + exportable data; share access revoked. |
| **Pro lapses mid-block** | Trainer surfaces read-only; **client keeps their plan, keeps logging, results still arrive**; no share revoked. |
| **Trial expires with unsent drafts** | Drafts are preserved and visible; Send is disabled with a plain explanation. |
| **Trainer archives every client** | No gate is triggered; history and export remain; Pro can lapse harmlessly. |
| **Partner promoted to client without Pro** | The promote action opens the paywall; the partner session is untouched and remains free. |
| Cardio with no HealthKit permission | Cardio still runs; HR not recorded; readiness insights unavailable. |
| Migration from live-coach version fails | Fails safe: prior store preserved, no data loss; retried; user informed plainly. |
| Duplicate exercise across clients | %-based loads recompute from the destination client's e1RM; absolute loads copy as-is. |
| Session with only mobility/instruction items | Runs as a checklist; contributes no working-set volume. |
| Deload week | Volume drops to ~MV; insights won't flag "below MEV" during a known deload. |
| **Shorthand alias ambiguity** | A chip row of candidates; never an auto-pick. |
| **Scheme applied to an item with existing sets** | Replace or Append, chosen explicitly; one undoable action. |
| **iPad window resized below the split-view threshold** | Layout degrades to the compact arrangement (set stack + prescription bar), not a broken grid. The Mac target instead declares a minimum window width and never enters this path. |
| **Pro purchased on iPhone, then the Mac app is launched** | Already entitled. StoreKit 2 syncs the transaction on the Apple ID; no restore step, no second purchase, no prompt. |
| **Client added on the Mac while the iPad is offline** | The roster converges when the iPad reconnects (private-database sync); the client's share is owned by the Apple ID, so either device can subsequently author and send. |
| **Keyboard attached to iPhone** | Full command set enables; ⌘-hold HUD appears. |

## Appendix N — Data-flow sequences

### N.1 Trainer → client plan delivery

1. **Author** — the trainer builds/generates a plan on any device (local SwiftData write, provenance `trainerAuthored`).
2. **Critique (optional)** — findings render; fixes applied.
3. **Preflight** — the Send sheet shows the week summary, critique count, and the weights that will freeze (§32.9).
4. **Send** — %1RM loads resolve and snapshot; the hierarchy is written into the client's shared zone.
5. **Notify** — optional push.
6. **Receive** — the client's device fetches the change; the plan appears attributed, execute-only.
7. **Distribute to Watch** — the current session's items/sets sync iPhone → Watch.

### N.2 Client → trainer result return

1. **Execute** — the client runs the session under a runtime session; results log locally (append-only).
2. **Finish** — status written; **sync flushes** (not before).
3. **Reconcile** — every trainer device fetches the change; dashboards update.
4. **Review** — prescribed-vs-actual, notes, pain flag.
5. **React** — accept an e1RM suggestion / apply progression / insert a deload / message; author next week.

### N.3 Single-user cross-device flow

1. The athlete (or trainer) edits on iPhone/iPad/Mac → local SwiftData write → mirrored to the **private** CloudKit database.
2. Other devices fetch and converge (last-writer-wins for plan edits; append-only for results).
3. The current session syncs to the Watch; execution logs locally; results flush after the session.
4. Progress/insights recompute locally on each device.

### N.4 Plan lifecycle

```
 draft ──activate/send──▶ active ──(week ends or replaced)──▶ archived
   │                        │
   │ (edit freely)          │ (self: editable; trainer-authored: execute-only for client)
   ▼                        ▼
 (generate / template / scheme / shorthand / manual all produce a draft first)
```

### N.5 The execute → progress → plan loop

```
        ┌───────────────────────────────────────────────┐
        ▼                                                │
   [Plan week] ──▶ [Execute on Watch] ──▶ [Results logged]│
        ▲                                      │          │
        │                                      ▼          │
   [Insights + Progress update] ◀── [Progress/Volume/e1RM recompute]
        │                                      │
        └──────── [Engine proposes next week] ◀┘
```

Identical for self-coached and coached; the difference is only who authors the next week, and on which screen.

### N.6 e1RM update flow

1. A qualifying set is logged (§B.5).
2. The engine raises a **suggestion** (Strength Profile / dashboard for a trainer; Progress / Plan for self).
3. The human **accepts** or **ignores**.
4. The updated e1RM affects only **future** prescriptions; already-sent plans are snapshotted.

### N.7 Entitlement flow (new in 2.0)

1. A surface asks `CadenceCore` for a `TrainerCapability` (never for raw entitlement state).
2. The resolver reads the cached `ProEntitlement`, revalidating against StoreKit 2 when online and stale.
3. If the capability is absent, the surface presents the **paywall** (user-initiated actions only) or a **read-only banner** (lapsed).
4. Purchase or trial start updates the entitlement; capabilities recompute; nothing else in the app changes state.
5. A capability change **never** mutates training data, shares, or plans.

## Appendix O — Design system, adaptive layout, and visual language

The visual language is native-Apple with a purposeful, "serious training tool" character, matching the mockups. It signals rigor and focus, not gamified consumer fitness.

### O.1 Aesthetic principles

- **Native first.** SwiftUI-idiomatic layouts, standard navigation (tab bar on iPhone, split view on iPad/Mac, glanceable stacks on Watch), system controls.
- **Instrument, not toy.** Restrained palette, precise data typography, generous whitespace, no confetti/streaks/badges.
- **Data is the hero.** Numbers (loads, %1RM, RPE, volume) are set in a monospaced face for scannability and alignment.
- **The same object should look like itself at every size.** A set is a row of values on iPad and a row of chips on iPhone — different affordances, recognizably the same thing, same order of fields (Type → Reps → Load → Effort → Rest) everywhere including the Watch.

### O.2 Colour tokens

- **Iron / graphite neutrals** — the structural palette.
- **Ember accent — `#B23A2E`** — the single strong accent for primary actions, "today," and key highlights; used sparingly.
- **Semantic status** (never colour-alone; always paired with a text label): on-target / positive, caution / harder-than-prescribed, missed / negative, informational. Volume-vs-landmark uses a graded scale.
- **Partner colours** — a small fixed palette (`colorIndex`) for rotation identification, chosen to be distinguishable in common colour-vision deficiencies and always paired with initials.

### O.3 Typography

- **Data / numeric:** a monospace face for loads, percentages, RPE, timers, and grid/chip values.
- **Headers / emphasis:** a condensed athletic face for section headers and titles.
- **Body / UI:** the system font, with Dynamic Type support.

### O.4 Spacing, density, and hit targets

| | compact (touch) | regular (touch) | regular (pointer) | mac |
|---|---|---|---|---|
| Minimum hit target | 44 pt | 44 pt | 28 pt | 28 pt |
| Set row height | 52 pt (chips) | 40 pt (grid) | 32 pt | 26 pt (Compact rows) |
| Section padding | 16 pt | 20 pt | 20 pt | 12 pt |
| Chip separation | ≥8 pt | n/a | n/a | n/a |

Density is chosen by **input type**, not idiom: an iPad with a trackpad gets pointer metrics; the same iPad in the hand gets touch metrics.

### O.5 Component patterns

- **Per-set grid** — the regular-width signature: aligned monospaced columns, warm-up vs working visually distinct, multi-select.
- **Set stack + chip row** — the compact-width signature: one row per set, value-first chips, each independently tappable (§32.3).
- **Prescription bar** — the compact editor: field picker, contextual control, set stepper (§32.6).
- **Scheme card** — a named set-list generator with a one-line preview (§32.4).
- **Shorthand echo** — typed text rendered live as the chips it will produce (§32.5).
- **Status dot** — client/session status at a glance.
- **Session pulse strip** — per-set completion cells for dashboard triage.
- **Prescribed-vs-actual row / diff row** — the review pattern at two densities.
- **Rationale + citation chips** — a claim with a confidence chip and tappable citation pills.
- **Insight card** — headline + short evidence-anchored text + optional action; sparse.
- **Muscle indicators** — canonical `MuscleGroup` trend + volume-vs-landmark status.
- **Capability banner** — the read-only lapsed state; informational, never modal, never red.

### O.6 Liquid Glass and newer-OS materials

Adopt newer materials **surgically** behind a feature flag: bars, cards, and the runner on supporting OSes, standard materials on the floor. The design must read as intentional and native on both; no layout depends on the new material.

### O.7 Watch-specific

- One dominant figure per screen; secondary details smaller.
- Colour-coded but label-backed states; strong haptics for rest/interval transitions.
- The Digital Crown is the primary adjustment input; nothing critical requires precise touch mid-set.
- In partner rotation, the current lifter's name is the dominant element.

### O.8 Mac-specific

- Source-list sidebar and inspector styling; unified toolbar; Compact rows on by default.
- Pointer hover states on every actionable row; drop badges that describe the result of a drag.
- Standard Mac control sizing and type scale rather than iPad's.

## Appendix P — Content and copy guidelines

### P.1 Voice

- **Knowledgeable peer, not a hype coach.** Direct, precise, respectful. No exclamation-point cheerleading, no gamified praise, no manufactured urgency.
- **Concrete over vague.** "Chest volume has been ~6 sets/week for 3 weeks — below the growth threshold" beats "Let's crush chest!"
- **Confident where the evidence is strong; honest where it isn't.**

### P.2 Evidence-honesty in copy

- State the **basis** briefly and offer the **citation**.
- **Never overclaim.** Avoid "optimal," "perfect," "guaranteed."
- **Label judgment calls.**
- **Estimated means estimated.**

### P.3 Confidence phrasing

- **strong** — "The evidence strongly supports…"
- **moderate** — "The evidence supports…" / "generally…"
- **limited** — "Limited evidence suggests…" / "as a practical guideline…"
- **judgmentCall** — "This is a judgment call — reasonable options include…"

### P.4 Safety and pain copy

- **Not a medical device**, stated plainly in onboarding and where relevant.
- **Pain flags** are acknowledged without diagnosis; at higher severities: "That level of pain is worth taking seriously — consider stopping this movement and checking with a qualified professional before loading it again."
- **Readiness** is framed as a soft signal, never a clinical assertion.
- **Failure/effort** — encourage effort short of failure by default.

### P.5 Empty-state copy

- New user, no plan: "Plan your week — build it yourself, start from a pre-made plan, or let the coach draft one for you."
- New trainer: "Add your first client to start programming. The first 30 days are free."
- New client, no plan: "Your coach hasn't sent a plan yet — you're connected and ready."
- Empty roster after archiving everyone: "No active clients. Your history and exports stay right here."

### P.6 Notification copy

- **Sparse, useful, opt-in.** "Today: Lower Body + Conditioning" / "Coach Dana sent your week" / "Maya completed today's session" / "Maya flagged knee discomfort."
- Exactly one billing notification exists: the trial-ending reminder.
- No "we miss you" re-engagement bait, ever.

### P.7 Error copy

Plain, non-blaming, actionable. "This will sync when you're back online." "That weight looks unusually high for you — is it right?" "We kept your data safe and will try again."

### P.8 Paywall and tier copy (new in 2.0)

The tier boundary is a product value, so its copy is specified rather than left to marketing instinct:

- **Lead with the rule, not the price.** "Training yourself is free, forever. Coaching someone else is Cladiron Pro."
- **Name what stays free, on the paywall itself.** Listing the free tier on the purchase screen is unusual and deliberate: it is the clearest possible signal that the product is not withholding value to force an upgrade.
- **Explain the boundary in the user's terms.** "Partners train beside you — that's free. Clients get plans from you on their own device — that's Pro."
- **Never imply the free tier is degraded.** Avoid "basic," "limited," "lite," or "upgrade to unlock the real coach." The free coach *is* the real coach.
- **Trial copy is factual.** "30 days free, then $X/year. Cancel any time in Settings." One reminder before it converts.
- **Lapse copy is reassuring and specific.** "Cladiron Pro has ended. Your clients are still connected and their plans still work — you just can't author or send new ones until you resume. Everything you've made stays here and stays exportable."
- **Forbidden:** urgency timers, scarcity claims, "most popular" badges engineered to steer, guilt copy, and any monetization language inside athlete or client surfaces.

## Appendix Q — Decision log and traceability

### Q.1 Key standing decisions (with rationale)

| Decision | Rationale | Where |
|---|---|---|
| **Native macOS app, in the same App Store record via Universal Purchase** *(v2.1 — supersedes the v2.0 Catalyst decision, which superseded v1.0's separate Mac product)* | The mobile-first insight holds, but the desktop delivery mechanism was wrong. Catalyst's cost is that a professional tool reads as an iPad app in a window, and Apple's guidance is native SwiftUI for a new multi-platform app. Shared `CadenceUI` makes a second target affordable; Universal Purchase preserves "one product, one purchase," which was Catalyst's real advantage. One record carries one macOS binary, so native **replaces** Catalyst. | §2.3 (full arc), §38, L.6 |
| **No Mac-only capability, enforced in CI** *(new, 2.1)* | The only thing that stops a second app target becoming a second product | §38.3, §49.24 |
| **Universal Purchase configured before the first Mac release** *(new, 2.1)* | Separate App Store records can never be merged; a mis-configured first release permanently forfeits one-purchase-covers-everything | §38.5, L.6, §51.2 |
| **One universal app with a Trainer *mode*, not two apps** *(new, 2.0)* | One purchase, one mental model, one sync graph; resolves v1.0's open packaging question | §7.1, §20.2, L.6 |
| **Full trainer authoring on iPhone, governed by an expressiveness rule** *(new, 2.0)* | The moment programming happens is often standing in a gym; parity is testable (§49.12) rather than aspirational | §32.1, §32 |
| **Compact authoring = schemes + shorthand + chip rows + prescription bar + bulk apply** *(new, 2.0)* | Layered coarse-to-fine input beats a shrunken spreadsheet; only outliers pay the per-field cost | §32.2 |
| **Deterministic shorthand grammar, not an LLM** *(new, 2.0)* | Offline, testable, instant, and safe; the LLM stays an optional layer above it | §32.5, §16.1 |
| **Pro gates coaching others only; all self-coached use is free** *(new, 2.0)* | Clean, honest line; removes upsell pressure from training surfaces; willingness to pay lives in the professional use case | §44.1–44.3, Principle 10 |
| **Any client requires Pro — no free-client tier, no per-seat pricing** *(new, 2.0)* | One-line pricing, no incentive to under-report, same product for one client and forty | §44.3 |
| **30-day trial starting at first gated action** *(new, 2.0)* | Measures real use, not shelf time | §44.4 |
| **Entitlement never gates existing data; lapse leaves clients connected** *(new, 2.0)* | A billing event must never break someone else's training | §44.6, §42.5 |
| **Partner ≠ client, in the model and the price** *(new, 2.0)* | Prevents both user confusion and a leaky paywall | §8.5, §9.11, §23 |
| **Set schemes as a first-class model type** *(new, 2.0)* | Makes phone authoring viable and replaces the ad-hoc "Apply Pyramid" | §9.9, §32.4 |
| **Fully serverless — the thin billing endpoint is withdrawn** *(new, 2.0)* | StoreKit 2 + Apple ID resolves entitlement; the last server exception is unnecessary | §44.4 |
| **Serverless via CloudKit sharing** (no custom backend, no accounts) | Nothing to build/secure/scale/pay for; privacy by construction | §42 |
| **SwiftData mirrored to CloudKit** (not GRDB + a hand-written sync layer) *(v2.2 — follows the shipped app; supersedes v1.0's GRDB decision, which the product itself reversed on 2026-07-27)* | The reliability concern that motivated GRDB did not materialize: SwiftData + `NSPersistentCloudKitContainer` ships in production, on watchOS included. Specifying a persistence rewrite would have been the single most expensive line in this document, for no product benefit. The correctness rules that mattered — snapshot-at-send, no-sync-during-a-runtime-session, append-only results — are store-independent and are retained. | §10.1–10.2 |
| **Engine decides + cites; LLM only parses/narrates** | Safety, determinism, testability, differentiation | §11, §16 |
| **Evidence-gated knowledge base** (every rule cited; CI-enforced) | "Evidence-based" made verifiable | §12, §13, App A |
| **Retire the always-on live coach → weekly planner** | Separates planning from execution; restores agency; maps to the trainer product | §2.1, §19 |
| **Unified planning model** (self/trainer/template author the same Plan) | One engine, many screens | §8 |
| **%1RM snapshot at send/start** | Concrete numbers that don't drift mid-block | §10.4, §13.3 |
| **`HKWorkoutSession` on Watch; phone-owned CloudKit; durable idempotent handoff** | Preserves live HR/background execution and prevents unreachable-phone data loss or duplicate imports | §41.1, App M, App AA |
| **Append-only logged results** | A real logged set is never overwritten | §10.2, §46.3 |
| **Anti-lock-in Excel export, free for everyone** | Trust + acquisition lever; counters incumbents' lock-in | §37, §43.4 |
| **Per-muscle progress on Home; Insights retained** | Preserves the shipped DB++ 20-muscle model | §21, §25, §26, App AA |
| **Small in breadth, deep in depth** | Protects the moats | §3.2, Principle 11 |
| **SHA-256 cache keys (never Swift `Hasher`)** | `Hasher` reseeds per launch | §10.1, §46.3 |

### Q.2 Traceability to companion documents

- **`REVISION-NOTES.md`** — the section-by-section diff from v1.0, including what was deleted and why. *(Present.)*
- **`TRAINER_PLATFORM_STRATEGY.md`** — business case, market, positioning. Where business packaging is open (price points, payment routing), the strategy doc governs and this spec supports either outcome. ***Not present in this repository*** — inherited from v1.0's reference list; the positioning material this spec depends on is restated self-containedly in Appendix R, and the open business decisions in Q.3.
- **`DATABASE_SWIFTDATA_MIGRATION.md`** — v1.0's persistence-layer analysis, which argued for GRDB. ***Not present in this repository***, and **superseded in substance**: the product reversed to SwiftData + CloudKit mirroring on 2026-07-27 and v2.1 follows the shipped architecture (§10.1, Q.1). Cited here only as the origin of the two hard sync rules, which survive the reversal intact.
- **v1.0 `cladiron-mvp/CLADIRON_PLATFORM_SPEC.md`** — superseded; retained for the Mac-app design should the decision ever be revisited.
- **`mockups/index.html`** — the per-screen visual reference catalog.
- **`Cladiron-Coaching-Export-Sample.xlsx`** — the concrete target format for export.

### Q.3 Decisions resolved 2026-08-11

Every business decision this specification had left open is now closed. They are recorded here with their resolution so the document has no dangling questions.

| Decision | Resolution | Where it lands |
|---|---|---|
| **Persistence** — v1.0's GRDB vs the shipped SwiftData + CloudKit | **SwiftData mirrored to CloudKit**, following the shipped app. No persistence rewrite; the two hard sync rules survive intact. | §10.1–10.2, Q.1, W.2/W.3 |
| **Module naming** | **`CadenceCore` / `CadenceUI` / `CadenceCommands`** internally; **Cladiron** is user-facing only. | Throughout; matches the repo's standing naming rule |
| **Status of this document** | **Adopted as the roadmap.** `CLAUDE.md` gains a roadmap pointer now; the shipped-behaviour sections there change only when the corresponding phase lands. | §3.3, `CLAUDE.md` |
| **Pro price points** | **$99/yr · $12/mo · $249 lifetime**, plus tip-jar consumables that unlock nothing. | §44.4 |
| **Lifetime tier** | **Available indefinitely** — not a launch promotion. Honest because marginal cost of service is zero. | §44.4 |
| **Stripe service-payment routing** | **Permanent non-goal.** The last candidate to reintroduce a server is closed; the platform is unconditionally serverless. | §3.2, §44.4 |
| **Group / cohort programming** | **Non-goal.** Multi-client apply covers the practical need. | §3.2, §35.3 |
| **iPadOS 26 as the trainer-mode floor** | **No — a presentation difference.** Below 26 the menu bar is unavailable and commands fall back to the toolbar plus the ⌘K palette. Capability never differs. | L.1, §33.1 |
| **Localization scope** | **English at launch, architecture localization-ready.** Per-locale cost (including alias curation) is stated rather than discovered later. | §45.2 |
| **Policy defaults** (trial starts at first gated action; archived clients don't count; 14-day offline entitlement; 3 partners max; `CadenceUI` as a package; compact authoring in Phase 1) | **Ratified as specified.** | §44.4, §44.3, §44.6, §9.11, §7.1, §47 |

### Q.3a Decisions deliberately left to implementation

Not open questions — just things that should be settled by whoever writes the code, not by this document: exact spacing tokens, the built-in scheme library's final membership, notification copy wording, and the order of work *within* a phase.

### Q.4 What would make this spec wrong

Stated plainly so they can be checked:

- That **compact-width authoring is genuinely usable** for real programming. If trainers author on iPhone only to *view* and always retreat to iPad to *build*, §32 has failed and the honest response is to narrow the phone's role rather than pretend.
- That **a native Mac target stays cheap enough for a solo developer**, because the view layer is shared. The measurable signal is the size of the platform-conditional surface: if `#if os(macOS)` starts appearing inside `CadenceUI` rather than staying in the Mac shell, or if Mac-specific regressions begin gating iOS releases, then v2.0 was right about the maintenance cost and Catalyst (or dropping the Mac again) returns to the table. §38.4 states the cost honestly so this bet can actually be checked.
- That **Universal Purchase is worth the configuration risk**. It is a one-way door (L.6); if it were mis-set at launch, the product would face exactly the "download the other app for the Mac" problem v2.0 was right to reject.
- That **giving the expert system away free is net-positive**. If it drives adoption without converting coaches, the tier line (§44) is where to look — but the fix is pricing, not withholding the coach.
- That **one client is worth $99/yr** to a hobbyist coach. If Rae-type users start trials and do not convert, the answer is a cheaper entry price — not a metered tier, which would punish exactly the growth the product wants.
- That **native Apple depth (especially the Watch) is a durable moat**, that an **evidence-gated deterministic engine beats black-box AI generation** on trust and liability, that **serverless CloudKit sharing is reliable enough**, that **separating planning from execution** serves serious lifters, and that **focus wins over breadth** (carried forward from v1.0).

## Appendix R — Competitive positioning and moats

### R.1 The incumbents and where they're weak

The remote-coaching platform market (Trainerize, TrueCoach, Everfit, FitBudd, and coaching services like Future) is established but leaves clear openings:

- **Weak native execution, especially on Apple Watch.** Cross-platform architectures produce watch apps that are unreliable for the one thing a strength app must nail: logging sets on the wrist mid-workout.
- **Desk-bound programming.** The builders are web dashboards; the mobile apps are for *clients*, not for the coach's authoring. A coach standing in a gym with a phone cannot do real work. **This is the specific gap v2.0 attacks.**
- **Lock-in.** Migrating years of programming off an incumbent is painful; few offer painless full-data export.
- **Add-on-stacked pricing.** Features are unbundled and priced up.
- **Black-box "AI" bolt-ons.** Recent "AI workout generators" are GPT wrappers — undifferentiated, non-deterministic, liability-prone.
- **Breadth over depth.** Nutrition, habits, messaging, and business tooling dilute the core.

### R.2 Cladiron's differentiation

- **Native Apple-ecosystem depth (the primary moat).** A flawless Watch execution experience, Live Activities, complications, HealthKit, the Digital Crown, Handoff, the iPad menu bar, multi-window.
- **Programming that travels (new in 2.0).** The only professional programming surface that works properly on a phone, and the same app on iPad and Mac. A coach can build a week between clients rather than at 11 p.m. at a laptop.
- **The evidence-gated expert system.** A deterministic, cited engine that generates, critiques, progresses, substitutes, autoregulates, and explains — and, uniquely, is **free to every self-coached athlete**, which turns the differentiator into an acquisition channel.
- **Serverless, privacy-first, no-lock-in architecture.** No backend, no accounts, no telemetry, no ads; data in the user's iCloud; one-click export.
- **Honest economics.** Free for athletes and clients; one flat Pro tier for coaching, whether that is one client or forty; a 30-day trial; no dark patterns.
- **Focus.** Deep and narrow beats broad-and-shallow for the serious strength segment.

### R.3 Beachhead and expansion

- **Beachhead:** independent strength coaches with Apple-Watch-wearing clients, plus self-coached intermediate+ lifters. The free expert system makes the second group a growth engine for the first — every self-coached user is a latent coach, and every coached client already has the app.
- **Wedge:** the Watch execution experience, the free evidence-based planner, and phone-native programming.
- **Expansion:** from independent coaches to small gyms/teams; deepening the engine rather than widening scope.

### R.4 Why the moats hold

Native depth compounds; the evidence-gated engine is a body of cited, tested logic a prompt can't replicate; the serverless/no-lock-in stance is a values commitment a VC-funded, data-monetizing incumbent structurally struggles to match; and the mobile-authoring capability is an architectural consequence of being Apple-native that a web-dashboard competitor cannot cheaply copy. The main risk to the moats is internal — scope creep — which the non-goals exist to prevent.

## Appendix S — Requirements traceability matrix

Maps the explicit requirements of **this revision** (and the carried-forward v1.0 requirements) to the sections that fulfil them.

| Requirement | Fulfilled in |
|---|---|
| **Eliminate the native Mac version** | §2.3 (rationale), §3.2 (explicit non-goal), Part V (rewritten without it), Q.1 (decision), App L.1/L.5 (no AppKit target), G (changelog) |
| **Trainer plan-creation functionality exists in full on iPad** | §29 (IA), §31 (the full planner), §34 (assistance), §35 (templates/multi-client), §36 (review), §37 (export), K.1–K.3 |
| **…including keyboard shortcuts** | §31.3 (grid traversal), §33 (command system), Appendix Y (full table), §49.22 (acceptance), K.4 |
| **Keep the native Mac app** | §2.3 (the decision arc), §38 (whole section), §38.1–38.2 (what is shared vs native), §38.7 (native rather than Catalyst), L.1/L.5, K.5 |
| **…distributed via the same App Store entry, universal purchase** | §38.5 (mechanics: shared bundle ID, one record, shared StoreKit products, the no-merge constraint), §44.4, L.6, §49.29 |
| **…fully functional for planning individual workouts** | §38.1 (same `CadenceUI`, no feature list difference), §38.3 (no Mac-only capability, CI-enforced), §44.2 (the free list applies on every surface), §49.27, K.5a + `mac-athlete-planner.html` |
| **…in-app purchase only for adding clients** | §44.1 (the one-sentence rule), §44.3 (what Pro unlocks — clients and nothing else), §9.12 (`TrainerCapability`), §49.26–27 |
| **…clients addable from iPhone or iPad as well** | §30.4 (add/invite from any idiom), §32.8 (compact roster and client switching), §42.1 (shares are owned by the Apple ID, so every device can author and send), §49.25 |
| **…with iCloud keeping everything in sync** | §10.2 (private-database sync of roster, drafts, templates across the user's own devices), §42.4 (conflict policy incl. the trainer's own two devices), §46.2 (same draft open on two devices), §49.25 |
| **iPhone gains Pro-tier trainer-only functionality to support clients** | §20.2 (where it lives), §30.2 (compact triage), §32 (compact authoring), §32.8 (client switching), §32.9 (send), §32.11 (review), K.10–K.11 |
| **Well designed for the smaller screen and touch space** | §32.3 (chip rows, 44 pt targets, Dynamic Type, VoiceOver), §32.6 (prescription bar), §32.12 (one-handed ergonomics), O.4 (density table) |
| **I must be able to create plans entirely on-phone (less efficient is fine)** | §32.1 (normative expressiveness rule), §32.2 (the five layers), §49 criterion 12 (parity acceptance test), §32.10 (honest list of what is slower) |
| **Same Pro tier, except any client requires Pro** | §44.1 (the rule), §44.3 (what Pro unlocks; no free-client tier), §8.5 (partner vs client), §9.12 (entitlement model) |
| **Pro supports both iPhone and iPad** | §44.4 (universal purchase across iPhone/iPad/Mac), L.6 |
| **30-day free trial** | §44.4 (trial starts at first gated action), M.3 (state machine), §46.4 (one reminder), §49.24 |
| **Free tier can fully plan own workouts, including partners** | §44.2 (normative free list), §22 (the full planner, free), Part III tier note (whole expert system free), §23 (partner sessions), §49.5/§49.25 |
| Retire the always-on live coach; keep insights; per-muscle progress on Home | §19, §21, §25, §26, App AA |
| Plan tab: manual, pre-made, assisted; plan from self or trainer | §22, §24 |
| Preserve per-set model, %1RM/e1RM, cardio, review, sharing, export | §9, §13.3, App B, §36, §42, §37 |
| **Extensive mockups for every delivery and execution surface, multiple per view where needed** | App K.0 (catalog: 16 iPad + 5 Mac + 29 iPhone + 13 Watch + 1 cross-platform packet), `mockups/index.html` |

### S.1 Where the "phone must do everything" requirement is enforced

Because this is the revision's most demanding requirement, it is enforced in four independent places so it cannot quietly erode: the **normative rule** (§32.1), the **acceptance criterion** (§49.12), the **CI parity fixture** (§50), and the **work-stream done-condition** for WS-SETSTACK and WS-IPHONE-TRAINER (§48).

## Appendix T — Quick-reference cheat sheet

**Tiering:** training yourself = free on every surface, Mac included (whole expert system and partners); coaching anyone else = Pro; 30-day trial from first gated action; **one Universal Purchase covers iPhone/iPad/Mac** (shared bundle ID, one App Store record — configure before the first Mac release, records can never be merged); lapse = read-only trainer surfaces, clients stay connected.
**Targets:** universal iOS/iPadOS app (+ embedded Watch app) and a **native macOS app**, over `CadenceCore` + `CadenceUI`. No Mac-only capability, ever — CI-enforced.
**Idioms:** compact (iPhone/narrow iPad) · regular (iPad) · mac (native macOS app, same App Store record via Universal Purchase). Layout differs; capability never does.
**Compact authoring:** schemes → shorthand → chip rows → prescription bar → bulk apply.
**Shorthand:** `bench 4x8 @70% rpe8 r2:30` · `sq 5x5 @315 warm3` · `pullup 3xamrap @bw` · `bike 6x(1m z4 / 2m z1)`.
**Volume (per muscle, per week):** MV ≈ 6 · MEV 4–8 · MAV 10–20 · MRV 18–25+ (individualized).
**Effort:** working sets ~1–3 RIR (RPE 7–9); RPE = 10 − RIR.
**Proximity to failure:** hypertrophy — closer helps, diminishing near failure (0–3 RIR); strength — negligible; power — well away.
**Load–rep:** strength 1–6 @ ≥85% · hypertrophy ~5–15+ @ 60–85% · endurance ≥15 @ <60%.
**Frequency:** ≥2×/muscle/week; secondary to volume for hypertrophy.
**Rest:** strength 2–5 min · hypertrophy 1.5–3 min · endurance 30–90 s.
**Periodization:** periodize; model is a judgment call.
**Deload:** ~every 4–8 weeks or on triggers → ~MV / −10% intensity.
**e1RM:** Epley `w×(1+reps/30)`; valid ~2–10 reps; always "estimated"; never silently overwritten.
**%1RM:** `round(e1RM×%, increment)`; snapshot at send; override keeps % intent.
**Volume count:** owner's working sets only; primary 1.0, secondary 0.5; warm-ups and partner sets 0.
**Three hard rules:** %1RM snapshots at send/start · Watch execution uses `HKWorkoutSession` and durable phone reconciliation, never Watch-owned CloudKit · entitlement never gates reading, executing, or exporting data the user already has.
**Engine stance:** engine decides + cites; LLM only parses/narrates; shorthand is a grammar, not a model; human always signs off; not a medical device.

## Appendix U — The rule set (enumerated)

The operational form of the knowledge base (§13). Each rule has a **trigger**, an **action/effect**, its **citations**, and a **confidence**. Every rule that emits a prescription carries ≥1 citation; the EvidenceGate CI verifies it.

### U.1 Volume rules

- **R-VOL-1 (target).** Generating a hypertrophy block → per-muscle weekly targets in the MAV band (10–20), individualized. *pelland_2025, schoenfeld_2017, iusca_2021, rp_landmarks.* strong/moderate.
- **R-VOL-2 (strength volume).** Strength goal → lower per-muscle volume at higher intensity. *nsca_essentials, williams_2017.* strong.
- **R-VOL-3 (beginner floor).** Beginner → start nearer MEV. *iusca_2021, rp_landmarks.* moderate.
- **R-VOL-4 (progress volume).** Hypertrophy mesocycle → add sets week-to-week within MAV→MRV, then deload. *pelland_2025, rp_landmarks.* moderate.
- **R-VOL-5 (below-MEV flag).** Sustained volume < MEV → critique flag / insight. *iusca_2021, schoenfeld_2017.* strong.
- **R-VOL-6 (over-MRV flag).** Volume ≥ MRV for multiple weeks → critique flag / deload trigger. *pelland_2025, rp_landmarks.* strong/moderate.
- **R-VOL-7 (weekly-jump flag).** Large week-over-week increase → overreaching-risk flag. *rp_landmarks.* limited-moderate.
- **R-VOL-8 (owner-only accounting).** Partner and warm-up sets contribute 0 to the host's volume. *(policy; §9.11.)*

### U.2 Intensity / effort rules

- **R-INT-1 (load–rep by goal).** strength 1–6 @ ≥85%; hypertrophy ~5–15+ @ 60–85%; endurance ≥15 @ <60%; power low-rep submaximal. *nsca_essentials, iusca_2021.* strong.
- **R-INT-2 (effort band).** Working-set effort ~1–3 RIR (RPE 7–9); reserve RPE 10. *helms_2016, robinson_2024, refalo_2024.* strong.
- **R-INT-3 (RPE↔RIR).** RPE = 10 − RIR. *helms_2016.* strong.
- **R-INT-4 (RPE non-inferior).** RPE prescription valid alternative to %-based. *helms_2023.* moderate.
- **R-INT-5 (effort-too-high flag).** All working sets at RPE 10 → critique flag. *robinson_2024, refalo_2023.* strong.
- **R-INT-6 (effort-too-low insight).** Most working sets ≤ RPE 6 → insight. *robinson_2024.* moderate.

### U.3 Proximity-to-failure rules

- **R-PTF-1 (hypertrophy).** Bias to 0–3 RIR; default ~1–3. *robinson_2024, refalo_2023, refalo_2024.* strong.
- **R-PTF-2 (strength).** Proximity negligible; keep 1–3 RIR. *robinson_2024.* strong.
- **R-PTF-3 (power/speed).** Well away from failure. *nsca_essentials.* moderate-strong.

### U.4 Frequency rules

- **R-FRQ-1 (distribute).** Moderate-high volume → ≥2 sessions/week. *pelland_2025.* strong.
- **R-FRQ-2 (secondary for hypertrophy).** Don't add frequency as a hypertrophy lever when volume is equated. *pelland_2025.* strong.
- **R-FRQ-3 (strength benefit).** Allow higher frequency for strength. *pelland_2025.* moderate.
- **R-FRQ-4 (crammed-volume flag).** All of a muscle's volume in one session → flag. *pelland_2025, rp_landmarks.* moderate.

### U.5 Exercise-selection rules

- **R-SEL-1 (pattern coverage).** *nsca_essentials.* strong.
- **R-SEL-2 (balance).** Balance opposing patterns. *nsca_essentials, iusca_2021.* strong.
- **R-SEL-3 (SFR-aware accessories).** *rp_landmarks.* limited-moderate.
- **R-SEL-4 (equipment filter).** Restrict to available equipment/load modes. *nsca_essentials.* strong (operational).
- **R-SEL-5 (missing-pattern flag).** *nsca_essentials.* strong.
- **R-SEL-6 (junk-volume flag).** Redundant isolations past MAV/MRV with poor SFR → consolidate. *pelland_2025, rp_landmarks.* moderate.

### U.6 Rest / tempo rules

- **R-RST-1 (rest by goal).** strength 2–5 min; hypertrophy 1.5–3 min; endurance 30–90 s. *schoenfeld_rest_2016, nsca_essentials.* moderate-strong.
- **R-RST-2 (inadequate-rest flag).** Short rest on heavy compounds → flag. *schoenfeld_rest_2016.* moderate-strong.
- **R-RST-3 (partner rotation rest).** In a partner session, the alternating structure satisfies R-RST-1 by construction; the engine does not additionally pad rest. *schoenfeld_rest_2016.* moderate.
- **R-TMP-1 (tempo secondary).** Support tempo but treat as secondary. *nsca_essentials.* limited.

### U.7 Progression rules

- **R-PRG-1..5 (models).** Linear / double / %-based / RPE-autoregulated / volume progression as selectable models. *nsca_essentials, grgic_2017_periodization, williams_2017.* strong (overload) / limited (model superiority).
- **R-PRG-6 (e1RM suggestion).** Qualifying set (§B.5) → propose update; never silent. *epley_1985, brzycki_1993.* strong (low reps).
- **R-PRG-7 (stall flag).** No progress ≥3 weeks + rising effort → flag; propose deload/variation. *rp_landmarks.* moderate.
- **R-PRG-8 (implausible-jump flag).** Implausible week-to-week load jump → flag/confirmation. *nsca_essentials.* moderate.

### U.8 Periodization rules

- **R-PER-1 (periodize).** Default accumulation→intensification→deload. *williams_2017.* strong.
- **R-PER-2 (model = judgment call).** Offer LP/DUP/block. *grgic_2017_periodization, moesgaard_2022.* judgmentCall.
- **R-PER-3 (DUP construction).** Build undulating weeks by varying each session's goal. *grgic_2017_periodization.* moderate.

### U.9 Deload / fatigue rules

- **R-DEL-1 (schedule).** ~every 4–8 weeks / after accumulation / near MRV. *rp_landmarks, nsca_essentials.* moderate-limited.
- **R-DEL-2 (triggers).** Declining performance / rising effort at fixed load / near MRV / poor readiness / pain → propose deload, non-alarmist. *rp_landmarks.* moderate-limited.
- **R-DEL-3 (autoregulate backoff).** Sustained actual RPE > target at fixed load → propose next-session backoff. *helms_2023, robinson_2024.* moderate.

### U.10 Readiness rules

- **R-RDY-1 (soft modifier).** Permissioned poor readiness → bias toward backoff/deload as a proposal; never force; never medical. *nsca_essentials, helms_2023.* limited-moderate.

### U.11 Cardio / concurrent rules

- **R-CAR-1 (FITT + intensity).** *acsm_guidelines.* strong.
- **R-CAR-2 (intensity anchors).** moderate ≈ RPE 3–4; vigorous ≈ 5–7. *acsm_guidelines.* strong.
- **R-CON-1 (interference management).** Separate hard cardio from lower-body strength; prefer low-impact near heavy legs; flag conflicts. *acsm_guidelines, nsca_essentials.* moderate.

### U.12 Warm-up rules

- **R-WU-1 (ramp sets).** Auto-generate ascending warm-up sets for main lifts, scaled by working intensity; typed `.warmup`; excluded from volume. Applies identically when generated by a `SetScheme`. *nsca_essentials.* moderate.

### U.13 Individualization rules

- **R-IND-1..5.** Individualize defaults by experience, goal, equipment, constraints/contraindications, and logged history. *pelland_2025, robinson_2024, iusca_2021.* strong (need) / moderate (heuristics).

### U.14 Safety rules

- **R-SAF-1 (contraindication filter).** Exclude/substitute movements against recorded injuries; flag in critique. *nsca_essentials.* strong (operational).
- **R-SAF-2 (pain response).** Pain flag → surface to trainer; bias to backoff/substitution; at high severity recommend stop + consult professional; no diagnosis. *(policy.)*
- **R-SAF-3 (failure caution).** Default away from failure. *robinson_2024, refalo_2023.* strong.
- **R-SAF-4 (implausible-input guard).** Confirm before implausible e1RM/loads drive prescriptions. *(policy.)*
- **R-SAF-5 (no-silent-send).** Sending a plan to another person's device always passes through an explicit preflight; Generate never chains directly into Send, on any idiom. *(policy; §18.2, §32.9.)*

### U.15 Tier rules (policy, not evidence)

These are product guardrails enforced in code and CI, listed here so they sit alongside the other rules the system must never violate:

- **R-TIER-1.** No capability required to plan, execute, review, or export **the user's own** training is ever gated. *(§44.2.)*
- **R-TIER-2.** Partner sessions are never gated. *(§8.5, §23.)*
- **R-TIER-3.** A client's app contains no purchase UI of any kind. *(§24.2, §44.7.)*
- **R-TIER-4.** Entitlement lapse never revokes a share, disconnects a client, hides data, or blocks export. *(§44.6, §42.5.)*
- **R-TIER-5.** Every gated action resolves through `TrainerCapability`; no view reads entitlement state. *(§44.5; CI-enforced.)*

## Appendix V — Additional worked scenarios (including pushback)

### V.1 Beginner generation (heavy guardrails)

**Request.** Alex (beginner), general fitness, 3 days, dumbbells + bodyweight, no e1RM data.
**Output.** Full-body 3× (R-SEL-1 with DB variants), linear progression (R-PRG-1), volume near MEV (R-VOL-3), conservative effort (RPE 6–8; R-INT-2/R-SAF-3), **RPE-only loading** with a note to log a few sessions so e1RM can be established. Rationale emphasizes simplicity and consistency over optimization.

### V.2 Fat-loss / conditioning emphasis

**Output.** Maintain strength volume near low-MAV/high-MEV with sufficient intensity to retain muscle, add Zone-2 2–3× and one interval session, **separate hard cardio from leg strength** (R-CON-1). Honest framing that training supports but does not drive fat loss (nutrition is out of scope).

### V.3 Return from layoff

**Behaviour.** The engine does not trust a stale e1RM for heavy %1RM work; it proposes a reintroduction week at reduced volume/intensity (RPE-capped) and prompts to re-establish e1RM. Conservative up front; ramps as data returns.

### V.4 Peaking a lift

**Output.** A short intensification/realization sequence: rising intensity, falling volume, top singles/doubles at controlled RPE, a light final week, then a test. Flags that peaking is specific and temporary. *williams_2017, nsca_essentials.*

### V.5 Pushback — a request outside the evidence

**Request.** "Program 30 sets of biceps in one session, to failure, every day."
**Behaviour.** The engine **reshapes rather than complies**: flags volume far past MRV (R-VOL-6), daily high-volume-to-failure as excessive fatigue/injury risk (R-INT-5/R-PTF-1/R-SAF-3), and no recovery. It proposes ~12–16 weekly biceps sets across 2–3 sessions at 1–3 RIR with rationale. The human can override in trainer mode, but the flags stand and are recorded.

### V.6 Pushback — a contraindicated movement

**Behaviour.** Critique raises a **high-severity contraindication flag** (R-SAF-1), proposes knee-friendlier substitutes, and — if a pain flag is present — recommends consulting a professional. No diagnosis.

### V.7 Honest uncertainty in action

**Request.** "What's the single best periodization model for my hypertrophy?"
**Behaviour.** Judgment-call framing (R-PER-2): LP and DUP are roughly equivalent for hypertrophy; both work through progressive overload; here are two concrete options.

### V.8 Programming a week on a phone, standing in a gym (new in 2.0)

**Situation.** Dana has eleven minutes between clients. Maya's week is due.

1. **Roster → Maya** (2 taps; the card is at the top because it says "no plan for next week").
2. **Repeat last week** (1 tap) — the fastest legitimate start, since Maya's block is mid-mesocycle.
3. **Apply progression** (1 tap) — the engine bumps loads where Maya hit rep tops, flags one stall, and proposes a leg-press substitution for the split squat she flagged discomfort on.
4. **Two manual edits.** Dana disagrees with one load: she taps the `160` chip on Wednesday's top set, the prescription bar opens on Load, she drags the value to `165`, taps `›` to the next set, adjusts, and taps Done. **Six taps for two sets.**
5. **One new exercise.** She adds a hamstring accessory by typing `leg curl 3x12 rpe8 r90` into shorthand, sees the echo chips, and commits. **One line of text.**
6. **Critique** (1 tap) — one note: chest at the low end of MAV. She accepts it as deliberate.
7. **Send** → the preflight sheet shows the frozen weights → **Send**.

Elapsed: about three minutes. The point of §32 is that none of these steps required a compromise in what could be expressed — the same week could have been produced on the iPad, and the resulting `Plan` is identical.

### V.9 Hitting the gate as a one-client coach (new in 2.0)

**Situation.** Rae wants to send her partner a program.

1. She has been using Cladiron free for eight months: her own planning, her own generated blocks, partner sessions with the same person.
2. In a partner session she taps `⋯` → **Make a client**.
3. The app explains the distinction in one sentence and shows the Pro screen — which lists, first, everything that stays free.
4. She starts the **30-day trial**; the client relationship and share are created; she sends a week.
5. On day 27 she gets **one** reminder. She converts to annual.
6. Six months later she stops coaching, archives the client, and lets Pro lapse. Her roster history stays readable and exportable; her own training never changes; her ex-client keeps their data.

Nothing in this sequence pressures, meters, or penalizes her — which is the entire design intent of §44.

## Appendix W — Implementation notes and gotchas

### W.1 Cross-cutting gotchas

- **Never use Swift `Hasher` for persistent keys.** It reseeds per process launch. Use **SHA-256** over a canonical serialization. Enforce with a CI gate.
- **Prescription and result are separate records.** Keep `PrescribedSet` and `SetResult` distinct; results are **append-only**.
- **%1RM must snapshot at send/start.** Store the resolved `calculatedWeight` at that moment; never recompute a live plan's loads.
- **Do not move CloudKit onto Watch.** Preserve the shipped phone-only CloudKit topology. Watch workout events use stable IDs and durable WatchConnectivity transfer; phone application is idempotent and then participates in ordinary private/shared CloudKit sync. Tests must cover unreachable phone, duplicate delivery, out-of-order delivery, relaunch, cancel/discard, and exactly-once cardio completion.
- **Enums with associated values** (`LoadPrescription`, `CardioIntensity`, `RepTarget`, `PlanProvenance`, `PerformerRef`, `SchemeKind`) need explicit `Codable` and a stable persistence mapping chosen once.
- **Only `exerciseKey` crosses the wire.**
- **Locale vs storage.** Store weekday/week structure canonically (Monday-first) and localize at display; store units on every load/result.
- **Capability, not entitlement, in views.** Never read `ProEntitlement` from a view; ask for a `TrainerCapability`. CI-enforced.

### W.2 CadenceCore / model (WS-CORE-MODEL, WS-STORE)

- Put the **domain invariants** in the package, not the apps. A prescription must be unconstructable without citations.
- **CloudKit compatibility is a modelling constraint, not a later chore.** Every mirrored property optional or defaulted; optional relationships with inverses; no `@Attribute(.unique)`; stable `UUID` + `updatedAt` + `originDevice` on every entity. Retrofitting this after the model exists is a migration; getting it right on day one is free.
- **Append-only is yours to enforce, not the framework's.** Mirroring is last-writer-wins per property, so a result record must be *inserted and never mutated* by domain rule, with a test that proves a remote change cannot overwrite a logged set.
- Keep schema evolution **additive only** (optional/defaulted); add a test for the live-coach → planner path that asserts history, e1RM, and progress survive.
- Volume accounting must exclude warm-up sets **and partner sets**, and apply the 1.0/0.5 convention. Get this right early.
- `SetScheme` expansion must be **pure and total** (I.8) so it is trivially testable and so undo is exact.

### W.3 Sync and sharing (WS-SYNC-PRIVATE, WS-SHARE)

- **Mirroring for your own devices; an explicit layer for other people's.** The private database is `NSPersistentCloudKitContainer` mirroring and needs no hand-written sync. Trainer↔client sharing is the opposite: CadenceCore owns the zone, the `CKShare`, change tokens, and the fetch loop. Do not blur the two.
- Conflict policy is field-appropriate: append-only for results, last-writer-wins (trainer authoritative) for plan edits, merge for e1RM.
- **Test the trainer's own multi-device case**, which is new in 2.0 and easy to overlook: the same draft open on iPad and iPhone must converge with a visible notice and no lost edits.
- The **share invite/accept** flow is the riskiest UX. Test acceptance on a second real Apple ID.
- **Suppressing mirroring during a Watch runtime session takes explicit work.** Automatic mirroring will happily push mid-session unless you stop it; this is the one place where "it syncs by itself" is a liability rather than a convenience.
- **A CloudKit schema deploy to Production is a release gate.** The private-database schema must be deployed in the CloudKit Dashboard before any TestFlight or App Store build will sync — same as the shipped app requires today.

### W.4 Watch execution (WS-WATCH-EXEC)

- Persist each logged set **immediately**; make the session resumable from the last logged set.
- Keep the Watch on a **lightweight execution subset**.
- RPE entry is optional and Crown-driven; never block completion on it.
- **Partner rotation** changes the advance semantics (performer within set index, not set index) — model it explicitly rather than as a UI trick, or resume-after-kill will restore the wrong lifter.

### W.5 The engine (WS-KNOWLEDGE-BASE, WS-ENGINE-*)

- Build the **citation registry and EvidenceGate first**; CI gates green before generation logic lands.
- Keep generation **deterministic**.
- Attach a **`RationaleDecision`** at the point each material decision is made, not afterwards.
- Critique **never mutates**; progress/substitute/deload return **proposals**.
- e1RM suggestions fire only on qualifying **owner** sets and never auto-apply.
- Individualize from history; fall back to conservative defaults with low-confidence flags.

### W.6 Compact authoring (WS-SETSTACK, WS-SCHEMES, WS-SHORTHAND) — the highest-risk UI in the product

- **Build the prescription bar as a focus system, not a sheet.** The bar must never take a modal presentation: the set stack has to stay visible and scroll to keep the focused row above the bar. If it becomes a sheet, set-to-set stepping loses its point and the whole model collapses back to "tap a set, open a modal."
- **Chip hit targets are the whole ballgame.** Each chip ≥44 pt with ≥8 pt separation, and the row's background is *not* a tap target that competes with the chips (tapping between chips should focus the row, not the last chip).
- **Never truncate a number.** Compress the label, wrap the row, or drop to a stacked layout — but `145 lb` must never become `14…`.
- **Scheme apply and shorthand commit are single undoable actions.** Multi-step undo here is a bug, not a nuance: a phone user who mis-taps must recover with one Undo.
- **Write the shorthand grammar as a real lexer/parser with a fixture corpus**, not regexes bolted together. It will be extended (supersets, tempo) and it must stay total: every input yields a parsed item, an ambiguity, or a marked error — never a crash and never silent data loss.
- **The echo is not decoration.** It is the trust mechanism. Build it before the commit path.
- **Test at accessibility text sizes from day one.** A chip row that works at default and breaks at XXL is a failure, and it is much cheaper to design for than to retrofit.
- **VoiceOver adjustable chips** need explicit `accessibilityAdjustableAction` handling; do not rely on the default row semantics.

### W.7 iPad, commands, and the native Mac (WS-SETGRID, WS-COMMANDS, WS-DRAGDROP, WS-MAC-NATIVE, WS-UNIVERSAL-PURCHASE)

- **Declare commands once** (§33.1). Do not hand-write a Mac menu and an iPad menu; they will drift within a month.
- **Keyboard traversal of the grid is the trainer's core loop.** Budget real time for focus management; SwiftUI focus in a dense grid is fiddly and is where the schedule usually slips.
- **Copy-with-recalc must recompute %-based loads from the destination client's e1RM** (absolute loads copy as-is). Test criterion 18 on both the drag path and the Copy-to-client path — it is easy to implement one and forget the other.
- **Drop badges** must describe the result before release; an unlabelled drag onto a roster row is indistinguishable from a destructive move.
- **Put product code in `CadenceUI`, shell code in the Mac target — and police the boundary.** The native Mac target is affordable only while it stays a shell. The first `#if os(macOS)` inside a `CadenceUI` view is the warning sign; the CI check exists because code review alone will not catch the tenth one.
- **Verify every menu item actually fires** on the Mac, and check **window restoration** early — restoration bugs surface late and are miserable to retrofit.
- **Test the narrow-window path** on iPad (Stage Manager, split view) — a window below the split-view threshold must become the compact arrangement, not a squeezed grid. The Mac target instead declares a **minimum window width**, so it never enters that path.
- **Do not add a Mac-only feature.** The moment one exists, the "one product" promise is broken and the next Mac request becomes a fork. This is the rule the whole v2.1 Mac decision rests on (§38.3).
- **Universal Purchase is configuration, and it is irreversible.** Shared bundle ID, one App Store Connect record with both platforms, shared StoreKit product IDs — verified with a real cross-platform purchase before the first Mac submission. Records that start separate can never be merged (L.6). Put this on the release checklist, not in someone's memory.

### W.8 Entitlement (WS-PRO-ENTITLEMENT)

- **One resolver, one capability API, zero inline checks.** Add the CI gate before the first gated surface exists.
- **Trial starts at the first gated action**, not at install; persist that timestamp locally *and* rely on StoreKit's own introductory-offer eligibility as the source of truth for billing.
- **The lapse path is the one users will judge you on.** Test it explicitly: lapse mid-block, confirm the client's plan still works, results still arrive, export still works, and no share is revoked.
- **Delete the legacy `CoachGate`.** The gate is the capability resolver; two gates means one of them is wrong.
- **Never notify to upsell.** Exactly one trial-ending reminder exists in the entire product.

### W.9 Export and LLM (WS-EXPORT, WS-LLM)

- Read only the local store; write via a Swift xlsx writer; no server round-trip. Historical data as **values**, summary rollups as **formulas**; assert zero formula errors.
- On iPhone/iPad deliver via the share sheet; on the Mac via `NSSavePanel` with a remembered directory. Large rosters export on a background task with cancellable progress.
- The LLM is **strictly an interface**; assert the engine's output is identical whether the request arrived via taps, shorthand, or text. Gate behind availability with the structured-prompt and shorthand fallbacks.

### W.10 Testing priorities (highest-leverage first)

1. Evidence-gate CI (citation-resolution + rule-coverage + alias-uniqueness).
2. Entitlement CI + the lapse/grace behaviour (protects users and the product's integrity).
3. Snapshot-at-send and append-only.
4. No-sync-during-runtime-session.
5. **Compact-authoring parity** (criterion 12) — this is what makes the revision true rather than aspirational.
6. Engine determinism + the Appendix H golden fixtures.
7. Shorthand corpus and scheme expansion.
8. Two-device sync/offline/flush, including the trainer's own two devices.
9. Command coverage and the native Mac test plan (§38.6).
10. Export recalc (zero formula errors).

## Appendix X — Reading paths and document maintenance

### X.1 Reading paths by role

- **Implementer / coding tool.** Start with the work-stream's entry in §48, follow its cross-references, read the matching appendix (K for screens, I/U for engine logic, B for formulas, M for state machines, Y for commands, W for gotchas), and check §49/§50. **Always read Appendix W before starting a work-stream.**
- **Understanding what changed from v1.0.** Read `REVISION-NOTES.md`, then §2.3, §32, §38, and §44.
- **Understanding the expert system.** Part III end to end, then Appendix A, H, V, I, U.
- **Understanding compact authoring (the revision's core UI bet).** §7.5, §32 in full, K.8, O.4/O.5, W.6, and criterion 12 in §49.
- **Understanding the trainer surface.** Part V (§29–38), Appendix Y, K.1–K.5, K.10–K.11.
- **Understanding the tiering.** §8.5, §23, §44 in full, M.3, P.8, U.15, K.12, V.9.
- **Architecture reviewer.** Part II (§7–10), §42, Appendix L, M, N, Q.
- **Business stakeholder.** §1–4, §44, §43, Appendix R, Q.3, §51.

### X.2 Document map

- **Vision, scope, principles, personas** → Part I (§1–6).
- **Architecture, idioms, planning model, data model, persistence/sync** → Part II (§7–10); types in Appendix E.
- **The expert system** → Part III (§11–18); citations App A; formulas App B; algorithms App I; rules App U; examples App H & V.
- **The athlete app** → Part IV (§19–28); screens K.6–K.8.
- **The trainer surface** → Part V (§29–38); screens K.1–K.5, K.9–K.12; commands App Y.
- **Watch** → Part VI (§39–41); screens K.13.
- **Cross-cutting** (sharing, privacy, monetization, units/accessibility, errors) → Part VII (§42–46); state machines App M; data flows App N.
- **Delivery** → Part VIII (§47–51).
- **Design/visual** → Appendix O; **library/taxonomy** → C/D; **pre-made plans** → J; **copy** → P; **decisions** → Q; **positioning** → R; **requirements coverage** → S; **cheat sheet** → T; **gotchas** → W; **commands** → Y.

### X.3 Keeping the specification current

- **This document governs** where it conflicts with v1.0 or `MVP_DESIGN.md`.
- **The knowledge base is versioned** (§12.4). When new evidence lands, update §13, the Appendix A registry (with the verified DOI), the affected Appendix U rules, and bump the KB version.
- **Decisions belong in Appendix Q.** Update a row rather than letting the product drift.
- **The tier boundary belongs in §44 and U.15.** Any change to what is free must update both, plus P.8 and the acceptance criteria — the tiering is a product promise, not a configuration value.
- **Keep the companion artifacts in sync**: the export sample with §37/W.9; the mockups with Appendices K and O; the persistence analysis with §10.

### X.4 One-paragraph restatement

Cladiron is an Apple-native, evidence-based strength-and-conditioning platform that ships as **one product across four native surfaces** — iPhone, iPad, a native Mac app, and Apple Watch — sold under a **single App Store record with Universal Purchase**, and sharing one brain (`CadenceCore`) and one view layer (`CadenceUI`). Athletes plan their week in a **Plan tab** — by hand, from pre-made plans, with a partner, or with the **coach expert system** — with Home showing plan and canonical per-muscle progress and execution through the proven iPhone/Watch runtime; **all of that is free forever**. Trainers switch the same app into **Trainer mode** and get a roster and a full per-set planner: a three-column, keyboard-first workbench on iPad and on the native Mac app, and **a complete authoring system on iPhone**, built from set schemes, deterministic shorthand, chip rows, and a prescription bar, which can produce the identical plan standing on a gym floor. Plans materialize through the existing workout prescription adapter rather than replacing field-tested set entry, partner rotation, cardio, HealthKit, or WatchConnectivity. Clients can be added from any trainer surface. Connected Cladiron clients exchange plans and results over serverless CloudKit sharing; clients on any other platform receive polished plan packets through Mail or the system Share sheet and report results for trainer entry. **Coaching anyone else — even one person — is Cladiron Pro**, the product's only in-app purchase: one flat tier, covering every device through Universal Purchase, with a 30-day trial, and a lapse that never disconnects a client or hides a byte of data. The differentiator remains the **evidence-gated expert system**: a deterministic, cited engine that generates, critiques, progresses, substitutes, autoregulates, and explains — with a natural-language layer that only translates, never prescribes.

## Appendix Y — Keyboard and menu command reference

The single source of truth for the command set (§33). Every entry has a menu location; entries with a key equivalent are keyboard-reachable on iPad (with a hardware keyboard), iPhone (with a hardware keyboard), and Mac. **Every entry also has a touch path** — a toolbar button, a context-menu item, or a `⋯` menu entry — because iPad-without-keyboard and iPhone are first-class.

### Y.1 Application and navigation

| Command | Key | Menu | Touch path |
|---|---|---|---|
| Settings | `⌘,` | App | Profile tab |
| Home / Plan / Progress / Clients | `⌘1`–`⌘4` | View | Tab bar / sidebar |
| Toggle sidebar | `⌘\` | View | Sidebar button |
| Toggle inspector | `⌥⌘I` | View | Inspector button / sheet grabber |
| Find | `⌘F` | Edit | Search field |
| Quick add / command palette | `⌘K` | File | `⌨︎ Shorthand` / `⋯` → Commands |
| Next / previous client | `⌥⌘→` / `⌥⌘←` | Client | Client chip switcher / swipe week header |
| New window | `⌘N` | File | (iPad multitasking / Mac only) |
| Keyboard shortcuts help | `⌘/` | Help | Help → Keyboard Shortcuts |

### Y.2 Week and session

| Command | Key | Menu | Touch path |
|---|---|---|---|
| Jump to day 1–7 | `⌘⌥1`–`⌘⌥7` | View | Tap the day |
| New session | `⌘⇧N` | File | `+` on a day |
| Duplicate session | `⌘⇧D` | Edit | Session `⋯` |
| Move session to day… | — | Plan | Session `⋯` → Move to day… |
| Repeat session on days… | — | Plan | Session `⋯` |
| Repeat week | — | Plan | Week `⋯` |
| Insert deload week | — | Plan | Week `⋯` |
| Save as template | — | Plan | Week/session `⋯` |

### Y.3 Items and the per-set grid / set stack

| Command | Key | Menu | Touch path |
|---|---|---|---|
| Add strength / cardio / mobility / instruction | `⌘⌥S` / `⌘⌥C` / `⌘⌥M` / `⌘⌥T` | File | `+` row in the session |
| Move cell focus | Arrow keys | — | Tap a chip |
| Next / previous field | `Tab` / `⇧Tab` | — | Field picker in the prescription bar |
| Commit and go to next set | `Return` | — | `›` in the prescription bar |
| Next / previous set | `⌃↓` / `⌃↑` | — | `‹` / `›` in the prescription bar |
| Duplicate set | `⌘D` | Edit | Swipe leading / row `⋯` |
| Delete set | `Delete` | Edit | Swipe trailing / row `⋯` |
| Move set up / down | `⌥↑` / `⌥↓` | Edit | Drag handle |
| Toggle warm-up | `Space` | Edit | Type chip → Warm |
| Multi-select | `⇧`-click / `⌘`-click | Edit | Long-press → selection mode |
| Select all working sets | `⌘⇧A` | Edit | Selection mode → All working |
| Apply scheme… | `⌘⇧P` | Plan | `⚡︎ Scheme` |
| Convert to %1RM / absolute | `⌘⇧%` / `⌘⇧W` | Edit | Row `⋯` / bulk bar |
| Nudge % up / down | `⌘]` / `⌘[` | Edit | Load control steppers |
| Set all rest… | `⌘R` | Edit | Bulk apply → Rest |
| Substitute exercise… | `⌘⇧X` | Plan | Item `⋯` → Substitute… |
| Copy exercise to client… | `⌘⇧K` | Client | Item `⋯` → Copy to client… (or drag to roster) |

### Y.4 Engine and delivery

| Command | Key | Menu | Touch path |
|---|---|---|---|
| Generate with Coach… | `⌘⇧G` | Plan | Plan with coach button |
| Critique plan | `⌘⇧C` | Plan | Critique button |
| Apply progression | `⌘⇧R` | Plan | Week `⋯` → Apply progression |
| Preview as client | `⌘⇧V` | Plan | Preview button |
| Send plan… | `⌘⇧S` | Plan | Send button → preflight |
| Share external plan… | `⌘⇧E` | Plan | Share next plan → preflight |
| Record external result… | — | Client | External Overview → Record result |
| Why this plan (rationale) | `⌘⇧Y` | View | "Why this plan" affordance |

### Y.5 Data

| Command | Key | Menu | Touch path |
|---|---|---|---|
| Export to Excel… | `⌘E` | File | Export row in Profile / toolbar |
| Import template… | — | File | Templates → Import |
| Print plan… | `⌘P` | File | (Mac; share sheet → Print elsewhere) |
| Undo / Redo | `⌘Z` / `⇧⌘Z` | Edit | Undo button in the toolbar |

### Y.6 Rules for adding a command

1. Declare it once in `CadenceCommands`; never add a platform-specific duplicate.
2. Give it a **touch path** in the same change, or it does not ship.
3. If it has a key equivalent, add it to this table and to the command-coverage test (§50).
4. Avoid bindings that collide with common non-US keyboard layouts; re-check per added locale (§45.2).
5. Destructive commands require confirmation or are undoable — preferably undoable.

---

## Appendix Z — External-client plan delivery and manual reporting

This appendix is implementable detail. It is normative where connected-client
assumptions elsewhere conflict with external delivery.

### Z.1 Product rules

1. External delivery is a presentation/transport choice over the same immutable
   sent plan; it is not a second planning model.
2. An active external client counts for Pro exactly like a connected client.
3. Cladiron prepares content locally. A system-owned composer/share service is
   the only sender; the trainer always chooses/approves the recipient and content.
4. No Contacts access, inbox access, SMTP/API integration, tracking pixel,
   analytics, hosted plan, web form, or developer-operated delivery service.
5. “Prepared” and “shared” are local workflow facts. Never say delivered, opened,
   or received unless the trainer explicitly marks the client's report received.
6. PDF is the canonical portable visual. Plain text is the universal fallback;
   HTML email is progressive enhancement.

### Z.2 Domain model

```swift
struct ExternalPlanPacket: Codable, Identifiable, Equatable {
    let id: UUID
    let schemaVersion: Int              // 1 at launch
    let packetVersion: Int              // monotonic per client
    let clientRelationshipID: UUID
    let planID: UUID
    let planRevision: Int
    let generatedAt: Date
    let generatedBy: TrainerIdentitySnapshot
    let client: ExternalClientSnapshot
    let position: ClientPositionSnapshot
    let upcoming: [ExternalWorkoutSnapshot] // 1...3, chronological
    let trainerNote: String?
    let replyRequest: ExternalReplyRequest
    let inclusions: ExternalPacketInclusions
}

struct ExternalClientSnapshot: Codable, Equatable {
    let displayName: String
    let unitPreference: WeightUnit
    let equipmentSummary: String?
}
struct ClientPositionSnapshot: Codable, Equatable {
    let programName: String?
    let phaseName: String?
    let weekIndex: Int?
    let weekCount: Int?
    let lastReportedTitle: String?
    let lastReportedAt: Date?
    let plannedThisWeek: Int
    let reportedThisWeek: Int
}
struct ExternalWorkoutSnapshot: Codable, Identifiable, Equatable {
    let id: UUID                         // source Session ID
    let title: String
    let scheduledDate: Date?
    let estimatedMinutes: Int?
    let items: [ExternalItemSnapshot]    // strength/cardio/mobility/instruction
}
struct ExternalReplyRequest: Codable, Equatable {
    var askCompletedDate: Bool = true
    var askActuals: Bool = true
    var askSessionEffort: Bool = true
    var askPainOrSubstitutions: Bool = true
    var askNotes: Bool = true
}
struct ExternalPacketInclusions: Codable, Equatable {
    var includeTrainerNote = true
    var includeReadiness = false         // sensitive, separately confirmed
    var includeInjuryNotes = false       // sensitive, separately confirmed
}
enum ResultProvenance: Codable, Equatable {
    case recordedInCladiron(deviceID: String)
    case reportedExternal(channel: ExternalShareChannel,
                          recordedByTrainerID: UUID,
                          packetID: UUID?)
}
```

Every snapshot field is a value: renderers never query live SwiftData. Packet
creation resolves %1RM to concrete client-unit loads using the normal send
snapshot rule. A packet is immutable; editing/re-sharing creates the next
`packetVersion`. Store packet metadata and encoded snapshot in the trainer's
private database so manual result entry always targets what was actually shared.

### Z.3 Packet builder

`ExternalPlanPacketBuilder.build(client:plan:now:calendar:inclusions:)` is pure
and deterministic. It must:

1. require `deliveryMode == .external`, `authorForClient`, and a valid sent/draft
   plan revision; email is not required;
2. select the next 1–3 incomplete sessions by scheduled date then stable ID;
3. derive position from append-only results as of `generatedAt`;
4. snapshot trainer display name, client units/equipment, all prescriptions,
   substitutions and instructions; never include internal trainer notes;
5. include readiness/injury only after a separate preflight choice and mark the
   packet metadata accordingly;
6. normalize line endings, clamp free-text display lengths (name 120, note 2,000,
   instruction 4,000 Unicode scalars), and retain full safe text in PDF overflow;
7. increment packet version transactionally only after the snapshot persists;
8. use locale/time zone captured from the trainer for dates, but client units.

No workout is available: disable Continue with “Add or generate an upcoming
workout first.” Missing load/e1RM: render the RPE/RIR/bodyweight prescription,
never invent zero. An unscheduled session says “Upcoming,” not a fake date.

### Z.4 Preflight and privacy

Preflight always shows client, email if stored, position, selected workouts,
packet version, trainer note, reply fields, and attachment estimate. Readiness
and injury switches are off each time; enabling either presents one concise
confirmation naming the recipient and field. Preview is available before a
system composer. The trainer may deselect a workout but must leave at least one.

The app never loads Contacts. The optional email is typed/pasted and validated
only enough to reject empty/control-character/newline header injection; the
system composer remains authoritative. Do not place health/injury content in the
email subject or attachment filename.

### Z.5 Three renderers, one content contract

Declare protocol-level outputs in `CadenceCore` or a platform-neutral package:

```swift
struct ExternalPacketRenderBundle {
    let subject: String
    let htmlBody: String
    let plainTextBody: String
    let pdfData: Data
    let pdfFilename: String
}
protocol ExternalPlanPacketRendering {
    func render(_ packet: ExternalPlanPacket,
                locale: Locale, timeZone: TimeZone) throws
      -> ExternalPacketRenderBundle
}
```

All renderers share `ExternalPacketPresentation`, a linear token tree (heading,
metadata, note, workout, item, set table, reply field, footer). HTML/PDF/text
walk that tree; no renderer independently derives content.

**Order:** brand/trainer → greeting → position → trainer note → workouts in
chronological order → structured reply request → privacy/provenance footer.
Strength includes set type, reps/range, concrete load plus original % intent,
RPE/RIR, rest, side/tempo when present. Cardio includes modality, duration/
distance/intensity/intervals. Mobility and instructions retain ordered text.

**HTML:** UTF-8 document fragment acceptable to Mail; semantic headings/tables;
inline CSS only; 640px max width; one-column media fallback; system font stack;
all user strings escaped; links only to static Cladiron help/privacy domains if
explicitly approved. No remote images/fonts/CSS, `data:` images, scripts, forms,
iframes, pixels, hidden elements, or CSS URLs. Brand is text/CSS.

**PDF:** generated locally with Core Graphics/PDFKit or a deterministic renderer;
Letter and A4 safe within 18mm margins; selectable text; table headers repeat;
set rows never split; keep workout heading with first item; footer has client,
packet vN, generated timestamp, page N/M. If content cannot fit atomically, move
it to the next page rather than shrink below 9pt. Filename is sanitized ASCII:
`<Client>-Plan-YYYY-MM-DD-v<N>.pdf`, maximum 96 characters, never email/health.

**Plain text:** UTF-8, no Markdown dependency, concise enough for Messages;
bullets and line breaks; never omit prescription values merely to shorten it.
If over 12,000 characters, use position + first upcoming workout + “See attached
PDF for remaining workouts.” Copy Summary uses this exact string.

Golden fixtures compare the presentation token sequence and normalized extracted
PDF text, not PDF bytes (metadata/compression may vary).

### Z.6 Platform adapters

Adapters receive a completed render bundle; they never build content.

**iOS/iPadOS email:** wrap `MFMailComposeViewController`. Check
`canSendMail()` before showing. Set optional To, subject, HTML body with
`isHTML: true`, and PDF via `addAttachmentData(..., "application/pdf", ...)`
before presentation. Use a SwiftUI `UIViewControllerRepresentable` coordinator,
retain the delegate until dismissal, and map `.sent/.saved/.cancelled/.failed`.
Only `.sent` may automatically set `lastSharedAt` and `.awaitingReply`; saved and
cancelled do not. Failure shows a retryable error. Never modify system UI.

**iOS/iPadOS share:** `UIActivityViewController` with the temporary PDF URL and
an `UIActivityItemSource` that returns `plainTextBody` for message/mail/social
activities and a short neutral preview title. Set subject through the supported
link-metadata/activity subject path. Anchor the iPad popover to the initiating
button. A completed activity may record channel and user-confirmed `lastSharedAt`;
cancel does not. Because an activity completion is not delivery, UI says Shared.

**macOS:** `NSSharingService(.composeEmail)` when available, with recipients,
subject, an attributed/plain body supported by the service, and the PDF file;
the PDF remains canonical because rich HTML fidelity is not guaranteed. General
Share uses `NSSharingServicePicker`; Save uses `NSSavePanel`; Print uses the PDF.
If Mail service is absent, disable it and retain Share/Save/Print/Copy.

**Temporary files:** create inside a per-operation temporary directory, apply
file protection where supported, exclude from backup, and remove on composer/
share completion or next launch cleanup. Never write packets to Documents unless
the trainer chooses Save to Files/Save Panel. Rendering requires no network.

### Z.7 State and failure model

```swift
enum ExternalShareState: Equatable {
  case editing, rendering, ready(ExternalPacketRenderBundleRef)
  case presenting(channel: ExternalShareChannel)
  case completed(channel: ExternalShareChannel, at: Date)
  case cancelled, failed(ExternalShareError)
}
```

Rendering is cancellable and performed off the main actor; presentation and
state mutation are `@MainActor`. Disable duplicate Continue/Share taps. Errors:
no upcoming workout, invalid email, render failed, Mail unavailable, service
unavailable, temp write failed, presentation failed. Each message states what
was not sent and offers an in-scope fallback. Never mark shared on ambiguity.

### Z.8 Manual report entry

From an external Overview, **Record result** selects an outstanding workout from
the last packet or another sent plan. Required: completed date and at least one
completion/actual. Source channel defaults to preferred/last shared and is
editable. Two paths:

- **Completed exactly as written:** confirmation then copy each prescription to
  new result values where representable; RPE/pain/note remain separately optional.
- **Enter actuals and changes:** prefilled set stack/grid with Rx read-only and
  Actual editable; supports missed/partial sets, changed load/reps, substitution,
  unplanned item, cardio/mobility, duration, session effort, pain, and client note.

Save calls one transactional domain command with an idempotency UUID. It inserts
append-only results carrying `.reportedExternal`, updates report status to
recorded, and feeds normal review/history/engine derivation. It never changes
the sent plan/packet and never implies the client used Cladiron. Editing a manual
entry creates an append-only correction/supersession record under existing
result-correction policy, not an in-place mutation.

### Z.9 Accessibility, localization, and tests

- UI: VoiceOver reads Rx before Actual; status has text, not color alone;
  Dynamic Type reflows preflight; all composer choices are labelled controls.
- Packet: semantic HTML, meaningful table headers, logical linear order,
  contrast ≥4.5:1, selectable PDF text, no information conveyed only by color.
- Localization: renderer strings use string catalogs; packet locale/date/unit
  formatting is injected; snapshots store values, never formatted strings.
- Required tests are criteria 35–39 and §50. Add a 100-workout stress fixture,
  emoji/RTL/HTML-injection names and notes, long-word wrapping, nil dates/loads,
  all item kinds, sensitive-field defaults, adapter cancellation, and launch-time
  temporary-file cleanup.

### Z.10 Deliberate non-goals

No hosted/browser plan link, web portal, online form, automatic reply parsing,
mailbox access, message delivery/open tracking, bulk email, reminders sent by
Cladiron, contact import, or non-Apple trainer app. These require a separate
privacy/backend decision and may not be inferred from this work stream.

---

## Appendix AA — Shipped training-loop preservation contract

This appendix is normative. It records the behavior earned through DB++ adoption
and repeated gym/device field testing. Planning is an upstream producer of
prescriptions; it is not authorization to rewrite execution. A Luna-class coder
must begin each planning slice by mapping these named seams in the current tree
and adding regression fixtures before changing code.

### AA.1 Source-of-truth seams

| Concern | Preserve this shipped seam | Planning may do |
|---|---|---|
| Exercise catalog/intelligence | `TrainingEngineBridge` is the only Swift import of `FreeExerciseDBPlusPlus`; `ImportedExerciseLibrary` maps stable records | Request/generate by stable exercise key through bridge-owned values |
| Muscle analysis | `MuscleGroup`, `VolumeCredit`, DB++ roles/eligibility | Display/project the same credits over planned and completed sets |
| Plan materialization | `EditablePlan` plus `WorkoutSession.plannedExercisePrescriptions`; legacy ladder/load fallback | Populate one prescription per exercise and set, then call the shared materializer |
| Live strength presentation | `SessionRenderModel`, `SessionViewModel`, `ExerciseCardView` | Supply prescription context; never create planner-specific runtime cards |
| Set entry/defaults | full-screen `InlineSetEditorView`, `PerformerSetPlanner`, performer history/default resolver | Seed a new performer's last fallback from the prescribed set |
| Partner order | `SetAlternation` and performer-aware `PendingSetDisplay` | Supply roster and performer overrides while retaining stable alternation |
| Watch strength | `WatchStrengthFlowModel` and existing Watch views/payload appliers | Add backward-compatible prescription fields to the input payload |
| Watch cardio | `WatchWorkoutManager`, `WatchCardioModels`, `WatchCardioCompletion` and phone repository merge | Start a planned cardio kind/target; preserve lifecycle and completion ID |
| Transport | durable WatchConnectivity payloads plus idempotent phone appliers | Add optional versioned keys; never require reachability |
| Persistence/export | existing SwiftData entities, repository commands, JSON round trip | Add optional/defaulted fields only; preserve stable UUIDs and old decoding |

Do not rename these seams for architectural neatness during the MVP. If current
source has evolved, locate the direct successor by tests and behavior, document
the mapping in the work-stream PR, and preserve the contract.

### AA.2 Plan-to-runtime adapter

The only new boundary is a pure, tested adapter:

```swift
struct RuntimePrescriptionAdapter {
    func materialize(planSession: PlanSessionSnapshot,
                     athlete: AthleteExecutionSnapshot,
                     existingSessionID: UUID?) throws -> WorkoutSessionDraft
}
```

It resolves percentage loads once using the athlete's e1RM and rounding profile,
stores canonical kilograms plus the original intent, writes each exercise's full
per-set prescription to `plannedExercisePrescriptions`, and retains plan/session/
item/set source IDs for review. It does not create set results. Starting twice
with the same `existingSessionID` returns/resumes the same live workout. Manual or
quick-start workouts call the existing path and need no synthetic `Plan`.

Compatibility rules:

1. New readers prefer `plannedExercisePrescriptions`; absent data synthesizes the
   current legacy `plannedRepLadder`/`prescribedLoadKg` view.
2. New writers keep legacy summary fields populated until all supported Watch/app
   versions understand the richer payload.
3. Exercise swap retains prescribed set count/rep intent, changes the exercise
   identity, then re-resolves each performer's exercise-specific history.
4. Results remain the existing append-only set/cardio records. Prescription IDs
   are optional foreign references, never replacement result entities.
5. Export/import includes new optional prescription/source fields and round-trips
   old fixtures without rewriting their IDs, dates, units, or performer.

### AA.3 iPhone strength-entry behavior that must not regress

- A workout opens with every exercise card collapsed. The compact line shows
  completion/planned count, rep pattern/range, load/BW, and partner names.
- Expanding reveals prescription, performer-specific “Last time” and PR context,
  completed sets, performer-aware pending rows, and actions. No dense planner
  chip row replaces this runtime card.
- Tapping a pending row opens the shipped full-screen editor for that explicit
  performer. It always shows exercise/set, “Who did this set?”, that performer's
  prior history (or an honest no-history line), large weight and rep controls,
  RPE/RIR, warm-up state, and a single Save Set action.
- Default precedence remains: same performer/current session/same exercise →
  same performer/prior same exercise → same performer's general rep pattern →
  prescribed exercise/set → ordinary fallback. Owner history never seeds a
  partner. Switching performer re-targets defaults immediately for new entries;
  editing an existing result reattributes without silently changing its values.
- Pending work is counted per performer. Logging three owner sets cannot consume
  a partner's three prescribed sets. Stable round-robin alternation follows roster
  order across exercises and resumes correctly after manual out-of-order choice.
- Exercise search stays incremental and alias-aware; it does not filter the full
  DB++ catalog on every keystroke. Cancel leaves the workout unchanged. Similar-
  exercise swap uses DB++ movement/muscle/equipment ranking and preserves logged
  performer attribution.
- Finish/save, cancel/discard, resume, warm-up exclusion, cooldown, summary,
  history navigation/edit/delete, PR calculation, and unplanned Add Set remain
  available whether or not a workout originated in Plan.

### AA.4 Muscle-level contract

`MuscleGroup`'s 20 DB++ raw values are canonical. Persist and calculate at this
level. `BodyRegion` may group picker sections and search terms only; it must never
replace a muscle key in plans, facts, targets, insights, progress, or exports.

- A volume-eligible owner working set gives every DB++ direct muscle `1.0`, every
  indirect muscle not already direct `0.5`, and stabilizers `0.0`.
- Warm-ups, non-volume-eligible movements, and partner sets contribute `0.0` to
  the owner's weekly totals.
- Custom/legacy exercises retain the shipped primary/secondary fallback.
- Home/Progress show the 13 default-tracked muscles in deterministic canonical
  order and surface any other muscle after the user trains or explicitly tracks
  it. Never collapse lats/mid-back/lower-back into “Back” for analysis.
- Planned volume and completed volume use the same `VolumeCredit` function and
  identify which is shown. Every science claim keeps its resolved citation.

### AA.5 Watch strength lifecycle

Preserve the shipped state machine and UI semantics:

```text
idle → active/session hub ↔ add exercise ↔ set keypad ↔ rest
                         ↘ partners
active → cooldown → summary → done
active → pause/back → resume
active → cancel(confirm) → discard
```

The Watch owns `HKWorkoutSession`/live builder and its local SwiftData write. A
session is created lazily enough that backing out before meaningful work leaves
no orphan. The session hub provides exercise progress, Partners, Add Exercise,
Finish & Save, and guarded Cancel. The keypad preserves unit increments, typed
weight, reps, warm-up, performer chip/rotation, history-derived defaults, and
haptics/audio. Rest previews the next lifter/set and remains skippable. Cooldown
is optional and stored. Summary and HealthKit save reflect the same workout.

Plan payload evolution is additive and versioned. An older Watch can execute the
legacy exercise list/rep ladder/load summary; a newer Watch uses per-exercise set
prescriptions. Unknown fields are ignored. Never require the phone to be
reachable to start, log, finish, cancel, or view the summary.

### AA.6 Cardio preservation

Planning supplies modality and optional duration/interval/zone/RPE target to the
existing cardio configuration; it does not introduce a second cardio runner.
Preserve Run, Walk, indoor/outdoor Cycle, Swim, HIIT, Boxing, Rowing, and Other;
warm-up/work/rest/cooldown; pause/resume/end; live elapsed time; sensor-conditional
HR/zone and distance; large glanceable metrics; summary average/max HR where
samples exist; HealthKit save; and phone history/delete behavior.

Watch cardio completion carries one stable workout UUID and is persisted in an
outbox until acknowledged/reconciled. The phone's merge is idempotent across
interactive message, user-info delivery, retry, relaunch, and HealthKit ingest.
Missing HR/GPS is shown as unavailable, never fabricated as zero. Stopping any
cardio path tears down its `HKWorkoutSession`; `.alreadyActive` recovery remains
stop-then-retry, not a second concurrent workout.

### AA.7 Required regression fixtures and device gates

Before planner UI work, capture passing fixtures for:

1. two exercises with different set counts/reps/loads materialize unchanged;
2. old session without rich prescriptions renders/logs normally;
3. solo collapsed card → pending row → editor → save → history;
4. two partners with distinct histories alternate and retain their own defaults;
5. swap before logging and swap after logging preserve the documented data;
6. all 20 muscles, direct/indirect/stabilizer/eligibility/warm-up/partner credits;
7. strength Watch payload decode on old/new shapes, duplicate/out-of-order apply,
   cancel/discard, resume, cooldown, and phone-unreachable recovery;
8. cardio completion duplicate/relaunch recovery and HR-present/absent summaries;
9. JSON export/import and CloudKit-compatible decoding of pre-planner fixtures;
10. the single iPhone smoke flow and single Watch smoke flow extended—not
    multiplied—to cover plan → proven runtime → saved history.

Simulator/headless gates do not replace real-device verification. Before a phase
that touches execution ships, complete one gym-style strength workout with a
partner, one planned strength workout on Watch with the phone unreachable, and
one Watch cardio workout with live HR. Confirm phone history, per-muscle totals,
HealthKit, audio/haptics, units, cancellation, and exactly-once reconciliation.

### AA.8 Explicit non-goals

Do not replace the full-screen set editor with planner chips, force every workout
to belong to a Plan, reduce muscles to broad body parts, move DB++ types into UI
or persistence, add Watch CloudKit, make `sendMessage` the only Watch transport,
rewrite the Watch lifecycle around `WKExtendedRuntimeSession`, remove manual
cardio/strength starts, or bulk-rewrite proven execution while adding planning.

---

*End of the Cladiron Coaching Platform specification, v2.5. Eight parts, 51 numbered sections, 27 appendices (A–AA).*

### Colophon

Written as the authoritative product description for the Cladiron platform: one product across four native surfaces — full-fidelity trainer planning on iPad, a **native Mac app in the same App Store record under Universal Purchase**, complete trainer capability on iPhone, execution on the wrist — and a tier boundary drawn where it belongs: **planning your own training is free everywhere; the only purchase is coaching someone else.**
