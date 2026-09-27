# Decisions — award polish

Answers to `decision-sheet.md`, recorded verbatim. Settled decisions are not
re-litigated.

## 2026-09-27

- **D4:** "voice should save immediately when it's sure"
  → Save immediately when the parse is exact. Show the confirm chip with
  Undo. Inferred or ambiguous parses wait for ✓.
- **D6:** "update target to watchos 11"
  → Raise `WATCHOS_DEPLOYMENT_TARGET` for the Watch app (and its tests) to
  11.0 in P5. Remove the now-redundant `#available(watchOS 11…)` checks, since
  Swift warns on unnecessary availability checks. Use
  `handGestureShortcut(.primaryAction)` directly.
- **D8:** "i don't think we want siri to log withuot the app open, saying
  "cladiron" everywhere will get tedious, rather i'd like things like "open
  cladiron" or something so I can open it and then start saying things to log
  sets if that's possible without saying "cladiron" every time?"
  → Siri does **not** log sets in the background. Siri, the Action Button,
  and Controls **open the app into a hands-free Listening mode**. The user
  says "Cladiron" once per session, and every command after that needs no
  wake word while the app listens (see `03` § Listening mode). Live
  Activity *tap* buttons (+30 s / Skip / Log planned set) are unaffected,
  because they are taps, not voice.
  **Implication for D3:** the primary voice mode becomes Listening mode, and
  hold-to-talk remains as the quick fallback. D3 is therefore still open:
  pick the default for when a workout starts (see the sheet).

- **Requirement (2026-09-27), verbatim:** "I'd also like a "hold to talk" or
  similar function on my PHONE because sometimes i don't have my watch and i'd
  really rather just lift up my phone for a sec and say "audrey did 20 reps at
  20 pounds" instead of having to click through an interface with sweaty hands,
  so add this to the plan and mockups to make a unified award polish plan"
  → Adds **Quick Talk**: one-shot phone voice logging with no navigation.
  Hold the big Log set button, hold the mic, lift the phone (raise-to-talk),
  or press the Action Button / Lock Screen control. It uses the same parser,
  save-when-sure (D4), and Undo. Quick Talk ships **before** Listening mode
  (P3a), because it's the everyday path. See `03` § Quick Talk and `04` §
  Lock-screen Quick Talk. Mockups: A21–A25.

## 2026-09-27 (second batch)

Verbatim: "d12: yes; d13: opt-in (also during onboarding, and if unset announce
in pre-workout and "never show again" as an option); d14: yes for clear
commands; d15 opt-in (also during onboarding, and if unset announce pre-workout
and also "never show again" as an option)"

- **D12:** Holding Log set starts Quick Talk; tapping still logs the planned set.
- **D13:** Raise to talk is **opt-in**. It's offered on a new onboarding page,
  and while it's unset, on the pre-workout Get Ready screen with "Not now" and
  "Never show again". See `03` § Voice opt-in offers, mockups A26/A27.
- **D14:** The Lock Screen / Action Button Quick Talk may save **clear (exact)
  commands only** without unlocking, with Undo on the Live Activity. Anything
  unclear opens the app.
- **D15:** Always-on Listening is **opt-in**, offered the same way as D13
  (onboarding + pre-workout while unset + "Never show again"). This is option
  (b): the `08` power gate still decides whether the option exists in a build.
  If the gate fails, the offers simply don't show it. D3 (auto-listen) and D11
  (Listening while locked) therefore stay at their recommended "no".

## 2026-09-27 (third batch)

Verbatim: "a"

- **D1:** Keep the bottom accessory visible across tabs; retain the Today
  Resume card only for crash-recovered paused sessions.

## 2026-09-27 (third batch, via questions)

- **D1:** "Keep for crash recovery (Recommended)". The tab accessory shows the
  live workout everywhere; Today's Resume card appears only for a
  crash-recovered paused session.
- **D2:** "Yes, add search tab (Recommended)". `Tab(role: .search)` for the
  exercise library; update CLAUDE.md's IA section in P1.
- **D5:** "Yes, add nicknames (Recommended)". The additive `Person.spokenAliases`
  field, synced and exported.
- **D9:** "Opt-in (Recommended)". AlarmKit rest alerts default to "In app
  only"; "Alarm (breaks through Silent)" is opt-in, with an explainer.
- **D10:** "Build, default on". The Foundation Models fallback is on by
  default wherever `SystemLanguageModel` is available and supports the
  voice language. It still ships only if the device evaluation passes
  (fewer "didn't catch" results, no more wrong logs). Its results are always
  dashed/inferred and wait for ✓. It never writes coaching text.
- **D7 (languages):** "at the minimum for my market I would like english,
  spanish, and chinese, research if other languages should be supported like
  french, portuguese, etc based on gym app usage". After the research
  follow-up: "let's launch with hevy's english, dutch, uk english (where
  different), spanish, and brazil/portugues, with french and german, chinese
  because i have chinese testers, so we get good coverage at launch"
  → Launch in en-US, en-GB (where different), nl, es, pt-BR, fr, de, zh-Hans,
  zh-Hant, for **voice and UI**.
- **Localization source (verbatim):** "I'd like you to add the translations
  applicable to free-exercise-db-plusplus in that repo (it's checked out in
  ../) adding multi-lingual support there as well, to help the community,
  keeping app-specific translations just within the app"
  → A DB++ additive i18n sidecar (exercise names, aliases, vocabulary)
  plus app-only strings in `Localizable.xcstrings`. See `09`.
- **China:** "Chinese voice without targeting China". Chinese ships for
  speakers anywhere; no MIIT/ICP filing; the mainland storefront isn't
  selected.

## Pending

D16 (show machine-draft exercise-name translations before native review?). See `09`.
