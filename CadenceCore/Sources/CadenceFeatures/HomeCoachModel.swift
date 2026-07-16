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
        /// Cardio intensity classification is age-anchored (Tanaka HRmax), so an
        /// age edit must invalidate the snapshot. Additive/defaulted.
        public var userAge: Int?

        public init(token: UUID, sessionCount: Int, cardioCount: Int, assessmentCount: Int,
                    goal: TrainingGoal, experience: ExperienceLevel, formula: OneRepMaxFormula,
                    schedule: CoachSchedulePreferences, profile: CoachPreferenceProfile,
                    painToday: Bool, userAge: Int? = nil) {
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
            self.userAge = userAge
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
                                 userAge: Int? = nil,
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
                  painToday: painToday(readiness: readiness, now: now),
                  userAge: userAge)
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
                                passiveSamples: [PassiveReadinessSample] = [],
                                userAge: Int? = nil,
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
            readinessEntry: latestReadiness(readiness, now: now),
            passiveSamples: passiveSamples,
            userAge: userAge,
            now: now)
    }

    /// The most recent readiness check-in on or before `now`, if any — the one the
    /// coach fuses with passive signals.
    static func latestReadiness(_ entries: [ReadinessEntry], now: Date) -> ReadinessEntry? {
        entries.filter { $0.date <= now }.max { $0.date < $1.date }
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

    /// Whether Home should render the prominent "Unlock the Coach" CTA.
    ///
    /// Wraps `CoachUpsellPolicy` so the entitlement is threaded through exactly
    /// once, in tested code, rather than at a SwiftUI call site — which is how a
    /// hardcoded `isPro: false` once shipped an advertisement to paying users.
    public static func upsellCTAVisible(entitlement: ProEntitlement,
                                        lastShown: Date?,
                                        now: Date = Date()) -> Bool {
        CoachUpsellPolicy.shouldShowCTA(isPro: entitlement.isPro,
                                        lastShown: lastShown,
                                        now: now)
    }
}
