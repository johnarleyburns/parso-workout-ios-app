# Decisions — launch-blocker fixes (answered by owner, 2026-07-18)

Recorded per the dev-methodology decision-sheet rule. Do not re-litigate.

1. **Idle watchdog / auto-end** — Owner (verbatim, on the auto-end diagnosis): "Wait, nothing showed 'still training', I didn't see any alert, and the screen was locked for only 2 minutes, so what happened?" → root cause re-verified: the 30s auto-end deadline is wall-clock and fires on unlock before the alert renders; activity = logged sets only. **Decision:** the system may auto-**pause** (idle watchdog, crash recovery) but may **never end/cancel** a workout — only an explicit user tap ends it. The `IdleWatchdog` type must make auto-end unrepresentable.

2. **Crash/upgrade during a workout** — Owner (verbatim): "if the app crashes or is upgraded during a workout, I NEVER want to lose my current workout, if this happens show the 'Resume Workout' - it's okay to auto-pause a workout in case of this crash or idle timer watchdog, but NEVER cancel/end the workout, the user has to explicitly do that." **Decision:** on relaunch, adopt the in-progress session paused (dead gap folded in as a paused span via a UserDefaults heartbeat), show the Resume Workout card on Home, do not auto-present. Stale sessions are still recoverable, never discarded.

3. **Home daily history** — Owner chose: **True today-list** — direct query of today's completed sessions (HistoryPresenter pattern), replacing the coach-fact "What you did" source. No cap; newest first.

4. **Per-rep weight auto-fill fallback** — Owner chose: **Estimate via e1RM** — exact rep-count match first; else scale the best recent working set through the user's chosen rep-max formula (Epley/Brzycki, existing `oneRMEstimation` citation) to the target reps; else the existing cascade. Per exercise, per performer.
