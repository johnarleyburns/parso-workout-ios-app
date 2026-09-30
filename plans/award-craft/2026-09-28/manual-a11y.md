# C5 manual accessibility matrix

This is the release-device pass for the changed workout surfaces. The host
tests cover the semantic labels and action policy; these checks require VoiceOver
and Dynamic Type on a real iPhone and are not represented as completed by a
generic build.

| Setting | Path | Pass condition |
|---|---|---|
| VoiceOver | Session → expanded exercise | Exercises rotor lands on every card; Unlogged sets rotor lands on every pending row; pending rows expose Log/Edit/Skip and logged rows expose Edit/Repeat/Delete. |
| VoiceOver | Log a set and finish rest | Announces the progress change, then “Rest complete. Ready for the next set.”; a PR announcement includes the exercise and new value. |
| Voice Control | Session | “Tap Log set”, “Tap Repeat set”, and “Tap Skip rest” activate the same actions as touch. |
| Switch Control | Session | The actionable pending row and Log control are reachable without a precision gesture. |
| Accessibility XXL | Today → Session | Exercise names wrap, set content remains readable, and no action control is clipped or overlaps. |
| Bold Text / Increase Contrast | Session and This Week | Labels remain distinguishable without relying on color alone. |
| Reduce Motion / Reduce Transparency | Session | No required state change depends on animation or material translucency. |
| iPad regular width | Today, Progress, Settings | No stretched 1,000pt hero or clipped navigation; split/regular-width layout remains usable. |

Record device model, OS build, and pass/fail notes in the release audit before
submission. A headless pass must not be used as evidence for these device-only
checks.
