import Foundation

public enum CoachSessionKind: String, Sendable, Equatable, CaseIterable, Codable {
    case strength
    case easyAerobic
    case moderateAerobic
    case vo2Intervals
    case recovery
    case rest
    case assessment
}

public struct CoachSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: CoachSessionKind
    public let title: String
    public let subtitle: String
    public let durationMinutes: Int?
    public let exercises: [RecommendedExercise]?
    public let modality: AerobicModality?
    public let intensity: AerobicIntensity?
    public let trainingLoadTags: [String]
    public let citationIds: [String]
    public let launchPayload: LaunchPayload
    public let systemsTrained: [TrainingSystem]
    public let evidenceCategory: EvidenceClaimCategory?

    public struct RecommendedExercise: Sendable, Equatable {
        public let name: String
        public let primaryMuscles: [String]
        public let sets: Int?
        public let repsLow: Int?
        public let repsHigh: Int?
        public let loadKg: Double?
        public let rir: Int?

        public init(name: String, primaryMuscles: [String] = [], sets: Int? = nil,
                    repsLow: Int? = nil, repsHigh: Int? = nil, loadKg: Double? = nil, rir: Int? = nil) {
            self.name = name; self.primaryMuscles = primaryMuscles
            self.sets = sets; self.repsLow = repsLow; self.repsHigh = repsHigh
            self.loadKg = loadKg; self.rir = rir
        }
    }

    public enum AerobicModality: String, Sendable, Equatable {
        case walk, run, cycle, swim, row, boxing, other
    }

    public enum AerobicIntensity: String, Sendable, Equatable {
        case easy, moderate, vigorous
    }

    public enum LaunchPayload: Sendable, Equatable {
        case strengthPlan(String)
        case cardio(type: String, durationMinutes: Int?)
        case recovery
        case rest
        case assessment

        public var isEmpty: Bool {
            if case .rest = self { return true }
            return false
        }
    }

    public init(id: String, kind: CoachSessionKind, title: String, subtitle: String = "",
                durationMinutes: Int? = nil, exercises: [RecommendedExercise]? = nil,
                modality: AerobicModality? = nil, intensity: AerobicIntensity? = nil,
                trainingLoadTags: [String] = [], citationIds: [String] = [],
                launchPayload: LaunchPayload = .rest,
                systemsTrained: [TrainingSystem] = [],
                evidenceCategory: EvidenceClaimCategory? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.durationMinutes = durationMinutes
        self.exercises = exercises
        self.modality = modality
        self.intensity = intensity
        self.trainingLoadTags = trainingLoadTags
        self.citationIds = citationIds
        self.launchPayload = launchPayload
        self.systemsTrained = systemsTrained
        self.evidenceCategory = evidenceCategory
    }
}

extension CoachSession {

    public static func candidates(for facts: CoachFacts,
                                  schedulePreferences: CoachSchedulePreferences = .default,
                                  anaerobicOptIn: Bool = false) -> [CoachSession] {
        let balance = facts.weeklyBalance
        let goal = facts.goal
        let range = goal.repRange
        let rir = goal.targetRIR

        var candidates: [CoachSession] = []

        // The weekly strength floor is the user's own target (was hardcoded 2).
        let strengthFloor = schedulePreferences.strengthDaysPerWeek
        let aerobicFloor = 150.0

        let strengthNeeded = balance.strengthDays < strengthFloor
        // Once the weekly strength target is met, NO strength is offered (general,
        // beginner, or reduced-load) — the user's expectation, and two-a-days must
        // not override it.
        let strengthCapMet = balance.strengthDays >= strengthFloor
        let aerobicNeeded = balance.moderateEquivalentMinutes < aerobicFloor
        let allBodyPartsCovered = balance.bodyPartsTrained.count >= 5

        // Always offer strength if something needs training and is eligible
        if strengthNeeded || facts.events.isEmpty {
            let exercises = buildStrengthExercises(facts: facts)
            candidates.append(CoachSession(
                id: "strength.general",
                kind: .strength,
                title: strengthNeeded ? "Strength session" : "Full-body session",
                subtitle: "\(range.lowerBound)–\(range.upperBound) reps · ≤\(rir) RIR",
                durationMinutes: 45,
                exercises: exercises,
                trainingLoadTags: ["strength"],
                citationIds: ["schoenfeld2021", "ekelundActivityMortality2016"],
                launchPayload: .strengthPlan("fullBody")
            ))
        }

        // Full-body A/B for beginners
        if facts.events.count < 5 && facts.experience == .beginner && !strengthCapMet {
            let aExercises = generateBeginnerA(facts: facts)
            candidates.append(CoachSession(
                id: "strength.beginnerA",
                kind: .strength,
                title: "Full-body A",
                subtitle: "2–3 sets · Squat, push, pull, carry",
                durationMinutes: 40,
                exercises: aExercises,
                trainingLoadTags: ["strength", "beginner"],
                citationIds: ["schoenfeld2021"],
                launchPayload: .strengthPlan("beginnerA")
            ))
            let bExercises = generateBeginnerB(facts: facts)
            candidates.append(CoachSession(
                id: "strength.beginnerB",
                kind: .strength,
                title: "Full-body B",
                subtitle: "2–3 sets · Hinge, press, pull, leg",
                durationMinutes: 40,
                exercises: bExercises,
                trainingLoadTags: ["strength", "beginner"],
                citationIds: ["schoenfeld2021"],
                launchPayload: .strengthPlan("beginnerB")
            ))
        }

        // Easy aerobic
        candidates.append(CoachSession(
            id: "aerobic.easyWalk",
            kind: .easyAerobic,
            title: "Easy walk",
            subtitle: "20–30 min · conversational pace",
            durationMinutes: 25,
            modality: .walk,
            intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "walk", durationMinutes: 25)
        ))

        candidates.append(CoachSession(
            id: "aerobic.easyCycle",
            kind: .easyAerobic,
            title: "Easy cycle",
            subtitle: "20–30 min · light effort",
            durationMinutes: 25,
            modality: .cycle,
            intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "cycle", durationMinutes: 25)
        ))

        candidates.append(CoachSession(
            id: "aerobic.easySwim",
            kind: .easyAerobic,
            title: "Easy swim",
            subtitle: "20–30 min · steady pace",
            durationMinutes: 25,
            modality: .swim,
            intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "swim", durationMinutes: 25)
        ))

        candidates.append(CoachSession(
            id: "aerobic.easyRow",
            kind: .easyAerobic,
            title: "Easy row",
            subtitle: "20–30 min · light pull",
            durationMinutes: 25,
            modality: .row,
            intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "rowing", durationMinutes: 25)
        ))

        // Moderate aerobic (always offer as alternatives, not just when behind)
        candidates.append(CoachSession(
            id: "aerobic.moderateWalk",
            kind: .moderateAerobic,
            title: "Brisk walk",
            subtitle: "30–40 min · steady effort",
            durationMinutes: 35,
            modality: .walk,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "walk", durationMinutes: 35)
        ))
        candidates.append(CoachSession(
            id: "aerobic.moderateRun",
            kind: .moderateAerobic,
            title: "Steady run",
            subtitle: "20–30 min · comfortable pace",
            durationMinutes: 25,
            modality: .run,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "highImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "run", durationMinutes: 25)
        ))
        candidates.append(CoachSession(
            id: "aerobic.moderateCycle",
            kind: .moderateAerobic,
            title: "Steady cycle",
            subtitle: "30–40 min · steady effort",
            durationMinutes: 35,
            modality: .cycle,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "cycle", durationMinutes: 35)
        ))
        candidates.append(CoachSession(
            id: "aerobic.moderateSwim",
            kind: .moderateAerobic,
            title: "Steady swim",
            subtitle: "25–35 min · continuous",
            durationMinutes: 30,
            modality: .swim,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "swim", durationMinutes: 30)
        ))
        candidates.append(CoachSession(
            id: "aerobic.moderateRow",
            kind: .moderateAerobic,
            title: "Row",
            subtitle: "25–35 min · steady pull",
            durationMinutes: 30,
            modality: .row,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "lowImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "rowing", durationMinutes: 30)
        ))
        candidates.append(CoachSession(
            id: "aerobic.moderateBoxing",
            kind: .moderateAerobic,
            title: "Boxing conditioning",
            subtitle: "20–30 min · moderate rounds",
            durationMinutes: 25,
            modality: .boxing,
            intensity: .moderate,
            trainingLoadTags: ["aerobic", "moderate", "highImpact"],
            citationIds: ["ekelundActivityMortality2016"],
            launchPayload: .cardio(type: "boxing", durationMinutes: 25)
        ))

        // VO2 intervals (for users with capacity)
        if balance.strengthDays >= 2 && balance.moderateEquivalentMinutes >= 75 {
            candidates.append(CoachSession(
                id: "aerobic.vo2Intervals",
                kind: .vo2Intervals,
                title: "VO₂max intervals",
                subtitle: "4×4 min hard / 3 min easy",
                durationMinutes: 35,
                modality: .run,
                intensity: .vigorous,
                trainingLoadTags: ["aerobic", "hard", "highImpact"],
                citationIds: ["crowleyVO2Intensity2022", "poonHIIT2024"],
                launchPayload: .cardio(type: "hiit", durationMinutes: 35)
            ))
        }

        // Recovery / rest
        candidates.append(CoachSession(
            id: "recovery.stretch",
            kind: .recovery,
            title: "Recovery: stretch or mobility",
            subtitle: "10–15 min · gentle movement",
            durationMinutes: 12,
            trainingLoadTags: ["recovery", "flexibility"],
            citationIds: ["konradStretchROM2024", "behmStretching2016"],
            launchPayload: .recovery
        ))

        candidates.append(CoachSession(
            id: "rest.full",
            kind: .rest,
            title: "Rest day",
            subtitle: "Recovery is training too",
            trainingLoadTags: ["rest"],
            citationIds: ["meeusenOvertraining2013"],
            launchPayload: .rest
        ))

        // Tag every base candidate with the training systems it loads and the
        // claim-specific evidence category it is allowed to cite (P4).
        candidates = candidates.map { c in
            switch c.kind {
            case .strength:
                return c.withEvidence(.strengthIntensity, systems: [.maximalStrength, .hypertrophy],
                                      citations: evidencePool(.strengthIntensity))
            case .easyAerobic, .moderateAerobic:
                return c.withEvidence(.aerobicBase, systems: [.aerobicBase],
                                      citations: evidencePool(.aerobicBase))
            case .vo2Intervals:
                return c.withEvidence(.vo2Training, systems: [.vo2max],
                                      citations: evidencePool(.vo2Training))
            case .recovery:
                return c.withEvidence(.flexibilityROM, systems: [.flexibility],
                                      citations: evidencePool(.flexibilityROM))
            case .rest:
                return c.withEvidence(nil, systems: [.recovery])
            case .assessment:
                return c.withEvidence(.fieldTestValidity, systems: [],
                                      citations: evidencePool(.fieldTestValidity))
            }
        }

        // Threshold tempo — only once an aerobic base is established (so it never
        // pre-empts base-building or appears for brand-new users).
        if balance.moderateEquivalentMinutes >= 90 {
            candidates.append(CoachSession(
                id: "aerobic.thresholdTempo",
                kind: .moderateAerobic,
                title: "Threshold tempo",
                subtitle: "20–30 min · comfortably hard (~85% HRmax)",
                durationMinutes: 25,
                modality: .run,
                intensity: .vigorous,
                trainingLoadTags: ["aerobic", "hard", "highImpact", "threshold"],
                citationIds: evidencePool(.thresholdTraining),
                launchPayload: .cardio(type: "tempo", durationMinutes: 25),
                systemsTrained: [.threshold],
                evidenceCategory: .thresholdTraining
            ))
        }

        // Anaerobic intervals — opt-in only; never auto-prescribed (P4 safety rule).
        if anaerobicOptIn {
            candidates.append(CoachSession(
                id: "aerobic.anaerobicIntervals",
                kind: .vo2Intervals,
                title: "Anaerobic intervals",
                subtitle: "Short, near-maximal efforts · long recoveries",
                durationMinutes: 20,
                modality: .run,
                intensity: .vigorous,
                trainingLoadTags: ["aerobic", "hard", "highImpact", "anaerobic"],
                citationIds: evidencePool(.anaerobicTraining),
                launchPayload: .cardio(type: "hiit", durationMinutes: 20),
                systemsTrained: [.anaerobicPower],
                evidenceCategory: .anaerobicTraining
            ))
        }

        // Reduced-load strength — surfaced when an acute load spike is flagged or a
        // poor readiness check-in is logged, so the user can keep training lighter.
        let loadSpiked = facts.loadSpikeFlags.contains { $0.ratio >= 1.3 }
        let readinessPoor = facts.readiness?.isPoor == true
        if (loadSpiked || readinessPoor) && !facts.events.isEmpty && !strengthCapMet {
            let exercises = buildStrengthExercises(facts: facts).map {
                RecommendedExercise(name: $0.name, primaryMuscles: $0.primaryMuscles,
                                    sets: max(2, ($0.sets ?? 3) - 1),
                                    repsLow: $0.repsLow, repsHigh: $0.repsHigh,
                                    loadKg: nil, rir: (($0.rir ?? rir) + 2))
            }
            candidates.append(CoachSession(
                id: "strength.reducedLoad",
                kind: .strength,
                title: "Lighter strength session",
                subtitle: "Same lifts · lower load · 2+ extra RIR",
                durationMinutes: 35,
                exercises: exercises,
                trainingLoadTags: ["strength", "reducedLoad"],
                citationIds: evidencePool(.recoveryMonitoring),
                launchPayload: .strengthPlan("fullBody"),
                systemsTrained: [.maximalStrength, .hypertrophy],
                evidenceCategory: .recoveryMonitoring
            ))
        }

        // Assessment prompt — when an actively-trained system has no fresh baseline,
        // so prescriptions stay grounded in measured fitness.
        if !facts.events.isEmpty {
            let trainedSystems = facts.systemLoads.filter { $0.value.trailing28dExposures > 0 }.keys
            if let missing = trainedSystems.first(where: { sys in
                facts.assessmentCoverage[sys].map { !$0.hasBaseline } ?? false
            }) {
                candidates.append(CoachSession(
                    id: "assessment.baseline",
                    kind: .assessment,
                    title: "Establish a baseline",
                    subtitle: "A quick \(missing.displayName) test sharpens every recommendation",
                    durationMinutes: 15,
                    citationIds: evidencePool(.fieldTestValidity),
                    launchPayload: .assessment,
                    systemsTrained: [missing],
                    evidenceCategory: .fieldTestValidity
                ))
            }
        }

        return candidates
    }

    private static func evidencePool(_ category: EvidenceClaimCategory) -> [String] {
        CitationRegistry.citationPool(for: category).citationIds
    }

    func withEvidence(_ category: EvidenceClaimCategory?, systems: [TrainingSystem],
                      citations: [String]? = nil) -> CoachSession {
        CoachSession(
            id: id, kind: kind, title: title, subtitle: subtitle,
            durationMinutes: durationMinutes, exercises: exercises,
            modality: modality, intensity: intensity,
            trainingLoadTags: trainingLoadTags,
            citationIds: citations ?? citationIds,
            launchPayload: launchPayload,
            systemsTrained: systems, evidenceCategory: category)
    }

    private static func buildStrengthExercises(facts: CoachFacts) -> [RecommendedExercise] {
        let goal = facts.goal
        let range = goal.repRange
        let sets = goal == .strength ? 3 : 3

        let preferred = mostTrainedExercises(facts: facts)

        var exercises: [RecommendedExercise] = []
        let patterns: [(MovementPattern, String)] = [
            (.squat, "Back Squat"),
            (.horizontalPush, "Bench Press"),
            (.horizontalPull, "Barbell Row"),
            (.hinge, "Romanian Deadlift"),
            (.verticalPush, "Overhead Press"),
            (.verticalPull, "Pull-Up"),
        ]

        var used = Set<MovementPattern>()
        for (pattern, fallback) in patterns {
            guard used.count < 4 else { break }
            let name = preferred[pattern] ?? fallback
            guard !used.contains(pattern) else { continue }
            used.insert(pattern)
            exercises.append(RecommendedExercise(
                name: name, sets: sets,
                repsLow: range.lowerBound, repsHigh: range.upperBound,
                loadKg: nil, rir: goal.targetRIR
            ))
        }

        return exercises
    }

    private static func generateBeginnerA(facts: CoachFacts) -> [RecommendedExercise] {
        let preferred = mostTrainedExercises(facts: facts)
        return [
            RecommendedExercise(name: preferred[.squat] ?? "Back Squat", sets: 3, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.horizontalPush] ?? "Bench Press", sets: 3, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.horizontalPull] ?? "Barbell Row", sets: 3, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.carry] ?? "Farmer Carry", sets: 2, repsLow: 1, repsHigh: 1, rir: 3),
        ]
    }

    private static func generateBeginnerB(facts: CoachFacts) -> [RecommendedExercise] {
        let preferred = mostTrainedExercises(facts: facts)
        return [
            RecommendedExercise(name: preferred[.hinge] ?? "Romanian Deadlift", sets: 2, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.verticalPush] ?? "Overhead Press", sets: 3, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.verticalPull] ?? "Pull-Up", sets: 3, repsLow: 6, repsHigh: 10, rir: 3),
            RecommendedExercise(name: preferred[.core] ?? "Plank", sets: 2, repsLow: 1, repsHigh: 1, rir: 3),
        ]
    }

    public static func mostTrainedExercises(facts: CoachFacts) -> [MovementPattern: String] {
        var counts: [String: (count: Int, pattern: MovementPattern)] = [:]
        for event in facts.rolling28dCompletedEvents {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            for ex in d.exercises {
                let name = ex.exerciseName
                for p in ex.patterns {
                    let current = counts[name]
                    if current == nil || ex.hardSetCount > current!.count {
                        counts[name] = (ex.hardSetCount, p)
                    }
                }
            }
        }

        var best: [MovementPattern: (name: String, count: Int)] = [:]
        for (name, info) in counts {
            if let existing = best[info.pattern] {
                if info.count > existing.count {
                    best[info.pattern] = (name, info.count)
                }
            } else {
                best[info.pattern] = (name, info.count)
            }
        }

        return best.mapValues { $0.name }
    }

    public var isHard: Bool {
        switch kind {
        case .strength, .vo2Intervals: return true
        case .moderateAerobic: return intensity == .vigorous
        default: return false
        }
    }

    public var isAerobic: Bool {
        switch kind {
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return true
        default: return false
        }
    }
}
