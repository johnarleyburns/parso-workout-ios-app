# P1 — Docs / Repositioning

**Branch:** `p1/docs-repositioning` off `main`
**Risk:** None (docs + string renames only, no logic changes)
**Depends on:** nothing

---

## Problem

Two requirements files exist (root v0.3, docs/ v0.2) with diverging content. Vision
predates the pivot to Cladiron as a field-testable coach. User-visible strings still say
"Cadence" in several places. Privacy NFRs are implicit, not explicit. IA section describes
the old tab structure.

## What the Code Does Today

- `REQUIREMENTS.md` (root, 238 lines, v0.3): updated for iPhone-only v1, but
  watch-first framing, old IA (Home/Plan/Library), missing Tests + Citations FRs.
- `docs/REQUIREMENTS.md` (243 lines, v0.2): older, duplicate §9, watch-first phasing.
- `CLAUDE.md` (81 lines): still says "health tracker," IA not specified.
- `README.md` (50 lines): already says "Cladiron" — mostly aligned.
- User-visible "Cadence" strings: need grep to find (HomeView title?, AboutView?,
  Info.plist CFBundleDisplayName?, LaunchScreen?).

## Design

### 1. Reconcile Requirements

Merge root v0.3 (more current) + docs/ v0.2 into a single `docs/REQUIREMENTS.md`:
- Use root v0.3 as the base (iPhone-only v1 framing).
- Pull in any docs/-only content that's still relevant.
- Delete root `REQUIREMENTS.md`, replace with a one-liner: "See docs/REQUIREMENTS.md."

### 2. Reposition Vision/Goals

Rewrite §1 (Vision) and §2 (Goals) to:
- Free, open-source, privacy-first, iPhone-native strength **coach**
- Cardio secondary / capture-only
- Auditable science (every prescription + test cites its source via CitationRegistry)
- Field-testable fitness (no-lab battery feeds the coach)
- Built-in established programs for self-directed users
- State the competitive wedge (the unoccupied quadrant)

### 3. Naming Convention

Add to docs/REQUIREMENTS.md and CLAUDE.md:
> Product name (user-visible): Cladiron. Internal codename: Cadence.

### 4. Grep + Fix User-Visible "Cadence" Strings

Files to check:
- `Cadence/Cadence/Features/Home/HomeView.swift` — title
- `Cadence/Cadence/Features/Settings/AboutView.swift` — app name
- `Cadence/Cadence/Info.plist` — CFBundleDisplayName, CFBundleName
- `Cadence/Cadence Watch App/Info.plist` — same keys
- Any SwiftUI `Text("Cadence")` or `.navigationTitle("Cadence")`
- Launch storyboard / asset catalog strings

Change user-visible occurrences to "Cladiron." Do NOT touch:
- Type names (`CadenceApp`, `CadenceCore`, etc.)
- Bundle identifiers
- Xcode scheme/project names
- Import statements

### 5. Privacy NFRs

Add/strengthen in docs/REQUIREMENTS.md:
- NFR-P1: No-network core — all features work offline / airplane mode.
- NFR-P2: No third-party SDKs or telemetry frameworks. Zero analytics.
- NFR-P3: App Store privacy label reads "Data Not Collected."
- NFR-P4: Sync only via user's own iCloud (CloudKit private DB). No server.
- NFR-P5: Plain-English privacy section in docs.

### 6. Rewrite IA Section

Replace old Home/Plan/Library IA with Workout/Tests/Progress. Add FRs:
- FR-T1: Tests tab — no-lab assessment battery (details in P3)
- FR-T2: In-app citations — "Why this?" affordance on prescriptions + tests
- Update §8 phasing to reflect P1–P5.

### 7. Update CLAUDE.md

- "What this is" → Cladiron product name, strength coach focus
- Add IA: Workout / Tests / Progress
- Add naming convention
- Keep all existing architecture/workflow content

### 8. README Reconciliation

README already says "Cladiron." Reconcile any claims with the updated docs (e.g., ensure
feature list matches current state, not aspirational).

## Implementation Steps

1. Grep codebase for user-visible "Cadence" strings → list all hits with file:line
2. Write consolidated `docs/REQUIREMENTS.md` (reconciled, repositioned)
3. Replace root `REQUIREMENTS.md` with stub redirect
4. Fix all user-visible "Cadence" → "Cladiron" in Swift/plist files
5. Update `CLAUDE.md` (What this is + IA + naming convention)
6. Reconcile README if needed
7. `cd CadenceCore && swift test` — must pass (no logic changes, but verify)
8. `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`

## Testing

- `swift test` — no logic changes, should pass unchanged.
- `xcodebuild build` — verify string changes don't break compilation.
- Manual: confirm no user-visible "Cadence" remains (grep verification).
