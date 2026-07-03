# Coach Surface Design — Attractive, Never Obtrusive

Status: APPROVED DIRECTION — agent-ready
Scope: HomeView coach presence, preview surfaces, conversion triggers, dismissal mechanics
Companion to: monetization-plan.md (§4.4–4.5)

## AMENDMENT (2026-07-03) — continuous insights, occasional upsell

Founder decision, supersedes the parts of §2/§4 that rate-limit or suppress the
*insights themselves*:

- **The coach insight updates CONTINUOUSLY, exactly like the real (Pro) coach.**
  A free user always sees the coach's live *observation* about their training on
  Home — recomputed from their logs every day / after every workout. There is no
  7-day insight frequency cap and no per-rule 30-day suppression on the
  observation. Seeing real, continuously-updated value is the point.
- **Only the PRESCRIPTION is paywalled** — what the coach *would do* about the
  insight (the exact sets/reps/load and the plan). That panel stays locked for
  free users, with its citation title visible.
- **"Unlock the Coach" is the only rate-limited element.** The prominent green CTA
  is what we hide most of the time (via `CoachUpsellPolicy`, min 14 days between
  billboard impressions) so the free experience never feels like a running ad. A
  discreet, always-available tap target on the locked prescription still lets a
  motivated user convert on their own initiative.

Net effect: the 5-state machine in §2 collapses to a single free-user surface —
insights always visible + locked prescription always visible + the big CTA shown
only occasionally. §4's insight frequency cap / suppression map are dropped;
`CoachUpsellPolicy` governs the CTA cadence instead.

## 0. Problems in current build (screenshots 2026-07-03)

1. Coach Preview card occupies the entire first viewport; quick actions (Strength/Cardio/Log/Programs) and Planned week are below the fold. For a free user this is a daily ad before their own data.
2. "The science ›" rendered 3× with identical labels — placeholder bug; must show real citation titles.
3. Program chips (Sat/Sun) duplicated between the preview card and the Planned card.
4. Three lock icons inside one card reads as nagging; one lock affordance per surface max.
5. Card is static — identical every day → banner blindness within a week.

## 1. Design principles (binding)

- **The free user's Home leads with their data**: today's plan, quick actions, last workout. The coach earns screen real estate only by saying something *about their training*, or by invitation.
- **Observation free, prescription locked.** The coach may freely tell a free user what it *noticed* in their logs; what to *do about it* is Pro. This line is the paywall.
- **Every coach surface is dismissible, and dismissal is remembered.** No dark patterns — respecting "no" is the brand, and it raises conversion when the user is actually ready.
- **Re-pitching is event-driven, never time-driven.** New logged evidence or a quarterly protocol pack can re-raise the coach; a calendar cannot.

## 2. Coach presence state machine

Persisted in UserDefaults (`coachSurfaceState`, plus counters/timestamps below). Entitlement changes (from ProEntitlement) override presentation states.

| State | Who | Home presentation |
|---|---|---|
| `introducing` | New/updated user, first 3 Home sessions after onboarding OR after a protocol pack release | Full preview card at top (current design, fixed per §5) |
| `ambient` | Default steady state, free user | Compact CoachRow (§3), placed AFTER quick actions + Planned, BEFORE What You Did |
| `insight` | Free user, a ghost insight is available (§4) | CoachRow expands to two lines showing the insight; auto-reverts to `ambient` when insight expires or is dismissed |
| `hidden` | User chose "Hide Coach offers" | No Home presence at all. Coach reachable via Programs tab row + Settings. Changelog badge still allowed on app update |
| `trial` / `pro` | Entitled users | Coach card at top becomes the functional prescription surface (earned placement) |

Transitions:
- `introducing → ambient`: after 3rd Home appearance OR first explicit dismiss (✕), whichever first. Counter: `coachIntroImpressions`.
- `ambient ↔ insight`: driven by insight engine (§4).
- any → `hidden`: Settings toggle, or long-press CoachRow → "Hide Coach offers".
- `hidden → introducing`: never automatic. Only if user re-enables in Settings. Protocol pack releases show a one-line changelog badge on the Programs tab, not a Home card.
- purchase/trial start → `trial`/`pro` from anywhere.

## 3. Compact CoachRow (the ambient surface)

One row, visually consistent with What You Did rows — not a promo card:

```
[leaf icon]  Coach                                   [›]
             Builds and adjusts your program
```

- Height ≈ 56pt, single lock glyph max (in nav chevron area or none).
- Tap → CoachPreviewScreen (§5).
- Long-press → context menu: "Hide Coach offers" / "Learn more".
- No green fill; tinted icon only. It's a directory row, not a billboard.

## 4. Ghost insights (the attractor)

The coach runs read-only over the user's real logs (all local — this is a privacy flex: the "preview coach" analyzes on-device, nothing leaves the phone). When a rule fires, CoachRow enters `insight`:

```
[leaf icon]  Coach noticed                            [›]
             Bench RIR fell 2 sessions in a row —
             tap to see what it would change
```

Rules v1 (each maps to an existing expert-system detector; agent: reuse KB logic in read-only mode):
1. RIR trending down ≥2 sessions on a tracked lift → fatigue observation.
2. New PR logged → "It would adjust next week's target load."
3. Same load ≥3 sessions on a lift (plateau) → progression observation.
4. ≥3 workouts logged in first 14 days → "Enough history to build your plan."
5. Long gap (≥10 days) then return → "It would rebuild your ramp-up week."

Constraints:
- **Frequency cap: max 1 insight surfaced per 7 days; max 1 active at a time.** Queue and drop, don't backlog.
- Insight shows the *observation* with real numbers from their logs. Tapping opens CoachPreviewScreen scrolled to a locked "What the Coach would do" panel — prescription blurred/locked, citation title visible.
- Dismissing an insight (✕ or swipe) suppresses that rule for 30 days (`insightSuppression[ruleID]`).
- Insights never fire during an active workout session and never as notifications (the only coach notification remains the trial-day-27 value summary from monetization-plan §4.4).

## 5. CoachPreviewScreen (full pitch moves off Home)

The current inline card content becomes a dedicated screen (also used in `introducing` state as the card's tap target):

1. Header + one-paragraph promise (keep current copy — it's good).
2. **Remove program chips** (duplicated on Home).
3. Locked capability rows: keep the three (Today's prescription / Autoregulation / Deload & adaptation) but **one lock treatment**: rows are dimmed with a single "Pro" pill on the section header instead of three lock glyphs.
4. THE SCIENCE: replace the 3× placeholder with **3 real citation titles** from the KB, e.g. "Volume and hypertrophy — Schoenfeld et al. 2017 ›". Tappable, free to read (citations are marketing; the *application* of them is Pro). Rotate selection per KB version.
5. If arrived via ghost insight: insert "What the Coach noticed" panel above capabilities with their real data, and the locked "What it would change" panel.
6. Green "Unlock the Coach" CTA + "Everything else in Cladiron is free forever." (keep verbatim) → PaywallView.
7. Footer link: "Hide Coach offers" (small, honest, visible). 

## 6. Home layout per state (free user)

`ambient`/`insight` ordering:
1. Today header + date
2. Quick actions row (Strength / Cardio / Log / Programs)
3. Planned (rest of week)
4. CoachRow (compact or insight form)
5. What you did

`introducing`: current full card at top, then 2–5. After 3 impressions or ✕ → `ambient` permanently (until protocol pack).

## 7. Copy bank

- Row default: "Coach — builds and adjusts your program"
- Insight prefix: "Coach noticed" (never "Upgrade now", never urgency language)
- Post-PR insight: "New PR on {lift}. The Coach would raise next week's target."
- Fatigue: "{lift} RIR fell {n} sessions in a row — see what it would change"
- Plateau: "{lift} has held {weight} for {n} sessions — see its progression plan"
- CTA everywhere: "Unlock the Coach" (consistent verb, already established)
- Reassurance line (verbatim, everywhere the CTA appears): "Everything else in Cladiron is free forever."

## 8. Agent tasks (sequenced)

1. **PR-A**: Fix science links (real citation titles from KB) + remove duplicate program chips + single-lock treatment. Pure cleanup of current card.
2. **PR-B**: Extract card → CoachPreviewScreen; introduce `coachSurfaceState` machine + CoachRow; reorder Home per §6; impressions counter + dismissal persistence.
3. **PR-C**: Ghost insight engine (read-only rule evaluation over logs, frequency caps, suppression map) + insight row form + insight panel in CoachPreviewScreen.
4. **PR-D**: Settings toggle "Hide Coach offers"; Programs-tab coach entry row (always present, all states); protocol-pack `introducing` re-trigger hook (reads KB version from monetization-plan §4.6 work).

Tests: state transitions (impressions, dismiss, hide, re-enable, entitlement override), frequency cap and suppression windows, free-user full-loop regression (log → history → export with coach in `hidden` — zero coach UI on Home).

## 9. Measures of success

No telemetry, so proxies: App Store trial-start rate before/after (ASC), and review sentiment — target zero reviews complaining about upsell nagging. The absence of complaints is the design working.