# Cladiron App Store Metadata

Source of truth for the first public App Store listing. Keep this file aligned
with in-app copy, `README.md`, and `docs/REQUIREMENTS.md`.

## Positioning

Primary audience: science-minded, self-coached iPhone lifters who want evidence,
privacy, and data ownership.

Core promise:

> An open-source, privacy-first strength coach that explains every workout with cited
> sport science.

Differentiators:

- Cited coaching: every recommendation links to published training research.
- Private by design: no account, no ads, no telemetry, and sync only through the user's private iCloud.
- Strength-first: fast set logging, PR context, routines, and progress trends.
- Companion Apple Watch app: phone-free strength (with partner rotation),
  HIIT/boxing rounds, and a full cardio suite (run, walk, cycle, swim, rowing)
  with live wrist heart rate; every watch workout saves to Apple Health and
  syncs back to the phone.
- Complete free app with one optional contribution: the tracker, history,
  analytics, coach, planning, execution, and export are available without
  purchase. A successful $9.99 contribution only adds a Supporter badge.

Monetization boundary (binding — keep copy aligned):

- Free forever: logging, history, PRs, trends, assessments, routines, Apple
  Health import/write, JSON export/import, coach generation/review, planning,
  autoregulation, and execution. The optional contribution unlocks nothing;
  it only records Supporter status and shows the Home badge.

Avoid:

- Claims that imply medical advice, diagnosis, treatment, or guaranteed results.
- Claims that imply generative AI, cloud AI, or a black-box model.
- Claims that imply cloud sync, social feeds, or nutrition coaching. (The
  automatic iCloud backup lives in the user's own private database — call it
  "backup", never "sync".)
- "Donation" language for in-app purchases. Use "support" or "contribute".

## App Store Fields

App name:

```text
Cladiron
```

Subtitle:

```text
Private Strength Coach
```

Promotional text (≤170 chars, editable without re-review):

```text
Cladiron reads your lifts, builds cited plans, and shows what it notices — free. Optional support helps fund continued development.
```

Keywords (≤100 chars, comma-separated, NO spaces; do not repeat "strength"/"coach"
— already indexed via the subtitle):

```text
workout,gym,fitness,weightlifting,hypertrophy,powerlifting,tracker,RPE,1RM,routine,program,PR,RIR
```

Category:

```text
Health & Fitness
```

App price:

```text
Free (with one optional $9.99 development contribution)
```

In-app purchases:

```text
Contribute to development — $9.99 (consumable; optional; unlocks nothing)
```

Support URL (required — a real help/contact page):

```text
https://github.com/johnarleyburns/parso-workout-ios-app/issues
```

Marketing URL (optional):

```text
https://www.parso.guru
```

Copyright:

```text
2026 John Arley Burns
```

## App Description

```text
Cladiron is a private, science-based strength coach for iPhone. Log your lifts, track your progress, and understand your training — with every coaching call backed by published sport science.

FREE, FOREVER
The full tracker is free with no ads, no account, and no tracking:
- Fast per-set logging: weight, reps, RPE, notes, and last-time recall
- PR detection and per-exercise trends
- Estimated 1RM, weekly volume vs. evidence-based landmarks, consistency
- Built-in routines: full-body, upper/lower, push/pull/legs, 5x5, calisthenics, Olympic
- Strength and cardio assessments with cited protocols
- Apple Health import (steps, heart rate, Apple Watch workouts) and summary write-back
- Companion Apple Watch app: phone-free strength, HIIT/boxing rounds, and cardio (run, walk, cycle, swim, rowing) with live wrist heart rate
- Full JSON export/import so your data stays portable, plus automatic backup to your own private iCloud
- Live coach insights: Cladiron continuously reads your logs and tells you what it notices about your training — free

THE COACH
Cladiron turns those observations into action. It builds and reviews your
program, prescribes exact sets and reps, autoregulates from logged performance
and recovery, plans deloads, and cites the research behind every call.

PRIVACY BY DESIGN
- No account, no ads, no telemetry, no developer-operated server; optional private-iCloud sync
- Health, Bluetooth, Location, and Motion data stay on your device
- Open-source and privacy-first, with no developer-operated server or tracking

APPLE WATCH INCLUDED
Train phone-free from your wrist: strength with partner rotation, HIIT and boxing rounds, and cardio (run, walk, cycle, swim with lap counting, rowing). Live heart rate streams from the wrist, workouts count toward your Activity rings, and everything syncs back to your iPhone automatically.

Cladiron's fitness tests and training recommendations are general educational coaching guidance, not medical advice, diagnosis, or treatment. Consult a qualified professional before starting or changing an exercise program.

—
Optional contribution:
- Contribute to development — $9.99, one-time consumable
The contribution is processed by Apple, unlocks nothing, and only adds a
Supporter badge to Home after a successful purchase.
Privacy Policy: https://parso.guru/cladiron_privacy
Terms (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## What's New

Initial release:

```text
Cladiron launches as an open-source, privacy-first strength app for iPhone and Apple Watch: fast logging, PRs, progress trends, Apple Health import/write, assessments, routines, a phone-free Watch app (strength, HIIT, cardio with live wrist HR), cited coach planning, and full export/import with private-iCloud backup — all free. An optional $9.99 contribution supports development and unlocks nothing. Cladiron is released under GPLv3-or-later with the Cladiron App Store Exception and built on the open free-exercise-db-plusplus project; its exercise database, annotations, and related tooling remain freely available for use by other applications under their own license.
```

## Screenshot Storyboard

Use seeded, credible workout data. Do not show debug text or placeholder values.

1. Coach's Pick
   - Caption: `Know what to train today`
   - Show: Home with Coach's Pick, weekly plan context, and Start button.
2. Why This Today
   - Caption: `Every recommendation explains why`
   - Show: what was done, what was ruled out, and next eligible time.
3. Strength Logging
   - Caption: `Fast set logging with PR context`
   - Show: set entry, last-time hint, PR/previous performance.
4. Progress
   - Caption: `Track strength, volume, and consistency`
   - Show: e1RM trend, volume landmarks, or progress dashboard.
5. Science Citations
   - Caption: `Published research behind every insight`
   - Show: citation detail or "The science" link from a coach output.
6. Privacy + Export
   - Caption: `No account. Private iCloud. Export anytime.`
   - Show: Backup & Restore / About privacy section.
7. Programs
   - Caption: `Built-in routines with cited rationale`
   - Show: routine browser or plan editor.
8. Support
   - Caption: `Privacy-first and ad-free, with optional support`
   - Show: Support Cladiron screen with StoreKit local products.

Apple Watch screenshots (required — the archive embeds a watchOS app; App Store
Connect will not submit without at least one Apple Watch screenshot):

1. Watch strength session — set logging with partner rotation.
2. Watch cardio — live HR during a run/cycle.
3. Watch HIIT — round timer.

## Review Notes

```text
Cladiron is an open-source, privacy-first strength app for iPhone. It has no accounts, no ads, no analytics, and no developer-operated server; private iCloud sync is optional. The application is released under GPLv3-or-later with the Cladiron App Store Exception; brand assets remain protected under TRADEMARKS.md.

The tracker is free: logging, history, PRs, analytics, assessments, routines, Apple Health import/write, and JSON export/import. Free users also see the coach's live insights (observations about their training).

All app features are available without purchase, including coach planning and
review, logging, history, export, and Watch execution. The optional $9.99
contribution is one-time, unlocks nothing, and only adds the Supporter badge on
Home after a successful Apple transaction. A full log → history → export loop
works without purchase.

HealthKit is used to read steps, heart rate, and workouts recorded by Apple Watch or other apps, and to save summary workouts back to Apple Health. Detailed set/reps/weight history is stored locally because HealthKit has no structured schema for it.

Bluetooth is used only for standard heart-rate monitors that expose the Bluetooth Heart Rate Service. Location is used only for iPhone-recorded outdoor workouts. Motion is used only to improve workout context.

This version includes a companion Apple Watch app for phone-free workouts (strength, HIIT/boxing, and cardio including swim). The watch app runs an HKWorkoutSession for live heart rate, saves workouts to Apple Health, and relays completed sessions to the iPhone over WatchConnectivity. Like the phone app, it has no accounts and no networking.

The app also automatically backs up the user's local data to the user's own private CloudKit database (hence the iCloud entitlement). This is user-owned storage processed by Apple; the developer operates no server and cannot access the data, so App Privacy remains "Data Not Collected".
```

## Privacy Answers

App Privacy posture:

```text
Data Not Collected
```

Rationale:

- No account or profile is created on a developer server.
- No analytics, telemetry, advertising SDK, crash reporter, or third-party SDK is
  present.
- Health, Bluetooth, Location, and Motion data stay on device.
- The automatic backup is stored in the user's own private CloudKit database;
  the developer operates no server and cannot access it.
- In-app purchases are processed by Apple; the app only stores local supporter
  state in UserDefaults.
- User data can be exported/imported locally through the app.

## Manual Link Checklist

- Marketing URL: `https://www.parso.guru`
- Support URL: `https://github.com/johnarleyburns/parso-workout-ios-app/issues`
- Privacy Policy URL: `https://parso.guru/cladiron_privacy`
- Source URL: `https://github.com/johnarleyburns/parso-workout-ios-app`
- Apple App Review Guidelines: `https://developer.apple.com/app-store/review/guidelines/`
- Apple screenshot specifications: `https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/`
- Apple app privacy setup: `https://developer.apple.com/help/app-store-connect/manage-app-privacy/`
