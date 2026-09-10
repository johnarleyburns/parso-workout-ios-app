import Foundation

// MARK: - Unified-plan coach output

/// The typed operations exposed by the unified-plan coach boundary. The engine
/// proposes changes; callers decide whether to apply them.
public enum UnifiedPlanCoachOperation: String, Codable, Sendable, Equatable {
    case generate
    case critique
    case progress
    case substitute
    case insights
    case autoregulate
}

public enum UnifiedPlanCoachSeverity: String, Codable, Sendable, Equatable, Comparable {
    case info
    case attention
    case warning

    private var rank: Int {
        switch self {
        case .info: return 0
        case .attention: return 1
        case .warning: return 2
        }
    }

    public static func < (lhs: UnifiedPlanCoachSeverity, rhs: UnifiedPlanCoachSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct UnifiedPlanCoachCritique: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case volume
        case balance
        case movementCoverage
        case intensity
        case rest
        case progression
        case recovery
        case safety
    }

    public let id: String
    public let kind: Kind
    public let severity: UnifiedPlanCoachSeverity
    public let title: String
    public let detail: String
    public let suggestedFix: String?
    public let citationIDs: [String]
    public let confidence: EvidenceConfidence

    public init(id: String, kind: Kind, severity: UnifiedPlanCoachSeverity,
                title: String, detail: String, suggestedFix: String? = nil,
                citationIDs: [String], confidence: EvidenceConfidence) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestedFix = suggestedFix
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

public struct UnifiedPlanProgressionProposal: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: UUID
    public let itemID: UUID
    public let setID: UUID
    public let exerciseKey: ExerciseKey
    public let current: PrescribedSet
    public let proposed: PrescribedSet
    public let reason: String
    public let citationIDs: [String]
    public let confidence: EvidenceConfidence

    public init(id: String, sessionID: UUID, itemID: UUID, setID: UUID,
                exerciseKey: ExerciseKey, current: PrescribedSet,
                proposed: PrescribedSet, reason: String,
                citationIDs: [String], confidence: EvidenceConfidence) {
        self.id = id
        self.sessionID = sessionID
        self.itemID = itemID
        self.setID = setID
        self.exerciseKey = exerciseKey
        self.current = current
        self.proposed = proposed
        self.reason = reason
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

public struct UnifiedPlanSubstitution: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: UUID
    public let itemID: UUID
    public let sourceExerciseKey: ExerciseKey
    public let candidateExerciseKey: ExerciseKey
    public let candidateName: String
    public let score: Double
    public let preserves: String
    public let tradeoff: String?
    public let citationIDs: [String]
    public let confidence: EvidenceConfidence

    public init(id: String, sessionID: UUID, itemID: UUID,
                sourceExerciseKey: ExerciseKey, candidateExerciseKey: ExerciseKey,
                candidateName: String, score: Double, preserves: String,
                tradeoff: String? = nil, citationIDs: [String],
                confidence: EvidenceConfidence) {
        self.id = id
        self.sessionID = sessionID
        self.itemID = itemID
        self.sourceExerciseKey = sourceExerciseKey
        self.candidateExerciseKey = candidateExerciseKey
        self.candidateName = candidateName
        self.score = score
        self.preserves = preserves
        self.tradeoff = tradeoff
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

public enum UnifiedPlanAutoregulationDirection: String, Codable, Sendable, Equatable {
    case hold
    case reduceLoad
    case reduceVolume
    case deferDecision
}

public struct UnifiedPlanAutoregulationProposal: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: UUID
    public let itemID: UUID
    public let direction: UnifiedPlanAutoregulationDirection
    public let loadAdjustmentPercent: Double?
    public let workingSetAdjustment: Int?
    public let detail: String
    public let citationIDs: [String]
    public let confidence: EvidenceConfidence

    public init(id: String, sessionID: UUID, itemID: UUID,
                direction: UnifiedPlanAutoregulationDirection,
                loadAdjustmentPercent: Double? = nil,
                workingSetAdjustment: Int? = nil, detail: String,
                citationIDs: [String], confidence: EvidenceConfidence) {
        self.id = id
        self.sessionID = sessionID
        self.itemID = itemID
        self.direction = direction
        self.loadAdjustmentPercent = loadAdjustmentPercent
        self.workingSetAdjustment = workingSetAdjustment
        self.detail = detail
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

public struct UnifiedPlanCoachInsight: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let severity: UnifiedPlanCoachSeverity
    public let title: String
    public let message: String
    public let detail: String
    public let citationIDs: [String]
    public let confidence: EvidenceConfidence

    public init(id: String, severity: UnifiedPlanCoachSeverity, title: String,
                message: String, detail: String, citationIDs: [String],
                confidence: EvidenceConfidence) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.detail = detail
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

public struct UnifiedPlanCoachReport: Codable, Sendable, Equatable {
    public let operation: UnifiedPlanCoachOperation
    public let plan: Plan
    public let rationale: EngineRationale
    public let engineEvaluation: UnifiedPlanEngineEvaluation?
    public let critique: [UnifiedPlanCoachCritique]
    public let progression: [UnifiedPlanProgressionProposal]
    public let substitutions: [UnifiedPlanSubstitution]
    public let autoregulation: [UnifiedPlanAutoregulationProposal]
    public let insights: [UnifiedPlanCoachInsight]

    public init(operation: UnifiedPlanCoachOperation, plan: Plan,
                rationale: EngineRationale,
                engineEvaluation: UnifiedPlanEngineEvaluation? = nil,
                critique: [UnifiedPlanCoachCritique] = [],
                progression: [UnifiedPlanProgressionProposal] = [],
                substitutions: [UnifiedPlanSubstitution] = [],
                autoregulation: [UnifiedPlanAutoregulationProposal] = [],
                insights: [UnifiedPlanCoachInsight] = []) {
        self.operation = operation
        self.plan = plan
        self.rationale = rationale
        self.engineEvaluation = engineEvaluation
        self.critique = critique
        self.progression = progression
        self.substitutions = substitutions
        self.autoregulation = autoregulation
        self.insights = insights
    }
}

public struct UnifiedPlanCoachRequest: Sendable {
    public let goal: TrainingGoal
    public let experience: ExperienceLevel
    public let schedulePreferences: CoachSchedulePreferences
    public let title: String
    public let referenceDate: Date
    public let trainingFacts: TrainingFacts?
    public let coachFacts: CoachFacts?

    public init(goal: TrainingGoal, experience: ExperienceLevel,
                schedulePreferences: CoachSchedulePreferences = .default,
                title: String = "Coach plan", referenceDate: Date = Date(),
                trainingFacts: TrainingFacts? = nil, coachFacts: CoachFacts? = nil) {
        self.goal = goal
        self.experience = experience
        self.schedulePreferences = schedulePreferences
        self.title = title
        self.referenceDate = referenceDate
        self.trainingFacts = trainingFacts
        self.coachFacts = coachFacts
    }
}

public enum UnifiedPlanCoachError: Error, Equatable, Sendable {
    case missingCoachFacts
    case invalidPlan(UnifiedPlanValidationError)
    case exerciseNotFound(ExerciseKey)
}

/// The Phase 2 plan-level adapter. Existing Coach/DB++ engines remain the
/// authorities for facts and exercise metadata; this type is the one stable
/// boundary that composes their outputs around the persisted unified `Plan`.
public enum UnifiedPlanCoachEngine {

    public static func generate(_ request: UnifiedPlanCoachRequest) throws -> UnifiedPlanCoachReport {
        guard let coachFacts = request.coachFacts else { throw UnifiedPlanCoachError.missingCoachFacts }
        let weekly = WeeklyPlan.generate(from: coachFacts,
                                         schedulePreferences: request.schedulePreferences)
        var plan = WeeklyPlanUnifiedBridge.plan(
            from: weekly,
            goal: request.goal,
            title: request.title)
        let rationale = generationRationale(request: request, plan: plan)
        plan.rationale = rationale
        plan.engineProvenance = UnifiedPlanDBPPBridge.provenance(for: plan)
        try plan.validate()
        let engineEvaluation = request.coachFacts.flatMap {
            UnifiedPlanDBPPBridge.evaluate(
                plan,
                experience: $0.experience,
                schedule: request.schedulePreferences)
        }
        return UnifiedPlanCoachReport(
            operation: .generate,
            plan: plan,
            rationale: rationale,
            engineEvaluation: engineEvaluation,
            critique: makeCritique(for: plan, trainingFacts: request.trainingFacts),
            autoregulation: autoregulate(for: plan, trainingFacts: request.trainingFacts,
                                         coachFacts: request.coachFacts),
            insights: insights(for: plan, trainingFacts: request.trainingFacts,
                               coachFacts: request.coachFacts))
    }

    public static func critique(for plan: Plan,
                                trainingFacts: TrainingFacts? = nil) throws -> [UnifiedPlanCoachCritique] {
        try plan.validate()
        return makeCritique(for: plan, trainingFacts: trainingFacts)
    }

    public static func progress(for plan: Plan,
                                trainingFacts: TrainingFacts) throws -> [UnifiedPlanProgressionProposal] {
        try plan.validate()
        return progression(for: plan, trainingFacts: trainingFacts)
    }

    public static func substitute(for plan: Plan, itemID: UUID,
                                  limit: Int = 5) throws -> [UnifiedPlanSubstitution] {
        try plan.validate()
        guard let located = locateStrengthItem(itemID, in: plan) else {
            throw UnifiedPlanCoachError.exerciseNotFound(ExerciseKey(raw: itemID.uuidString))
        }
        let source = try preparedTemplate(for: located.item.exerciseKey)
        let candidates = ExerciseLibrary.starter.map(preparedTemplate)
        return ExerciseSimilarity.rank(source: source, candidates: candidates,
                                       selectedType: .strength, limit: max(1, limit)).map {
            let candidateKey = ExerciseKey(raw: exerciseKey(for: $0.candidate))
            let direct = $0.candidate.direct.map(\.displayName).sorted().joined(separator: ", ")
            let overlap = Int((($0.directOverlap * 100).rounded()))
            return UnifiedPlanSubstitution(
                id: "substitute|\(itemID.uuidString)|\(candidateKey.raw)",
                sessionID: located.session.id,
                itemID: itemID,
                sourceExerciseKey: located.item.exerciseKey,
                candidateExerciseKey: candidateKey,
                candidateName: $0.candidate.name,
                score: $0.score,
                preserves: "Direct stimulus overlaps \(direct) (\(overlap)% direct overlap).",
                tradeoff: $0.candidate.equipment.map { "Equipment: \($0.displayName)" },
                citationIDs: ["schoenfeld2021", "pellandFractionalSets2024"],
                confidence: $0.directOverlap >= 0.5 ? .moderate : .limited)
        }
    }

    public static func apply(_ substitution: UnifiedPlanSubstitution,
                             to plan: Plan, at date: Date = Date()) throws -> Plan {
        try plan.validate()
        var copy = plan
        for weekIndex in copy.weeks.indices {
            for dayIndex in copy.weeks[weekIndex].days.indices {
                for sessionIndex in copy.weeks[weekIndex].days[dayIndex].sessions.indices {
                    var session = copy.weeks[weekIndex].days[dayIndex].sessions[sessionIndex]
                    guard let itemIndex = session.items.firstIndex(where: { $0.id == substitution.itemID }) else { continue }
                    guard case var .strength(item) = session.items[itemIndex], item.id == substitution.itemID else { continue }
                    guard item.exerciseKey == substitution.sourceExerciseKey else { continue }
                    item.alternateExerciseKey = substitution.sourceExerciseKey
                    item.exerciseKey = substitution.candidateExerciseKey
                    session.items[itemIndex] = .strength(item)
                    copy.weeks[weekIndex].days[dayIndex].sessions[sessionIndex] = session
                    copy.updatedAt = date
                    return copy
                }
            }
        }
        throw UnifiedPlanCoachError.exerciseNotFound(substitution.sourceExerciseKey)
    }

    public static func insights(for plan: Plan,
                               trainingFacts: TrainingFacts? = nil,
                               coachFacts: CoachFacts? = nil) -> [UnifiedPlanCoachInsight] {
        var output: [UnifiedPlanCoachInsight] = []
        let volume = plannedVolume(for: plan)
        for group in MuscleGroup.defaultTracked.sorted(by: { MuscleGroup.canonicalIndex($0) < MuscleGroup.canonicalIndex($1) }) {
            let planned = volume[group, default: 0]
            let actual = trainingFacts?.weeklySetsByGroup[group] ?? 0
            guard planned > 0 || actual > 0 else { continue }
            let bands = VolumeLandmarks.bands(for: group, experience: trainingFacts?.experience ?? .intermediate)
            if planned < bands.mev {
                output.append(UnifiedPlanCoachInsight(
                    id: "plan-volume-low|\(group.rawValue)", severity: .attention,
                    title: "\(group.displayName) is lightly planned",
                    message: "The plan provides \(Format.sets(planned)) sets against a \(Format.sets(bands.mev)) starting minimum.",
                    detail: "This is a planning signal, not a diagnosis. Add volume only if recovery and the user's goal support it.",
                    citationIDs: ["pellandDoseResponse2026", "pellandFractionalSets2024"],
                    confidence: .moderate))
            } else if planned >= bands.mrv {
                output.append(UnifiedPlanCoachInsight(
                    id: "plan-volume-high|\(group.rawValue)", severity: .warning,
                    title: "\(group.displayName) is near the recovery ceiling",
                    message: "The plan assigns \(Format.sets(planned)) sets, at or above the starting MRV band.",
                    detail: "Review exercise overlap and recovery before accepting this volume; the coach will not silently trim an authored plan.",
                    citationIDs: ["pellandDoseResponse2026", "drewFinchInjury2016"],
                    confidence: .limited))
            } else if actual > 0 && planned < actual * 0.75 {
                output.append(UnifiedPlanCoachInsight(
                    id: "plan-vs-history|\(group.rawValue)", severity: .info,
                    title: "\(group.displayName) is planned below recent work",
                    message: "Recent work is \(Format.sets(actual)) sets; this plan schedules \(Format.sets(planned)).",
                    detail: "That may be deliberate during a recovery week. Confirm the reduction matches the intended block.",
                    citationIDs: ["pellandDoseResponse2026", "rpeAutoregulation"],
                    confidence: .moderate))
            }
        }

        if let facts = trainingFacts {
            for (exercise, trend) in facts.e1RMTrendByExercise.sorted(by: { $0.key < $1.key }) {
                guard trend == .declining else { continue }
                output.append(UnifiedPlanCoachInsight(
                    id: "plan-trend-declining|\(exercise)", severity: .attention,
                    title: "\(exercise) needs a closer review",
                    message: "Estimated 1RM has declined across the comparison window.",
                    detail: "Coach proposes checking effort, recovery, and exercise fit before adding load.",
                    citationIDs: ["oneRMEstimation", "rpeAutoregulation"],
                    confidence: .moderate))
            }
        }

        if let coachFacts, coachFacts.readiness?.isPoor == true {
            output.append(UnifiedPlanCoachInsight(
                id: "plan-readiness-low", severity: .warning,
                title: "Readiness is low",
                message: "Keep the plan available, but review hard work before starting.",
                detail: "Self-reported readiness is treated as a soft modifier. The athlete remains in control and no session is changed automatically.",
                citationIDs: ["sawMonitoring2016", "halsonRecovery2014"],
                confidence: .limited))
        }
        return output.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.id < $1.id
        }
    }

    public static func autoregulate(for plan: Plan,
                                   trainingFacts: TrainingFacts?,
                                   coachFacts: CoachFacts? = nil) -> [UnifiedPlanAutoregulationProposal] {
        guard let facts = trainingFacts else { return [] }
        let poorReadiness = coachFacts?.readiness?.isPoor == true
        let hardRPE = facts.avgRPE.map { $0 >= 8.75 } ?? false
        guard poorReadiness || hardRPE else { return [] }
        let direction: UnifiedPlanAutoregulationDirection = poorReadiness ? .reduceVolume : .reduceLoad
        let detail = poorReadiness
            ? "Readiness is low; consider one fewer working set on hard items and reassess between sets."
            : "Recent working-set RPE is high; consider reducing the next loaded prescription modestly while keeping the effort target."
        return strengthItems(in: plan).map { located in
            UnifiedPlanAutoregulationProposal(
                id: "autoregulate|\(located.item.id.uuidString)",
                sessionID: located.session.id,
                itemID: located.item.id,
                direction: direction,
                loadAdjustmentPercent: poorReadiness ? nil : -0.05,
                workingSetAdjustment: poorReadiness ? -1 : nil,
                detail: detail,
                citationIDs: poorReadiness
                    ? ["sawMonitoring2016", "halsonRecovery2014"]
                    : ["rpeAutoregulation", "meeusenOvertraining2013"],
                confidence: .moderate)
        }
    }

    // MARK: Report helpers

    private static func generationRationale(request: UnifiedPlanCoachRequest,
                                            plan: Plan) -> EngineRationale {
        var decisions = [
            RationaleDecision(
                id: stableUUID("rationale|volume|\(plan.id.raw.uuidString)"),
                claim: "Weekly working-set volume is distributed across the scheduled sessions.",
                basis: "The coach uses experience-scaled starting landmarks and spreads volume rather than maximizing one session.",
                citationIDs: ["pellandDoseResponse2026", "pellandFractionalSets2024"],
                confidence: .moderate),
            RationaleDecision(
                id: stableUUID("rationale|effort|\(plan.id.raw.uuidString)"),
                claim: "Strength prescriptions use a goal-appropriate rep range and effort target.",
                basis: "Load and proximity to failure are complementary controls; the user can edit every prescription.",
                citationIDs: ["schoenfeld2021", "rpeAutoregulation"],
                confidence: .moderate),
            RationaleDecision(
                id: stableUUID("rationale|recovery|\(plan.id.raw.uuidString)"),
                claim: "Hard sessions are separated when recent history indicates recovery is still relevant.",
                basis: "Recovery is a soft planning constraint and never silently overrides an authored plan.",
                citationIDs: ["parejaBlancoRecovery2020", "meeusenOvertraining2013"],
                confidence: .moderate)
        ]
        if request.schedulePreferences.cardioDaysPerWeek > 0 {
            decisions.append(RationaleDecision(
                id: stableUUID("rationale|cardio|\(plan.id.raw.uuidString)"),
                claim: "Cardio sessions retain their modality and intensity prescription in the unified plan.",
                basis: "The plan keeps steady, interval, and open cardio distinct so execution can preserve the intended stimulus.",
                citationIDs: ["ekelundActivityMortality2016", "schumannConcurrent2022"],
                confidence: .moderate))
        }
        return EngineRationale(
            summary: "Generated for \(request.goal.displayName.lowercased()) with the current schedule and recent training state. Review the cited decisions, then edit or accept the draft.",
            knowledgeBaseVersion: CoachKnowledgeBaseLoader.current.version,
            decisions: decisions)
    }

    private static func makeCritique(for plan: Plan,
                                     trainingFacts: TrainingFacts?) -> [UnifiedPlanCoachCritique] {
        var findings: [UnifiedPlanCoachCritique] = []
        let volume = plannedVolume(for: plan)
        let patterns = plannedPatterns(for: plan)
        let tracked = Set(volume.keys).union(MuscleGroup.defaultTracked)
        for group in tracked.sorted(by: { MuscleGroup.canonicalIndex($0) < MuscleGroup.canonicalIndex($1) }) {
            let sets = volume[group, default: 0]
            let bands = VolumeLandmarks.bands(for: group,
                                              experience: trainingFacts?.experience ?? .intermediate)
            if sets > 0 && sets >= bands.mrv {
                findings.append(UnifiedPlanCoachCritique(
                    id: "critique|volume-high|\(group.rawValue)", kind: .volume,
                    severity: .warning, title: "\(group.displayName) volume is high",
                    detail: "The plan assigns \(Format.sets(sets)) working sets, at or above the starting MRV band of \(Format.sets(bands.mrv)).",
                    suggestedFix: "Reduce redundant sets or mark the week as an intentional overload block.",
                    citationIDs: ["pellandDoseResponse2026", "drewFinchInjury2016"], confidence: .limited))
            } else if sets > 0 && sets < bands.mev {
                findings.append(UnifiedPlanCoachCritique(
                    id: "critique|volume-low|\(group.rawValue)", kind: .volume,
                    severity: .attention, title: "\(group.displayName) volume is below the starting range",
                    detail: "The plan assigns \(Format.sets(sets)) working sets, below the starting MEV band of \(Format.sets(bands.mev)).",
                    suggestedFix: "Add a compatible movement or accept this as a maintenance/recovery choice.",
                    citationIDs: ["pellandDoseResponse2026", "pellandFractionalSets2024"], confidence: .moderate))
            }
        }

        let expectedPatterns: Set<MovementPattern> = [.squat, .hinge, .horizontalPush, .horizontalPull]
        let missing = expectedPatterns.subtracting(patterns)
        if !missing.isEmpty && !strengthItems(in: plan).isEmpty {
            let names = missing.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", ")
            findings.append(UnifiedPlanCoachCritique(
                id: "critique|patterns|\(names)", kind: .movementCoverage,
                severity: .attention, title: "Movement coverage is incomplete",
                detail: "The strength plan does not currently include: \(names.lowercased()).",
                suggestedFix: "Add or substitute a movement only if it fits the user's equipment and constraints.",
                citationIDs: ["schoenfeld2021", "ramosCampoSplit2024"], confidence: .moderate))
        }

        for located in strengthItems(in: plan) {
            let working = located.item.sets.filter { $0.kind != .warmup }
            if working.isEmpty {
                findings.append(UnifiedPlanCoachCritique(
                    id: "critique|no-working-set|\(located.item.id.uuidString)", kind: .intensity,
                    severity: .warning, title: "No working sets for \(located.item.exerciseKey.raw)",
                    detail: "This item cannot express a meaningful strength prescription without at least one working set.",
                    suggestedFix: "Add a working set or remove the item from the session.",
                    citationIDs: ["schoenfeld2021"], confidence: .strong))
            }
            for set in working where set.targetRPE == nil && set.targetRIR == nil && set.load == .unspecified {
                findings.append(UnifiedPlanCoachCritique(
                    id: "critique|underspecified|\(set.id.uuidString)", kind: .intensity,
                    severity: .info, title: "Effort is not specified",
                    detail: "\(located.item.exerciseKey.raw) has no load or RPE/RIR target on set \(set.setIndex + 1).",
                    suggestedFix: "Add a load, %1RM, or effort target if the engine is expected to progress this set.",
                    citationIDs: ["rpeAutoregulation", "oneRMEstimation"], confidence: .moderate))
            }
        }

        if plan.weeks.contains(where: \.isDeload) == false,
           trainingFacts?.repeatedDeclineByExercise.values.contains(where: { $0 >= 2 }) == true {
            findings.append(UnifiedPlanCoachCritique(
                id: "critique|deload-signal", kind: .recovery,
                severity: .attention, title: "Recent performance suggests a deload review",
                detail: "At least one lift has repeated week-over-week decline; this is a review signal, not an automatic plan change.",
                suggestedFix: "Consider a lower-volume week and inspect sleep, pain, effort, and exercise fit.",
                citationIDs: ["rpeAutoregulation", "halsonRecovery2014", "meeusenOvertraining2013"],
                confidence: .limited))
        }
        return findings.sorted { if $0.severity != $1.severity { return $0.severity > $1.severity }; return $0.id < $1.id }
    }

    private static func progression(for plan: Plan,
                                   trainingFacts: TrainingFacts) -> [UnifiedPlanProgressionProposal] {
        var proposals: [UnifiedPlanProgressionProposal] = []
        for located in strengthItems(in: plan) {
            guard let snapshot = trainingFacts.liftSnapshots[resolvedExerciseName(for: located.item.exerciseKey)]
                ?? trainingFacts.liftSnapshots.first(where: { ExerciseLibrary.dedupKey($0.key) == ExerciseLibrary.dedupKey(resolvedExerciseName(for: located.item.exerciseKey)) })?.value
            else { continue }
            for set in located.item.sets where set.kind != .warmup {
                guard let proposed = nextSet(set, snapshot: snapshot, intent: plan.weeks.first?.intendedProgression) else { continue }
                guard proposed != set else { continue }
                let declining = trainingFacts.repeatedDeclineByExercise[snapshot.exercise, default: 0] >= 2
                proposals.append(UnifiedPlanProgressionProposal(
                    id: "progress|\(set.id.uuidString)", sessionID: located.session.id,
                    itemID: located.item.id, setID: set.id, exerciseKey: located.item.exerciseKey,
                    current: set, proposed: proposed,
                    reason: declining
                        ? "Hold or reduce the next exposure after repeated decline."
                        : "The recent top set supports the next step in the selected progression model.",
                    citationIDs: ["rpeAutoregulation", "oneRMEstimation", "schoenfeld2021"],
                    confidence: declining ? .limited : .moderate))
                break
            }
        }
        return proposals
    }

    private static func nextSet(_ set: PrescribedSet, snapshot: LiftSnapshot,
                                intent: ProgressionIntent?) -> PrescribedSet? {
        var proposed = set
        switch set.repTarget {
        case let .range(minimum, maximum):
            if snapshot.topSetReps >= maximum {
                switch set.load {
                case let .absoluteWeight(value, unit):
                    proposed.load = .absoluteWeight(value: value * 1.025, unit: unit)
                case let .percent1RM(percent, _):
                    proposed.load = .percent1RM(percent: min(1, percent + 0.025), calculatedWeight: nil)
                default:
                    proposed.repTarget = .range(min: minimum + 1, max: maximum + 1)
                }
            } else if snapshot.topSetReps >= minimum {
                proposed.repTarget = .range(min: min(maximum, snapshot.topSetReps + 1), max: maximum)
            }
        case let .exact(reps):
            guard snapshot.topSetReps >= reps else { return nil }
            if case let .absoluteWeight(value, unit) = set.load {
                proposed.load = .absoluteWeight(value: value * 1.025, unit: unit)
            } else if case let .percent1RM(percent, _) = set.load {
                proposed.load = .percent1RM(percent: min(1, percent + 0.025), calculatedWeight: nil)
            } else {
                proposed.repTarget = .exact(reps + 1)
            }
        default:
            return nil
        }
        if intent == .autoregulated && set.targetRIR == nil && set.targetRPE == nil {
            proposed.targetRIR = 2
        }
        return proposed
    }

    private struct LocatedStrengthItem {
        let session: Session
        let item: StrengthItem
    }

    private static func strengthItems(in plan: Plan) -> [LocatedStrengthItem] {
        plan.weeks.flatMap { week in
            week.days.flatMap { day in
                day.sessions.flatMap { session in
                    session.items.compactMap { item in
                        guard case let .strength(strength) = item else { return nil }
                        return LocatedStrengthItem(session: session, item: strength)
                    }
                }
            }
        }
    }

    private static func locateStrengthItem(_ id: UUID, in plan: Plan) -> LocatedStrengthItem? {
        strengthItems(in: plan).first { $0.item.id == id }
    }

    private static func plannedVolume(for plan: Plan) -> [MuscleGroup: Double] {
        strengthItems(in: plan).reduce(into: [:]) { result, located in
            guard let template = try? preparedTemplate(for: located.item.exerciseKey), template.volumeEligible else { return }
            let sets = Double(located.item.sets.filter { $0.kind != .warmup }.count)
            for group in template.direct { result[group, default: 0] += sets }
            for group in template.indirect { result[group, default: 0] += sets * VolumeCredit.indirect }
        }
    }

    private static func plannedPatterns(for plan: Plan) -> Set<MovementPattern> {
        strengthItems(in: plan).reduce(into: Set<MovementPattern>()) { result, located in
            guard let template = ExerciseLibrary.template(matching: resolvedExerciseName(for: located.item.exerciseKey)) else { return }
            result.formUnion(MovementPattern.patterns(forExerciseNamed: template.name,
                                                      primaryMuscles: template.primaryMuscles,
                                                      databasePatternIDs: template.movementPatternIDs))
        }
    }

    private static func preparedTemplate(for key: ExerciseKey) throws -> ExerciseSimilarity.Prepared {
        guard let template = template(for: key) else { throw UnifiedPlanCoachError.exerciseNotFound(key) }
        return preparedTemplate(template)
    }

    private static func preparedTemplate(_ template: ExerciseTemplate) -> ExerciseSimilarity.Prepared {
        ExerciseSimilarity.Prepared(
            id: template.sourceExerciseID ?? template.name,
            name: template.name,
            direct: Set(template.directMuscles), indirect: Set(template.indirectMuscles),
            patterns: Set(template.movementPatternIDs), mechanics: template.mechanics,
            force: template.force, equipment: template.equipment,
            modalities: Set(template.modalities), trainingTypes: Set(template.trainingTypes),
            volumeEligible: template.volumeEligible)
    }

    private static func template(for key: ExerciseKey) -> ExerciseTemplate? {
        ExerciseLibrary.starter.first { template in
            template.name.caseInsensitiveCompare(key.raw) == .orderedSame
                || template.sourceExerciseID == key.raw
                || ExerciseLibrary.lookupKey(template.name) == key.raw
        }
    }

    private static func resolvedExerciseName(for key: ExerciseKey) -> String {
        template(for: key)?.name ?? key.raw
    }

    private static func exerciseKey(for prepared: ExerciseSimilarity.Prepared) -> String {
        prepared.id
    }

    private static func stableUUID(_ value: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_311_906_951
        for byte in value.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second ^= UInt64(byte &+ 31)
            second &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let chars = Array(hex)
        let groups = [8, 4, 4, 4, 12].reduce(into: ([String](), 0)) { result, length in
            result.0.append(String(chars[result.1..<(result.1 + length)]))
            result.1 += length
        }.0
        return UUID(uuidString: groups.joined(separator: "-")) ?? UUID()
    }
}
