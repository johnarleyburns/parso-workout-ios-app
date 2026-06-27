# Home Simplification Rationale

Date: 2026-06-26

## Decision

Home should answer three questions without making the user choose between several
similar overview screens:

1. What should I do now?
2. What is planned next this week?
3. What did I just do?

The redesign keeps the Coach card as the single primary action surface, moves
the rest-of-week plan onto Home, replaces Recent Workouts with a compact What You
Did summary, and routes detailed history through one View more link. The old Why
This Today screen is removed; its useful pieces now live in Home, Coach
Preferences, and Coach Insights.

## Apple HIG Fit

Apple's tab-bar guidance frames tabs as top-level sections. This app already has
Workout, Tests, and Progress as top-level destinations, so Home should not add
more pseudo-tabs inside the first screen.

Apple's disclosure-control guidance is a good fit for details like citations and
science explanations, but not for duplicating a second overview page that repeats
weekly balance and recent training facts. The new Home exposes summary content
directly and uses separate destinations only for full History, full Plan, and
full Coach Insights.

Apple's toolbar guidance supports a top-right control for frequently used
commands. Coach Preferences is now a small control in the Coach card header
because it configures that card's recommendation, while the existing app Settings
gear remains the app-wide settings entry.

## Fitness App Pattern Check

Current major fitness apps consistently optimize the first screen around one
dominant user intent:

- Strava emphasizes recording activity, the activity feed/training log, and
  progress insights.
- Nike Training Club and Nike Run Club emphasize a training plan or guided
  workout as the next action.
- Fitbod emphasizes a personalized workout plan that adapts to the user's edits,
  history, goals, and equipment.
- Strong and Hevy emphasize fast logging and detailed history/progress as the
  follow-up surface.

The useful pattern is not copying a competitor layout. It is reducing the first
screen to a clear next action, keeping plan context nearby, and sending detail
work to predictable full screens.

## User Feedback Fit

The repo's field-testing notes repeatedly push Home away from a dashboard and
toward a short action path. The 2026-06-06 notes say Home should be
action-oriented, should not mirror Apple Health, and should move detailed stats
and history behind clear destinations. The 2026-06-15 Coach-home plan says the
first screen should lead with one Coach card plus manual Start and Log actions,
with nothing else competing above the fold.

This redesign follows that feedback by removing duplicate weekly and recent
history surfaces from Home, keeping the Coach recommendation as the dominant
action, and making plan, insights, preferences, and history predictable
destinations instead of parallel overview screens.

## Implemented IA

- Coach card: recommendation, start/complete/add-on state, Coach Preferences,
  top insight, and More insights.
- Home middle: quick actions, then Planned (rest of week) with a Your plan link.
- Home bottom: What you did with a View more link to History.
- Your Plan: weekly progress and next-week planning, without duplicating the
  rest-of-week section already shown on Home.
- Coach Insights: dedicated full insights list with the existing citation detail.

## Sources

- Apple HIG, Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Apple HIG, Disclosure controls: https://developer.apple.com/design/human-interface-guidelines/disclosure-controls
- Apple HIG, Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Strava App Store metadata: https://apps.apple.com/us/app/strava-run-bike-walk/id426826309
- Nike Training Club App Store metadata: https://apps.apple.com/us/app/nike-training-club/id301521403
- Fitbod App Store metadata: https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543
- Strong App Store metadata: https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577
- Hevy App Store metadata: https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350
- Field-testing note, action-oriented Home: `plans/field-testing/2026-06-06/00-overview.md`
- Field-testing IA note: `plans/field-testing/2026-06-06/01-navigation-and-home.md`
- Coach-driven Home plan: `plans/strength-pivot/2026-06-15/05-coach-driven-home.md`
