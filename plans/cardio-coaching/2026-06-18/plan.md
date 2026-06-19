# Cardio Coaching Plan

**Date:** 2026-06-18
**Goal:** Add science-backed cardio coaching to the engine so it prescribes interval protocols, recommends balanced training, and carries a cardio exercise catalog.

## Research Summary

### Key Papers

| Citation | Protocol | Finding |
|----------|----------|---------|
| Tabata et al. 1996 (MSSE 28(10)) | 20s/10s x8 at 170% VO2max | +14.6% VO2max in 6 wk; also gains anaerobic capacity (steady-state does not) |
| Helgerud et al. 2007 (MSSE 39(4)) | 4x4min at 90-95% HRmax | HIIT > moderate training for VO2max; already cited |
| Gibala/Little 2010 (J Physiol 588(6)) | 60s/75s x8-12 at ~100% peak power | Mitochondrial biogenesis + performance in 2 wk; practical alt to all-out SIT |
| Milanovic et al. 2015 (Sports Med 45(10)) | Meta-analysis, 28 studies, n=723 | Both HIIT and endurance training improve VO2max; HIIT produces greater gains (+5.5 vs +4.9 mL/kg/min) |
| Bar-Or 1987 (Sports Med) | Wingate 30s all-out | Gold-standard anaerobic test; already cited |
| Cooper 1968 (JAMA 203(3)) | 12-min run field test | VO2max proxy; already cited |

### Protocol Inventory (already in IntervalPlan.swift)

| Protocol | Work/Rest | Rounds | Total | Intensity |
|----------|-----------|--------|-------|-----------|
| Tabata | 20s/10s | 8 | 4 min | 170% VO2max |
| Norwegian 4x4 | 4min/3min | 4 | 28 min | 90-95% HRmax |
| Gibala | 60s/60s | 8 | 19 min | ~100% peak |
| SIT | 30s/4min | 4 | 22 min | All-out |
| REHIT | 20s/3min | 2 | 10 min | All-out |
| 10-20-30 | 30+20+10s | 15 | 22 min | Mixed |

## Current Gaps

1. **Citations**: Missing Tabata 1996, Gibala 2010, Milanovic 2015 meta-analysis
2. **Cardio exercises**: Only 3 (Run, Rowing Machine, Double-Under). Need cycling, walking, swimming, jump rope, stair climb, elliptical
3. **Proactive rules**: Engine only fires on declining assessments. No "you should do cardio" for strength-only users
4. **Weekly target**: No rule for the WHO-recommended 150 min moderate or 75 min vigorous per week
5. **Protocol recommendation**: No logic to recommend the right protocol for the user's goal/level

## Implementation Plan

### Phase 1: Citations (CadenceCore)
- Add `tabataProtocol` (Tabata et al. 1996)
- Add `gibalaHIT` (Little et al. 2010)
- Add `hiitMetaAnalysis` (Milanovic et al. 2015)
- Update CITATIONS.md

### Phase 2: Cardio Exercise Catalog (CadenceCore)
Add exercises with `.cardio` category:
- Cycling (Stationary), Road Cycling, Walking, Stair Climbing, Elliptical, Jump Rope, Swimming

### Phase 3: Cardio Coaching Rules (CadenceCore)
New insight rules:
- `cardioDeficit`: user has strength sessions this week but zero cardio → attention "Add cardio for heart health"
- `lowCardioVolume`: user has <75 min cardio this week → info "Aim for 150+ min moderate or 75+ min vigorous"

New recommendation rules:
- `weeklyCardio`: no cardio sessions logged this week → recommend a protocol matched to experience
  - Beginner: Norwegian 4x4 or steady-state walk/run
  - Intermediate: Gibala or Tabata
  - Advanced: SIT or Tabata
- `cardioProgression`: user has been doing cardio regularly → recommend stepping up protocol intensity

### Phase 4: Tests
- Citation invariants (every rec/insight must be cited)
- Rule trigger tests for the new cardio rules
- Exercise catalog includes new cardio entries

## Rollout

Single branch, single PR. All changes in CadenceCore + CITATIONS.md.
