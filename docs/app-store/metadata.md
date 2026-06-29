# Cladiron App Store Metadata

Source of truth for the first public App Store listing. Keep this file aligned
with in-app copy, `README.md`, and `docs/REQUIREMENTS.md`.

## Positioning

Primary audience: science-minded, self-coached iPhone lifters who want evidence,
privacy, and data ownership.

Core promise:

> A private, open-source strength coach that explains every workout with cited
> sport science.

Differentiators:

- Cited coaching: every recommendation links to published training research.
- Private by design: no account, no cloud sync, no ads, no telemetry.
- Strength-first: fast set logging, PR context, routines, and progress trends.
- Honest v1 scope: iPhone-only; Apple Watch workouts import from Apple Health
  after the session, but there is no companion Watch app in v1.
- Free with optional tips: no subscription and no paid feature gates.

Avoid:

- Claims that imply medical advice, diagnosis, treatment, or guaranteed results.
- Claims that imply generative AI, cloud AI, or a black-box model.
- Claims that imply a companion Apple Watch app, live Watch HR streaming, cloud
  sync, social feeds, or nutrition coaching.
- "Donation" language for in-app purchases. Use "tip" or "support".

## App Store Fields

App name:

```text
Cladiron
```

Subtitle:

```text
Private Strength Coach
```

Promotional text:

```text
Train with cited sport science. Cladiron recommends what to do today, logs your lifts, and keeps your data on your iPhone.
```

Keywords:

```text
strength,workout,gym,weightlifting,hypertrophy,powerlifting,fitness,HealthKit,PR,coach
```

Category:

```text
Health & Fitness
```

App price:

```text
Free
```

In-app purchases:

```text
Optional one-time tips only. Tips unlock no features or content.
```

## App Description

```text
Cladiron is a private, science-based strength coach for iPhone.

Log your lifts, see what to train today, and understand why. Cladiron's on-device coaching engine reads your workout history, recovery state, training goal, and assessment results to recommend concrete next steps - then shows the published sport science behind the recommendation.

STRENGTH COACHING, NOT JUST LOGGING
- Recovery-aware Coach's Pick for today
- "Why This Today" explanations with ruled-out alternatives
- Prescriptive next-session targets for strength, hypertrophy, and endurance goals
- Built-in routines including full-body, upper/lower, push/pull/legs, 5x5-style, calisthenics, and Olympic lifting templates

FAST STRENGTH LOGGING
- Per-set weight, reps, RPE, and notes
- Last-time recall while logging
- PR detection and per-exercise trends
- Rest timer, training partners, warm-up, cooldown, and workout settings

PROGRESS YOU CAN AUDIT
- Estimated 1RM trends
- Weekly volume versus evidence-based landmarks
- PR timeline, history, and consistency views
- Strength and cardio assessments with cited protocols

PRIVACY BY DESIGN
- No account
- No ads
- No cloud sync
- No telemetry
- No developer-operated server
- Full JSON export/import so your training history and preferences stay portable

APPLE HEALTH + SENSORS
Cladiron reads steps, heart rate, and Apple Watch-recorded workouts from Apple Health with your permission. It can save workout summaries back to Health. For live heart rate during iPhone-recorded workouts, pair a Bluetooth chest strap.

IMPORTANT V1 SCOPE
Cladiron is iPhone-only in this release. Apple Watch workouts can be imported from Apple Health after they are recorded, but Cladiron does not include a companion Apple Watch app in v1.

FREE AND OPEN SOURCE
Cladiron is free, open-source, and ad-free. Optional one-time tips support development but unlock nothing; the full app is available without paying.

Cladiron's fitness tests and training recommendations are general educational coaching guidance, not medical advice, diagnosis, or treatment. Consult a qualified professional before starting or changing an exercise program.
```

## What's New

Initial release:

```text
Cladiron launches as a private, open-source strength coach for iPhone: cited recommendations, fast strength logging, progress trends, Apple Health import/write, assessments, routines, full export/import, and optional tips.
```

## Screenshot Storyboard

Use seeded, credible workout data. Do not show debug text, placeholder values, or
deferred Watch functionality.

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
   - Caption: `No account. No cloud. Your data exports anytime.`
   - Show: Backup & Restore / About privacy section.
7. Programs
   - Caption: `Built-in routines with cited rationale`
   - Show: routine browser or plan editor.
8. Support
   - Caption: `Free and open source, with optional tips`
   - Show: Support Cladiron screen with StoreKit local products.

## Review Notes

```text
Cladiron is a free, open-source strength training app. It has no accounts, no ads, no analytics, no cloud sync, and no developer-operated server.

HealthKit is used to read steps, heart rate, and workouts recorded by Apple Watch or other apps, and to save summary workouts back to Apple Health. Detailed set/reps/weight history is stored locally because HealthKit has no structured schema for it.

Bluetooth is used only for standard heart-rate monitors that expose the Bluetooth Heart Rate Service. Location is used only for iPhone-recorded outdoor workouts. Motion is used only to improve workout context.

The three in-app purchases are optional one-time tips that support development. They unlock no features or content; the app is fully usable without purchase.

Cladiron is iPhone-only in this release. Apple Watch workouts can be imported from Apple Health after recording, but this app version does not ship a companion Apple Watch app.
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
- In-app purchases are processed by Apple; the app only stores local supporter
  state in UserDefaults.
- User data can be exported/imported locally through the app.

## Manual Link Checklist

- Marketing URL: `https://www.parso.guru`
- Privacy Policy URL: `https://parso.guru/cladiron_privacy.html`
- Source URL: `https://github.com/johnarleyburns/parso-workout-ios-app`
- Apple App Review Guidelines: `https://developer.apple.com/app-store/review/guidelines/`
- Apple screenshot specifications: `https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/`
- Apple app privacy setup: `https://developer.apple.com/help/app-store-connect/manage-app-privacy/`
