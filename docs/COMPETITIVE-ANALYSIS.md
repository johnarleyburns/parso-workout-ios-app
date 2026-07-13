# Cladiron — Competitive Gap Analysis

_Written 2026-07-13. Market data current as of July 2026._

The companion implementation plan is `plans/revenue/2026-07-13/`.

---

## 1. The headline

**Cladiron is feature-complete, fully monetized in code, and has never been submitted to the App Store.**

Everything required to take money already ships and is tested: StoreKit 2
(`Cadence/Cadence/Store/StoreService.swift`), a three-tier paywall
(`Store/PaywallView.swift`), the onboarding → "Your program is ready" → paywall
funnel (`Features/Onboarding/OnboardingView.swift:37`), a trial notifier,
entitlement resolution with offline caching
(`CadenceCore/Sources/CadenceCore/ProEntitlement.swift`), and a tip jar. There
is no release tag, no TestFlight release, and no listing. `MARKETING_VERSION` is
still 1.0 / build 1.

**The binding constraint is not a feature gap versus Hevy or Fitbod. It is that
nothing is in front of a user.** Every gap below is downstream of that.

Two further findings reframe the strategy, and they are the subject of most of
this document:

1. **Cladiron is priced against the wrong competitor** (§3).
2. **The coach's flagship signal is the one it does not have** (§5).

---

## 2. The revenue math

Target: **$100k/yr net**. Under Apple's Small Business Program (15% commission
below $1M), gross required is **~$117,600**.

| Annual price | Paying subs needed | Downloads needed @ 2.4% install→paid |
|---|---:|---:|
| **$34.99 (today)** | **3,362** | **~140,000** |
| $59.99 | 1,961 | ~82,000 |
| **$79.99 (recommended)** | **1,471** | **~61,000** |
| $99.99 | 1,177 | ~49,000 |

The 2.4% figure is derived from this project's own targets in
`plans/monetization-plan.md` §7 — 8% install→trial × 30% trial→paid. Category
conversion generally runs 2–5%.

Two conclusions fall out:

1. **Repricing $34.99 → $79.99 more than halves the distribution problem** —
   from ~140k downloads to ~61k — with zero engineering work and no product
   change. Nothing else in this document comes close to that return.
2. **140,000 downloads is not realistically achievable** for a brand-new indie
   app with no paid UA, no Android, no social loop, and no ASO history. At
   $34.99, the $100k goal is arithmetically out of reach through the channels
   currently permitted. **The price is the strategy.**

Churn compounds the argument. Category churn is ~9.2%/month (68.4% annually) and
80% of fitness-app users churn within 90 days. You are not filling a bucket once
— you are re-acquiring a large fraction of the base every year. Higher ARPU is
the only lever that makes that treadmill survivable without paid UA.

There is also an ordering constraint that makes this urgent: **you can always
discount later, but you cannot un-anchor a cheap price.** Raising a public price
post-launch reads as a bait-and-switch, and raising it on existing subscribers
requires per-user consent under App Store rules. Launch high; run a founding-member
promotion.

---

## 3. The field

| App | Price | What it actually is | Why it wins |
|---|---|---|---|
| **Hevy** | Free tier + $9.99/mo, $59.99/yr | Logger + **social feed** | 14M+ users; ~$7.2M annualized. The free tier is the product; the social graph is the moat |
| **Strong** | ~$4.99/mo, $99.99 lifetime | Logger; fastest set entry | The default for serious lifters; a decade of ASO signal |
| **Boostcamp** | Free + ~$59.99/yr | **Program marketplace** (11,000+ programs) | Content volume; coach-designed programs |
| **Fitbod** | $15.99/mo, $95.99/yr | AI program generator | Mass-market "tell me what to do today" |
| **Alpha Progression** | $12.99/mo, $79.99/yr | Hypertrophy-focused coach | The closest analogue to Cladiron's *shape* |
| **RP Hypertrophy** | $34.99/mo, **$299.99/yr** | Israetel's methodology, productized | Brand authority in evidence-based lifting |
| **JuggernautAI** | ~$35/mo (~$420/yr) | RPE-autoregulated powerlifting | Genuine autoregulation; elite credibility |
| **Jefit** | Freemium | Logger + exercise DB | 20M+ downloads |
| **wger / LiftLog / Liftosaur** | Free / one-time | Open-source loggers | Own the OSS niche today — but **none of them coach** |

### The mispricing

`plans/monetization-plan.md` §2 states the current positioning explicitly:

> "annual undercuts Fitbod (~$96/yr) ~3x; lifetime undercuts Hevy ($74.99) and
> Strong ($99.99); intro lifetime $49.99 is the cheapest lifetime of any serious
> app in the category."

**This benchmarks Cladiron against loggers. Cladiron is a coach.** Its
comparables are RP Hypertrophy ($299/yr) and JuggernautAI (~$420/yr). Its buyer
— the person who wants Schoenfeld 2021 cited on their deload — is the same
person already paying ~$12/mo for MASS Research Review and following Stronger by
Science.

**In evidence-based fitness, price is a credibility signal.** $34.99/yr does not
read as generous; it reads as amateur. The cheapest serious annual in a category
is not a position of strength when the product's entire claim is rigor.

---

## 4. Where Cladiron genuinely stands alone

`docs/REQUIREMENTS.md` already claims the open-source / no-account quadrant. That
claim holds up against the market:

- **Inline, tappable citations on every coaching output.** 53 citations in
  `CitationRegistry`, CI-enforced by `CitationIntegrityTests`, each annotated
  with *why the coach uses it*. RP has Israetel's **authority**; nobody else has
  **auditable citations**. This is unmatched and defensible.
- **A 13-test no-lab assessment battery that feeds the coach**
  (`CadenceCore/Sources/CadenceCore/Assessment.swift`), with honest evidence
  grading (`.validated` / `.fieldEstimate` / `.personalBenchmark`). No competitor
  does strength *and* cardio field testing that drives prescriptions.
- **Deterministic, not "AI."** In a market racing to say *AI*, a transparent rule
  engine that exposes its `scoreBreakdowns` and explains what it ruled out and
  why is a **trust** product. For this buyer, that is the right side of the trade.
- **No account, no server, no telemetry — verifiable, because the source is
  open.** Genuinely rare, and genuinely valued by the target segment.

---

## 5. The gaps, ranked by revenue impact

| Gap | Cladiron today | The field | Impact |
|---|---|---|---|
| **Distribution** | Not launched | A decade of ASO signal | **Fatal until fixed** |
| **Price** | $34.99/yr | Coaches charge $80–$420/yr | **2.3× on the download requirement** |
| **Passive readiness** | Self-report survey only | Whoop charges $239/yr for this | **The unbuilt wedge** — see below |
| **Data durability** | Local-only + manual JSON export | All have cloud sync | **1-star risk → kills conversion** |
| **Apple Watch app** | `ContentView.swift` is the Xcode "Hello, world!" template; the logging UI is a two-`Stepper` toy | All have real Watch apps | Table stakes for gym logging |
| **Acquisition loop** | None | Hevy's social feed | 20–35% churn delta |
| **PR timeline / heatmap** | **Claimed in `CLAUDE.md`; do not exist** | All have them | Cheap retention wins |
| **Exercise media** | Images only — and fetched from `raw.githubusercontent.com` at runtime | Video | No images offline; contradicts NFR-3 |
| **Program library** | 35 presets | Boostcamp: 11,000 | Not worth chasing |
| **Android** | None | All | Halves TAM — out of scope |

### The wedge: passive readiness

The coach is recovery-aware in architecture — `CoachFacts.swift` models
`RecoveryState`, `consecutiveHardDays`, `loadSpikeFlags`, and
`sessionsSinceDeloadByExercise` — but its readiness input is a **self-reported
survey** (`ReadinessEntry`: soreness, sleep quality, stress, motivation, pain
concern). Surveys do not get filled out.

Meanwhile the user's Apple Watch is already writing **HRV, sleep, and resting
heart rate** into HealthKit, and `Services/HealthKitProvider.swift` reads **none
of them** (it reads workouts, steps, HR, energy, and distance — and not
`bodyMass` either, despite `CLAUDE.md` claiming it).

Reading them costs nothing. It is a HealthKit read permission, the data stays
on-device, and the **Data Not Collected** privacy label is unaffected. And it
produces the single most compelling sentence this app could say:

> *"Your HRV is 18% below your baseline and you slept 5h 10m. The coach dropped
> today's squat to 80% and moved the volume to Thursday — here's the study."*

**Whoop charges $239/yr to tell you the first half of that sentence and cannot
tell you the second half. Hevy, Strong, Fitbod, and Boostcamp cannot tell you
either half.** No competitor can copy this without abandoning their architecture.
It flows directly out of engines already built and tested here — and it is what
makes $79.99/yr feel cheap rather than expensive.

#### An important caveat, which the repo itself supplies

The obvious version of this recommendation — *"replace the survey with HRV"* — is
**wrong**, and the codebase catches it.

The coach already cites **`sawMonitoring2016`**: *"Self-reported measures trump
objective monitoring."* Self-report was chosen **because the evidence favors it.**
Under this project's HARD RULE (every coaching output must cite navigable
science), Cladiron cannot ship a coach claim that contradicts a citation the
coach already carries.

The real problem is not that self-report is wrong. It is **compliance**.

So the design is **fusion, not replacement**: passive signals act as a
zero-friction prior that is always available; **self-report wins wherever it is
present**; and a passive red flag *prompts* the check-in. This fixes compliance
without contradicting the science — and it is the better product. It is recorded
as locked decision **D4** in `plans/revenue/2026-07-13/decisions.md`.

---

## 6. Recommendations

### R1 — Reprice before launch (highest ROI, zero engineering)

| Product | Today | Recommended |
|---|---|---|
| Annual | $34.99 | **$79.99** (keep the 1-month trial) |
| Monthly | $4.99 | **$12.99** |
| Lifetime | $49.99 → $69.99 | **$149.99**, founding launch price $99.99 |

Positioning: *Cladiron is the value option **within the coaching tier**, not the
discount option in the tracker tier. RP charges $299/yr for one coach's opinion;
Cladiron charges $79.99 and shows you the paper behind every prescription.*

Keep the free tracker genuinely complete and free forever. That principle
(`plans/monetization-plan.md` §1) is correct and should not change — it is
exactly what makes a higher coach price defensible rather than greedy.

**Risk:** an unknown brand with zero reviews will convert worse per-visitor at
$79.99 than at $34.99. Mitigate with the existing 30-day trial, and a longer
trial at launch if needed (an App Store Connect setting, not code). The revenue
math wins decisively even at materially lower conversion.

### R2 — Treat launch as the whole game

The path to $100k does not run through App Store search. Strong and Hevy have ten
years of install velocity, review volume, and keyword history. You will not
out-rank them on "workout tracker," and you should not try.

It runs through the concentrated, high-intent community that already buys
evidence-based fitness content. **The launch story is three stories in one:**

1. *Open source, no telemetry, no account — and you can read the code to verify
   it.* → Hacker News, r/opensource, PrivacyGuides.
2. *Every coaching decision cites a paper.* → r/weightroom, r/naturalbodybuilding,
   the Stronger by Science / MASS audience.
3. *A beautifully built, accessible, zero-SDK, zero-dependency SwiftUI app.* →
   **Apple featuring.** This is the highest-leverage free channel available and
   it is underrated. Apple actively features privacy-first apps with no
   third-party SDKs, full accessibility (Cladiron targets AX5), Swift Charts, and
   HealthKit. Submit the App Store Connect featuring-nomination form ahead of
   launch. A single feature can outperform a year of ASO.

**The bibliography is the content engine.** 53 citations, each already annotated
with why the coach uses it, is 53 articles for parso.guru. The quarterly
"protocol pack" changelog (already designed in `plans/monetization-plan.md` §6)
is a newsletter. This is the only acquisition channel that compounds without paid
UA.

**ASO: go long-tail.** Not "workout tracker." Target "evidence based training,"
"science based lifting," "RIR autoregulation," "5/3/1 app," "fitness test app,"
"private workout tracker no account." The existing subtitle — *Private Strength
Coach* — is good.

### R3 — Build the wedge (passive readiness)

See §5. This is the most important *product* recommendation in this document, and
it is what justifies R1's price.

### R4 — The three unlocked non-goals, ranked

**1. Data durability — do this first. It is insurance, not growth.** Local-only
storage plus a *manual* JSON export means the first user who loses or replaces a
phone writes *"it deleted my entire training log."* App Store rating is the
dominant conversion factor on a product page, and early reviews are permanent.
CloudKit's **private** database keeps the privacy story fully intact — the data
lives in the *user's* iCloud, Apple is the processor, you never see it, and the
Data Not Collected label survives.

Notably, `Models.swift:22` says *"no `@Attribute(.unique)` — CloudKit does not
support unique constraints."* **The schema was deliberately kept
CloudKit-compatible.** `current_state.md` shows sync was removed for
*positioning* reasons, not technical ones — so re-adding it is low-risk.

**2. Social — but not a feed. A shareable PR card.** Do not build Hevy's social
graph; it requires accounts and a server and would destroy the positioning. Build
the 10% that captures most of the value: a rendered, branded workout/PR image the
user can post to Instagram or Reddit. No account, no server, nothing leaves the
device but a PNG the user explicitly chose to share. A genuine acquisition loop at
zero privacy cost.

Pair it with the missing **PR timeline** and **consistency heatmap** — both
claimed in `CLAUDE.md`, neither existing, both cheap, and both the emotional
payload that makes a card worth sharing.

**3. Apple Watch — real, but expensive, and it does not sell the app.** It is
table stakes and it removes a switching objection, but nobody buys a *coaching
subscription* because of a Watch app. The plumbing already works
(`WatchWorkoutManager.swift` runs a real `HKWorkoutSession` and relays HR); the
gap is purely the logging UI. Do it after launch, funded by revenue.

### R5 — Fix what will cost money at launch

Detailed in `plans/revenue/2026-07-13/`. In brief:

1. **Paying subscribers are shown the upsell.** `Features/Home/HomeView.swift:171`
   passes `isPro: false` as a **literal** into `CoachUpsellPolicy.shouldShowCTA`,
   making the policy's `guard !isPro` early-return unreachable. A subscriber
   nagged to subscribe is a refund and a bad review.
2. **`CoachGate` is dead code** — defined, never instantiated. Real gating is
   `CoachSurfacePresenter`.
3. **Exercise images are fetched from GitHub at runtime** — no images offline,
   and GitHub sees a request per exercise view, in an app whose pitch is "we
   never phone home." This is the detail a hostile HN commenter finds.
4. **The launch docs contradict each other.** `docs/app-store/release-checklist.md`
   still says *"Confirm purchases unlock no features"* — it predates the Coach
   paywall and contradicts `docs/app-store/metadata.md`.
5. **`CLAUDE.md` and `README.md` say "free, open-source" and never mention the
   paid Coach.** The open-source community you are launching to on Hacker News is
   exactly the audience that reads this as a bait-and-switch. The honest story —
   *the tracker is free forever and open source; the coach is a paid product; the
   source is open so you can verify we never track you* — is fully defensible, but
   it must be told consistently or it becomes the top comment.
6. **`CLAUDE.md` advertises features that do not ship:** GZCLP and nSuns
   (deliberately removed for lack of published evidence), HealthKit bodyweight
   (never read), PR timeline and consistency heatmap (do not exist).
7. **GPLv3 + App Store.** GPLv3 is a known friction with Apple's terms (VLC was
   pulled). `git shortlog` confirms sole authorship, so the copyright holder can
   ship under Apple's terms regardless — but **add an explicit App Store
   exception to `LICENSE`** so a third party cannot file a GPL takedown against
   your own listing. On fork risk: keep GPLv3. The openness *is* the marketing,
   and a forked coach without the quarterly research updates decays within two
   quarters.

---

## 7. The honest assessment of $100k

With the repricing and the unlocked non-goals, $100k/yr is **reachable, but
probably in year two, not year one** — and it depends on one of the launch
channels landing hard: an Apple feature, a Hacker News front page, or a genuine
foothold in the evidence-based lifting community.

The one lever that would most change this answer is the one still ruled out:
**paid user acquisition.** At $79.99/yr with even a $30 blended CAC, you are
profitable on first-year LTV, and $100k becomes a spend problem rather than a
luck problem.

*"No paid UA at launch"* is a sound decision. *"No paid UA ever"* is difficult to
reconcile with a $100k target through organic channels alone. Worth revisiting
once launch produces real conversion data.

---

## Sources

Market data gathered July 2026.

- [Best Strength Training Apps in 2026 — Vora](https://askvora.com/blog/best-strength-training-apps-2026)
- [Best Strength Training Apps 2026: Hevy vs Strong vs Fitbod — Find Your Edge](https://www.findyouredge.app/news/best-strength-training-apps-2026)
- [How Hevy earns $166k/Month — Startups.fyi](https://www.startups.fyi/product/hevy)
- [Hevy — Sensor Tower overview](https://app.sensortower.com/overview/1458862350?country=US)
- [Best Hypertrophy Training Apps in 2026 — Mesostrength](https://mesostrength.com/blog/best-hypertrophy-training-apps)
- [Best Apps for Hypertrophy — Boostcamp](https://www.boostcamp.app/best/hypertrophy)
- [Health & Fitness App Subscription Benchmarks 2026 — Adapty](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/)
- [Fitness App Retention & Churn Rate 2026 — RetentionCheck](https://retentioncheck.com/churn-benchmarks/fitness-apps)
- [ASO Case Study: Fitness App Growth in a Competitive Market — ASOMobile](https://asomobile.net/en/blog/aso-case-study-fitness-app-growth-strategy-in-a-competitive-market/)
- [Fitness App Monetization Models: Beyond the Subscription — Nyusoft](https://nyusoft.com/fitness-app-monetization-strategies/)
- [GPLv3 is incompatible with the Apple App Store ToS — tigase/siskin-im#103](https://github.com/tigase/siskin-im/issues/103)
- [Estimate your VO2 Max with WHOOP](https://www.whoop.com/us/en/thelocker/estimate-your-vo-max-with-whoop-/)
