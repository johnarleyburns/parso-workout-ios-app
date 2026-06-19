# Decisions — strength pivot

Record the user's verbatim answers here once made (per CLAUDE.md methodology). Until
then these are OPEN and block the dependent phases.

| ID | Question | Recommendation | Answer (locked 2026-06-15) |
|----|----------|----------------|--------|
| D1 | Spin-out mechanics | Flag now, extract later | **REMOVE CrossFit** — `git tag` the code before deleting so it's recoverable for a future separate app. **Keep Boxing, reclassified as cardio-only** (no separate boxing app). |
| D2 | CC0 source + images | free-exercise-db base | **free-exercise-db (Unlicense) + embed its public-domain images & instructions on-device** (offline; drop EXRX links). Downscale images. |
| D3 | Citation prominence | Mandatory card | **Always-visible "why + citation" card on every recommendation** (the differentiator). |
| D4 | Goals at launch | Both | **Strength + Hypertrophy + Endurance** (user-selected per goal). |
| D5 | Assessment cadence | App-suggested, opt-in | **App suggests a re-test at block end (~6–8 wks), opt-in.** |
| D6 | Non-medical framing | Yes | **Assumed YES** (strictly "coaching," one-time disclaimer, no health claims) — not separately contested; flag if you disagree. |
| D7 | Naming/spin-out apps | Reserve names | Resolved by D1: no Boxing spin-out (boxing stays as cardio); CrossFit preserved via git tag for a possible future app. |
| D8 | Image bundling | Downscale | Embed + **downscale**; if binary size is a problem, move images to an on-demand asset pack (implementation detail). |
| D9 | Citations file | Yes | **Yes** — curated, in-app, open `CITATIONS.md`, reviewed before the prescriptive phase (P5). |
