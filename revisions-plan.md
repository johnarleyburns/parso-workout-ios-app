
• Proposed Plan


  # Coach Scheduling, Background Cues, And Post-Completion Add-On Plan

  ## Summary

  Fix three related gaps:

  - Fixed rest weekdays are persisted but not honored by the scheduler.
  - Interval/boxing cue sounds do not reliably play in background because audio is configured as foreground-friendly cue audio, not background playback, and cue timing is view-driven.
  - After today’s plan is complete, Home should offer Coach-aware optional add-ons: encourage safe extra easy cardio, warn for higher-load work, and still let the user continue.

  ## Key Changes

  ### Fixed Rest Days

  - Make CoachSchedulePreferences.restPreference active in weekly planning.
  - Add a helper in core logic that answers whether a date should be rest:
      - .fixed(days:): rest when Weekday(from: date) is in the set.
      - .rolling(everyNDays:): rest when the projected hard/training cadence reaches the configured interval.

  - In WeeklyPlan.generate, pass restPreference into future planning and short-circuit fixed rest days to a .rest planned session before strength/cardio assignment.
  - Preserve current weekday chip UI in WhyThisTodayView for v1; do not replace with dropdowns unless the chips still prove confusing after behavior works.
  - Add a small label near fixed days such as “Coach will not schedule workouts on selected days.”

  ### Background Interval Audio

  - Add audio to UIBackgroundModes in the app Info.plist.
  - Change workout cue audio policy to use AVAudioSession.Category.playback with .mixWithOthers, no .duckOthers, and activate only when cue playback starts.
  - Keep user audio non-interrupted: no ducking, no forced deactivation that causes music/podcast glitches.
  - Replace AudioServicesPlaySystemSound interval beeps with app-owned short cue audio via AVAudioPlayer or AVAudioEngine, routed through the shared audio policy.
  - Move interval cue scheduling out of SwiftUI view ticks:
      - Create a small interval cue scheduler owned by the interval session/runner.
      - Schedule phase-start, 30-second warning, final countdown, and completion cues using wall-clock phase boundaries.
      - Keep IntervalRunner as the source of truth for elapsed/phase state.

  - Ensure boxing continues using bundled bell assets, but under the same background-capable cue system.
  - Keep spoken cues optional, but route AVSpeechSynthesizer through the same playback session.

  ### Post-Completion Coach Add-Ons

  - Introduce a core “add-on recommendation” result for use only when PlanAdherence.planComplete is true.
  - Inputs:
      - Current CoachFacts
      - CoachSchedulePreferences
      - Today’s completed events
      - Readiness and recovery gates

  - Add-on states:
      - encouraged: extra work is within weekly allotment or low-risk, especially easy cardio.
      - neutral: extra work is acceptable but not needed.
      - warn: extra work is higher load than planned or conflicts with recovery/readiness.

  - Recommended default add-ons after completion:
      - If cardio days or moderate-equivalent minutes are still below target: encourage easy walk/cycle/swim/row.
      - If weekly cardio is already met but user wants movement: offer easy walk/mobility as neutral.
      - If strength was already completed today, hard strength is warning-only.
      - If poor readiness, pain/illness concern, hard-day streak, or recovery window applies: warn before hard work.
      - HIIT/boxing/vigorous intervals after completion should warn unless Coach explicitly has remaining vigorous work eligibility.

  - Copy must avoid “overtraining/overtrained.” Use wording like:
      - “This is more load than planned today.”
      - “Recovery may be the limiting factor.”
      - “You can continue, but keep it easy if performance drops.”

  - Home complete state should keep the “On plan” acknowledgement but add:
      - Primary optional CTA: “Add easy cardio” when encouraged.
      - Secondary CTA: “Choose extra workout.”
      - Warning confirmation sheet for risky add-ons with “Start anyway” and “Choose easier option.”

  ## Public Interfaces / Types

  - Add a core add-on model, for example:
      - CoachAddOnRecommendation
      - CoachAddOnStatus = .encouraged, .neutral, .warn
      - CoachAddOnOption wrapping a CoachSession, status, message, and citation IDs.

  - Add a core evaluator, for example:
      - CoachAddOnEngine.run(facts:schedulePreferences:profile:) -> CoachAddOnRecommendation

  - Keep existing CoachDecisionEngine.run behavior intact for normal pre-completion recommendations.
  - Do not add server state, telemetry, or LLM inference.
  - Do not store add-on decisions persistently in v1; completed workouts already update history and future recommendations.

  ## Test Plan

  - Core schedule tests:
      - Fixed Saturday/Sunday rest produces rest sessions on those weekdays.
      - Fixed rest days do not schedule strength/cardio even when weekly targets are unmet.
      - Non-fixed days still schedule enough future sessions to satisfy targets where possible.
      - Rolling rest behavior is covered with deterministic dates.

  - Audio checks:
      - Static check that cue code contains no .duckOthers.
      - Static check that UIBackgroundModes includes audio.
      - Unit-test any pure audio configuration wrapper if introduced.
      - Manual real-device acceptance: lock device during boxing/HIIT with music or podcast playing; transition bells and warnings play without pausing or lowering other audio.

  - Add-on engine tests:
      - Plan complete + cardio below target encourages easy cardio.
      - Plan complete + cardio target met returns neutral easy movement.
      - Plan complete + strength already done warns for another hard strength session.
      - Poor readiness warns for hard add-ons but still allows easy movement.
      - Hard-day streak warns and cites recovery evidence.

  - UI tests:
      - After completing today’s plan, Home shows “On plan” plus add-on CTA.
      - Encouraged extra cardio opens the normal cardio setup flow.
      - Warning add-on shows confirmation and “Start anyway” routes to the selected workout.

  ## Assumptions

  - Keep the existing fixed-day chip UI for now; fix behavior before redesigning the control.
  - Background cues are important enough to request the iOS background audio capability.
  - User audio should continue mixing without ducking.
  - Add-on warnings are advisory, not blocking, except existing pain/illness safety copy should remain conservative.
  - “Overtraining” is not used in app copy because the current science-copy tests intentionally avoid diagnostic language.
