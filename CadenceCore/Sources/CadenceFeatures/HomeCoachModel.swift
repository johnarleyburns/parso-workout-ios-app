import Foundation
import CadenceCore

/// Home's coach pipeline logic, lifted out of `HomeView` (test-pyramid Phase 3).
///
/// The star here is `Signature` — the equatable cache key that gates the whole
/// coach recomputation. Home runs the expensive pipeline (facts → decision → plan
/// optimization → insights) *once* into a cached snapshot via `.task(id:)`, keyed
/// on this signature, so per-set churn never re-runs it. That cache-invalidation
/// rule is correctness-critical and previously had no test; it does now.
public enum HomeCoachModel {

    /// Coarse cache key: history *counts* + a refresh token + coach-relevant
    /// settings — deliberately NOT per-set session content, so logging a set (which
    /// mutates a session but changes no count and bumps no token) never re-runs the
    /// pipeline. The token is bumped on workout complete / log / ingest / delete /
    /// day-change; counts catch create/delete; settings catch preference edits.
    public struct Signature: Equatable {
        public var token: UUID
        public var sessionCount: Int
        public var cardioCount: Int
        public var assessmentCount: Int
        public var goal: TrainingGoal
        public var experience: ExperienceLevel
        public var formula: OneRepMaxFormula
        public var schedule: CoachSchedulePreferences
        public var profile: CoachPreferenceProfile
        public var painToday: Bool

        public init(token: UUID, sessionCount: Int, cardioCount: Int, assessmentCount: Int,
                    goal: TrainingGoal, experience: ExperienceLevel, formula: OneRepMaxFormula,
                    schedule: CoachSchedulePreferences, profile: CoachPreferenceProfile,
                    painToday: Bool) {
            self.token = token
            self.sessionCount = sessionCount
            self.cardioCount = cardioCount
            self.assessmentCount = assessmentCount
            self.goal = goal
            self.experience = experience
            self.formula = formula
            self.schedule = schedule
            self.profile = profile
            self.painToday = painToday
        }
    }

    /// Whether today's readiness entry flags pain or illness — a coach input.
    public static func painToday(readiness: [ReadinessEntry],
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        return readiness
            .first { calendar.startOfDay(for: $0.date) == today }?
            .hasPainOrIllnessConcern ?? false
    }

    /// Builds the coach cache key from the view's `@Query` results + settings.
    public static func signature(token: UUID,
                                 sessions: [WorkoutSession],
                                 cardio: [CardioWorkout],
                                 assessments: [Assessment],
                                 readiness: [ReadinessEntry],
                                 goal: TrainingGoal,
                                 experience: ExperienceLevel,
                                 formula: OneRepMaxFormula,
                                 schedule: CoachSchedulePreferences,
                                 profile: CoachPreferenceProfile,
                                 now: Date = Date()) -> Signature {
        Signature(token: token,
                  sessionCount: sessions.count,
                  cardioCount: cardio.count,
                  assessmentCount: assessments.count,
                  goal: goal,
                  experience: experience,
                  formula: formula,
                  schedule: schedule,
                  profile: profile,
                  painToday: painToday(readiness: readiness, now: now))
    }

    /// Runs the full pure coach pipeline once, deriving `hasPainToday` from readiness.
    public static func snapshot(sessions: [WorkoutSession],
                                cardio: [CardioWorkout],
                                assessments: [Assessment],
                                readiness: [ReadinessEntry],
                                goal: TrainingGoal,
                                experience: ExperienceLevel,
                                formula: OneRepMaxFormula,
                                schedule: CoachSchedulePreferences,
                                profile: CoachPreferenceProfile,
                                now: Date = Date()) -> CoachSnapshot {
        CoachSnapshotBuilder.build(
            sessions: sessions,
            cardio: cardio,
            assessments: assessments,
            hasPainToday: painToday(readiness: readiness, now: now),
            goal: goal,
            experience: experience,
            formula: formula,
            schedulePreferences: schedule,
            profile: profile,
            now: now)
    }

    /// The current fitness-test recommendation (issue 11), gated to ≤1/week and
    /// honoring per-kind "not right now" snoozes. nil when the coach is hidden.
    public static func testRecommendation(coachHidden: Bool,
                                          assessments: [Assessment],
                                          lastRecommendedAt: Date?,
                                          snoozedUntil: [String: Date],
                                          now: Date = Date()) -> TestRecommendation? {
        guard !coachHidden else { return nil }
        let summaries = AssessmentMath.summaries(from: assessments)
        let inputs = CoachTestRecommendationEngine.Inputs(
            summaries: summaries,
            lastRecommendedAt: lastRecommendedAt,
            snoozedUntil: snoozedUntil,
            now: now)
        return CoachTestRecommendationEngine.recommendation(inputs)
    }
}
