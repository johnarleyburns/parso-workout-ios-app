# Releasing — Quarterly Coach Protocol Packs

The Coach knowledge base is versioned in-repo and ships with the app. A quarterly
"protocol pack" is just an app update that bumps the KB and surfaces a changelog
(monetization plan §4.6, §6). No server, no remote config.

## What a pack must contain (minimum bar)

Per the founder cadence (§6): **at least 1 programming-logic improvement + 3
new/updated citations**. If a quarter has nothing worth shipping, say so honestly
in the changelog rather than padding — the credibility *is* the product.

## Steps

1. **Research.** Review new meta-analyses/RCTs (MASS Research Review, Stronger by
   Science, PubMed alerts) in strength & hypertrophy.
2. **Update the engine.** Make the programming-logic change in `CadenceCore`
   (e.g. `CoachDecisionEngine`, `VolumeLandmarks`, `CoachPlanOptimizer`). Add or
   update the backing citations in `CitationRegistry` (and `docs/CITATIONS.md` —
   they must stay in sync).
3. **Bump the KB.** Edit
   `CadenceCore/Sources/CadenceCore/Resources/coach-kb-version.json`:
   - Bump `version` (calendar semver, e.g. `2026.4.0`) and `releaseDate`.
   - Prepend a new entry to `entries` with `version`, `date`, `title`, `summary`,
     and `citationIds` (every ID **must** resolve in `CitationRegistry`).
4. **Verify.** `cd CadenceCore && swift test` — `CoachKnowledgeBaseTests` and
   `CitationIntegrityTests` fail if any changelog citation is missing.
5. **Ship the app update.** The "Coach Research Updates" screen renders the new
   entry automatically, and a "New" badge appears in Settings until the user views
   it. Reuse the `summary` as the App Store "What's New" text.
6. **Amplify.** Each pack doubles as a long-form article on parso.guru.

## Notes

- The KB version is display/changelog only; entitlement is unaffected. Pro and free
  users both see the changelog (free sees it as paywall reinforcement).
- Schema changes to the app's local store must remain additive (see CLAUDE.md).
