import SwiftUI
import CadenceCore
import CadenceFeatures

struct ActiveIntervalSession {
    let plan: IntervalPlan
    let kind: String
}

extension WatchRootView {
    func cardioType(from raw: String?) -> CardioType {
        guard let raw, let type = CardioType(rawValue: raw) else { return .other }
        return type
    }

    var cardioTypes: [CardioType] {
        [.run, .walk, .cycle, .swim, .hiit, .boxing, .rowing, .other]
    }

    var sessionOwnership: WatchSessionOwnership.Verdict {
        watchManager.sessionOwnership(hasResumableStrength: resumableStrengthSession != nil)
    }

    var needsHealthAccess: Bool { !watchManager.workoutShareAuthorized && !watchManager.isActive }

    var hero: WatchTodayHero {
        let resume = resumableStrengthSession.map { session in
            WatchTodayHeroBuilder.ResumeInput(
                title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                startedAt: session.date,
                exercises: Self.loggedPerExercise(session),
                plannedSets: Dictionary(session.plannedPrescriptions.map {
                    ($0.exerciseName, $0.sets.filter { $0.kind != .warmup }.count) }, uniquingKeysWith: { a, _ in a }))
        }
        return WatchTodayHeroBuilder.make(
            resume: resume,
            plan: watchManager.todayPlan,
            synced: watchManager.lastPhoneSyncAt != nil)
    }

    static func loggedPerExercise(_ session: WorkoutSession) -> [(name: String, sets: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for set in session.orderedSets where !set.isWarmup {
            let name = set.exercise?.name ?? ""
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    func intervalSetupModel(kind: String) -> IntervalSetupModel {
        let isHIITOrBoxing = kind.lowercased() == "hiit" || kind.lowercased() == "boxing"
        let syncedWarmup = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.warmupMinutes * 60)
        let syncedCooldown = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.cooldownMinutes * 60)
        return IntervalSetupModel(kind: kind, warmupSeconds: syncedWarmup, cooldownSeconds: syncedCooldown)
    }
}
