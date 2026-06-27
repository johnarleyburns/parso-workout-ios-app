import Foundation
import SwiftData

/// High-level data operations over the SwiftData store. Written once here so
/// both app targets (and tests) share identical logging/PR/import behavior.
/// Operations are synchronous and run on the context's actor (typically main).
public enum WorkoutRepository {

    // MARK: Seeding (FR-1.1)

    /// Ensures every built-in exercise is present, adding any that are missing
    /// and backfilling facets/keywords on older built-ins (field-testing §03).
    /// Idempotent and never touches custom exercises, so existing stores upgrade
    /// to the larger catalog without duplicating user entries. Returns whether
    /// anything changed.
    @discardableResult
    public static func seedStarterLibraryIfNeeded(_ context: ModelContext) throws -> Bool {
        let existing = try allExercises(context)
        var byName: [String: Exercise] = [:]
        for ex in existing { byName[ex.name.lowercased()] = ex }
        var changed = false

        for t in ExerciseLibrary.starter {
            if let ex = byName[t.name.lowercased()] {
                guard !ex.isCustom else { continue }
                // Backfill facets on a pre-facets built-in (e.g. the legacy 25).
                if ex.searchKeywords.isEmpty {
                    ex.categoryValue = t.category
                    ex.equipmentValue = t.equipment
                    ex.isLateral = t.isLateral
                    ex.mechanicsValue = t.mechanics
                    ex.forceValue = t.force
                    ex.primaryMuscles = t.primaryMuscles
                    ex.secondaryMuscles = t.secondaryMuscles
                    ex.muscleGroups = t.muscleGroups
                    ex.searchKeywords = t.searchKeywords
                    ex.updatedAt = Date()
                    changed = true
                }
                // Backfill P2 (CC0 library) facets on already-faceted built-ins so
                // existing installs gain public-domain instructions/images/level.
                if ex.instructions.isEmpty, !t.instructions.isEmpty {
                    ex.instructions = t.instructions
                    ex.updatedAt = Date(); changed = true
                }
                if ex.imageName == nil, let img = t.imageName {
                    ex.imageName = img
                    ex.updatedAt = Date(); changed = true
                }
                if ex.level == nil, let lvl = t.level {
                    ex.level = lvl
                    ex.updatedAt = Date(); changed = true
                }
                // Backfill load accounting defaults on built-in exercises.
                if ex.loadAccountingMode == nil, !ex.loadAccountingUserOverride {
                    if let mode = Exercise.defaultLoadAccountingMode(equipment: ex.equipmentValue,
                                                                      isLateral: ex.isLateral,
                                                                      name: ex.name) {
                        ex.loadAccountingModeValue = mode
                        ex.updatedAt = Date(); changed = true
                    }
                    if ex.equipmentValue == .barbell && ex.defaultBarWeightKg == 0 {
                        ex.defaultBarWeightKg = Exercise.defaultBarWeightKg
                        ex.updatedAt = Date(); changed = true
                    }
                }
            } else {
                context.insert(ExerciseLibrary.makeExercise(from: t))
                changed = true
            }
        }
        if changed { try context.save() }
        return changed
    }

    // MARK: Exercises (FR-1.1)

    public static func allExercises(_ context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
    }

    /// Ranked, keyword-aware exercise search (field-testing §03): matches name,
    /// equipment ("cable"), muscle synonyms ("lats"/"pecs"), and force ("push").
    public static func searchExercises(_ query: String, in context: ModelContext) throws -> [Exercise] {
        ExerciseSearch.rank(query, over: try allExercises(context))
    }

    /// Finds an existing exercise by case-insensitive name or creates a custom
    /// one. New customs carry any provided facets and derived search keywords
    /// (field-testing §03).
    @discardableResult
    public static func findOrCreateExercise(named name: String,
                                            category: ExerciseCategory? = nil,
                                            equipment: Equipment? = nil,
                                            isLateral: Bool = false,
                                            mechanics: Mechanics? = nil,
                                            force: Force? = nil,
                                            primaryMuscles: [String] = [],
                                            secondaryMuscles: [String] = [],
                                            in context: ModelContext) throws -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try allExercises(context)
        if let existing = all.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return existing
        }
        // Backfill facets from the built-in catalog when the caller didn't supply
        // them and the name matches a known movement, so body-part coverage and
        // bodyweight detection work even for movements materialized by name (plan
        // launches, reuse) before the library is fully seeded. An exact built-in
        // is therefore not "custom".
        let template = ExerciseLibrary.byName[trimmed.lowercased()]
        let resolvedCategory = category ?? template?.category
        let resolvedEquipment = equipment ?? template?.equipment
        let resolvedLateral = isLateral || (template?.isLateral ?? false)
        let resolvedMechanics = mechanics ?? template?.mechanics
        let resolvedForce = force ?? template?.force
        let resolvedPrimary = primaryMuscles.isEmpty ? (template?.primaryMuscles ?? []) : primaryMuscles
        let resolvedSecondary = secondaryMuscles.isEmpty ? (template?.secondaryMuscles ?? []) : secondaryMuscles
        let keywords = ExerciseSearch.keywords(name: trimmed, equipment: resolvedEquipment, isLateral: resolvedLateral,
                                               force: resolvedForce, mechanics: resolvedMechanics,
                                               primaryMuscles: resolvedPrimary, secondaryMuscles: resolvedSecondary)
        let ex = Exercise(name: trimmed, category: resolvedCategory, muscleGroups: resolvedPrimary + resolvedSecondary,
                          isCustom: template == nil, equipment: resolvedEquipment, isLateral: resolvedLateral,
                          mechanics: resolvedMechanics, force: resolvedForce,
                          primaryMuscles: resolvedPrimary, secondaryMuscles: resolvedSecondary,
                          searchKeywords: keywords)
        context.insert(ex)
        try context.save()
        return ex
    }

    // MARK: Sessions & sets (FR-1.1, FR-1.2)

    /// `isLogged` flags a workout entered manually after the fact (feedback batch 6/7):
    /// it lands in history identically to a live one but carries the "Logged" tag and
    /// no live HR/clock. Additive default keeps live callers unchanged.
    @discardableResult
    public static func createSession(title: String = "Workout",
                                      date: Date = Date(),
                                      isLogged: Bool = false,
                                      partnerIDs: [String] = [],
                                      in context: ModelContext) throws -> WorkoutSession {
        let s = WorkoutSession(title: title, date: date, isLogged: isLogged)
        s.activePartnerIDs = partnerIDs
        context.insert(s)
        try context.save()
        return s
    }

    public static func allSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
    }

    /// Appends a set to a session, assigning the next order index. Stamps
    /// `updatedAt` for sync (FR-9.2). `performedBy` attributes the set to a
    /// training partner (nil ⇒ the owner; field-testing §04).
    @discardableResult
    public static func addSet(to session: WorkoutSession,
                              exercise: Exercise,
                              weightKg: Double,
                              reps: Int,
                              rpe: Double? = nil,
                              isWarmup: Bool = false,
                              usesBodyweight: Bool = false,
                              note: String? = nil,
                              completedAt: Date = Date(),
                              performedBy: Person? = nil,
                              in context: ModelContext) throws -> SetEntry {
        let nextOrder = (session.sets ?? []).map(\.order).max().map { $0 + 1 } ?? 0
        // Only snapshot load accounting when the exercise has an explicit mode set
        // (seeded or user-overridden). Legacy exercises without accounting produce
        // legacy sets where effectiveLoadKg = weight.
        let mode = exercise.loadAccountingModeValue
        let bar = exercise.effectiveDefaultBarWeightKg
        let set = SetEntry(weight: weightKg, reps: reps, order: nextOrder,
                           isWarmup: isWarmup, usesBodyweight: usesBodyweight, rpe: rpe, note: note,
                           completedAt: completedAt, session: session, exercise: exercise,
                           performedBy: performedBy,
                           barWeightKg: mode != nil ? bar : 0,
                           loadMultiplier: 1.0,
                           loadAccountingMode: mode?.rawValue)
        context.insert(set)
        session.updatedAt = Date()
        try context.save()
        return set
    }

    /// Starts a fresh session pre-populated with a past session's exercises (in
    /// order) but no sets, so the user logs anew (field-testing §04, decision
    /// #16 — replaces templates). Only the owner's exercises are carried over.
    @discardableResult
    public static func reuseSession(from past: WorkoutSession,
                                    date: Date = Date(),
                                    in context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(title: past.title, date: date)
        // Carry over every exercise anyone logged (in order) as planned names so a
        // partner's movements aren't dropped — "start from history" should include
        // the partner's work too, since the user often trains with the same partner
        // (feedback batch 3). The partners themselves are global `Person`s and stay
        // in the roster.
        session.plannedExerciseNames = past.exercisesInOrder.map(\.name)
        context.insert(session)
        try context.save()
        return session
    }

    /// Copies a full past workout — its owner exercises AND sets (weight/reps/
    /// RPE/warmup) — into `session`, stamped now, as a ready-to-adjust starting
    /// point ("use previous workout"). Returns the number of sets copied.
    @discardableResult
    public static func copyWorkout(from past: WorkoutSession,
                                   into session: WorkoutSession,
                                   in context: ModelContext) throws -> Int {
        let now = Date()
        var copied = 0
        for set in past.orderedSets where set.isOwnerSet {
            guard let ex = set.exercise else { continue }
            _ = try addSet(to: session, exercise: ex, weightKg: set.weight, reps: set.reps,
                           rpe: set.rpe, isWarmup: set.isWarmup, note: set.note,
                           completedAt: now, in: context)
            copied += 1
        }
        if session.title.isEmpty || session.title == "Workout" { session.title = past.title }
        session.plannedExerciseNames = []
        try context.save()
        return copied
    }

    // MARK: People / partners (field-testing §04)

    public static func allPeople(_ context: ModelContext) throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }

    /// The owner Person, creating it on first use.
    @discardableResult
    public static func me(in context: ModelContext) throws -> Person {
        if let existing = try allPeople(context).first(where: { $0.isMe }) { return existing }
        let me = Person(name: "Me", isMe: true)
        context.insert(me)
        try context.save()
        return me
    }

    /// Finds a partner by case-insensitive name or creates one.
    @discardableResult
    public static func findOrCreatePerson(named name: String, in context: ModelContext) throws -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try allPeople(context).first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) { return existing }
        let p = Person(name: trimmed, isMe: false)
        context.insert(p)
        try context.save()
        return p
    }

    /// Edits a logged set. Every parameter is "no change" when omitted, so editing
    /// weight/reps never clobbers `isWarmup`, the note, or RPE (history-edit bug
    /// fix). `performedBy` is double-optional: `nil` = leave attribution as-is,
    /// `.some(nil)` = re-attribute to the owner ("Me"), `.some(person)` = a partner.
    public static func updateSet(_ set: SetEntry,
                                 weightKg: Double? = nil,
                                 reps: Int? = nil,
                                 rpe: Double?? = nil,
                                 isWarmup: Bool? = nil,
                                 usesBodyweight: Bool? = nil,
                                 note: String?? = nil,
                                 exercise: Exercise? = nil,
                                 performedBy: Person?? = nil,
                                 in context: ModelContext) throws {
        if let weightKg { set.weight = weightKg }
        if let reps { set.reps = reps }
        if let rpe { set.rpe = rpe }
        if let isWarmup { set.isWarmup = isWarmup }
        if let usesBodyweight { set.usesBodyweight = usesBodyweight }
        if let note { set.note = note }
        if let exercise { set.exercise = exercise }
        if let performedBy {
            // A "Me"/owner Person is normalized to nil so owner stats stay correct.
            set.performedBy = (performedBy?.isMe ?? true) ? nil : performedBy
        }
        set.updatedAt = Date()
        set.session?.updatedAt = Date()
        try context.save()
    }

    /// Reassigns every set of `oldExercise` in `session` to `newExercise` — the
    /// history-edit "I logged the wrong movement" fix. Owner AND partner sets
    /// move together, the planned-name list follows so the card header/prescription
    /// update, and duplicate planned names are de-duped. No-op (returns 0) when the
    /// exercise is unchanged. Returns the number of sets moved.
    @discardableResult
    public static func changeExercise(in session: WorkoutSession,
                                      from oldExercise: Exercise,
                                      to newExercise: Exercise,
                                      in context: ModelContext) throws -> Int {
        guard oldExercise.id != newExercise.id else { return 0 }
        let now = Date()
        let moved = (session.sets ?? []).filter { $0.exercise?.id == oldExercise.id }
        for s in moved {
            s.exercise = newExercise
            s.updatedAt = now
        }
        var names = session.plannedExerciseNames
        if let idx = names.firstIndex(of: oldExercise.name) {
            names[idx] = newExercise.name
        }
        // Collapse any duplicate of the new name so we never render two cards.
        var seen = Set<String>()
        names = names.filter { seen.insert($0).inserted }
        session.plannedExerciseNames = names
        session.updatedAt = now
        try context.save()
        return moved.count
    }

    public static func deleteSet(_ set: SetEntry, in context: ModelContext) throws {
        set.session?.updatedAt = Date()
        context.delete(set)
        try context.save()
    }

    public static func deleteSession(_ session: WorkoutSession, in context: ModelContext) throws {
        context.delete(session)
        try context.save()
    }

    public static func softDeleteSession(_ session: WorkoutSession, in context: ModelContext) throws {
        session.deletedAt = Date()
        try context.save()
    }

    public static func restoreSession(_ session: WorkoutSession, in context: ModelContext) throws {
        session.deletedAt = nil
        try context.save()
    }

    // MARK: Last-time & PRs (FR-1.3, FR-1.4, FR-5.2)

    /// All non-warmup sets for an exercise as pure samples, newest first.
    /// Partner sets are excluded so they never affect the owner's stats
    /// (field-testing §04, decision #13). Uses effective load for calculations.
    public static func sampleHistory(for exercise: Exercise) -> [SetSample] {
        (exercise.sets ?? [])
            .filter { $0.isOwnerSet }
            .map { SetSample.from($0) }
            .sorted { $0.date > $1.date }
    }

    /// The most recent prior session's working sets for an exercise (FR-1.3),
    /// excluding the given session. Returns sets in logged order.
    public static func lastTimeSets(for exercise: Exercise,
                                    excluding session: WorkoutSession?) -> [SetEntry] {
        let sets = (exercise.sets ?? []).filter { $0.session?.id != session?.id && $0.isOwnerSet }
        // Group by session, pick the most recent session by date.
        let grouped = Dictionary(grouping: sets) { $0.session?.id ?? UUID() }
        let mostRecent = grouped.values.max { a, b in
            (a.first?.session?.date ?? .distantPast) < (b.first?.session?.date ?? .distantPast)
        }
        return (mostRecent ?? []).sorted { $0.order < $1.order }
    }

    /// Current PR value for an exercise under the rule, optionally excluding a
    /// session (so we can ask "is this set a PR vs everything before it").
    /// Uses effective load for calculations.
    public static func currentPR(for exercise: Exercise,
                                 rule: PRRule,
                                 formula: OneRepMaxFormula,
                                 excluding session: WorkoutSession? = nil) -> Double? {
        let samples = (exercise.sets ?? [])
            .filter { (session == nil || $0.session?.id != session?.id) && $0.isOwnerSet }
            .map { SetSample.from($0) }
        return PRCalculator.best(samples, rule: rule, formula: formula)
    }

    /// Whether a prospective set would be a new PR for the exercise.
    /// `weightKg` is the effective load (caller must compute before passing).
    public static func wouldBePR(exercise: Exercise,
                                 weightKg: Double,
                                 reps: Int,
                                 isWarmup: Bool,
                                 rule: PRRule,
                                 formula: OneRepMaxFormula,
                                 excluding session: WorkoutSession? = nil) -> Bool {
        let candidate = SetSample(weight: weightKg, reps: reps, isWarmup: isWarmup)
        let previous = (exercise.sets ?? [])
            .filter { (session == nil || $0.session?.id != session?.id) && $0.isOwnerSet }
            .map { SetSample.from($0) }
        return PRCalculator.isNewPR(candidate: candidate, previous: previous, rule: rule, formula: formula)
    }

    public struct RecentPR: Identifiable, Sendable {
        public var id: UUID
        public var exerciseName: String
        public var value: Double
        public var achievedAt: Date
        public var rule: PRRule
    }

    /// The best (PR) set per exercise, sorted by achievement date (FR-5.2).
    public static func recentPRs(_ context: ModelContext,
                                 rule: PRRule,
                                 formula: OneRepMaxFormula) throws -> [RecentPR] {
        let exercises = try allExercises(context)
        var prs: [RecentPR] = []
        for ex in exercises {
            let samples = sampleHistory(for: ex)
            guard let best = PRCalculator.bestSample(samples, rule: rule, formula: formula) else { continue }
            prs.append(RecentPR(id: ex.id, exerciseName: ex.name,
                                value: PRCalculator.metric(best, rule: rule, formula: formula),
                                achievedAt: best.date, rule: rule))
        }
        return prs.sorted { $0.achievedAt > $1.achievedAt }
    }

    // MARK: Trends (FR-5.1)

    public struct TrendPoint: Identifiable, Sendable, Equatable {
        public var date: Date
        public var value: Double
        public var id: Date { date }
    }

    /// Best metric per training day for an exercise, ascending by date (FR-5.1).
    /// Each point is the best working-set value that day under the rule.
    /// Uses effective load for calculations.
    public static func trendSeries(for exercise: Exercise,
                                   rule: PRRule,
                                   formula: OneRepMaxFormula,
                                   calendar: Calendar = .current) -> [TrendPoint] {
        let sets = (exercise.sets ?? []).filter { !$0.isWarmup && $0.reps > 0 && $0.effectiveLoadKg > 0 && $0.isOwnerSet }
        let byDay = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.completedAt) }
        return byDay.map { day, daySets in
            let samples = daySets.map { SetSample.from($0) }
            let best = PRCalculator.best(samples, rule: rule, formula: formula) ?? 0
            return TrendPoint(date: day, value: best)
        }
        .sorted { $0.date < $1.date }
    }

    /// The progressive PR history for an exercise: each point that set a new
    /// all-time record under the rule, ascending by date (FR-5.2).
    /// Uses effective load for calculations.
    public static func prTimeline(for exercise: Exercise,
                                  rule: PRRule,
                                  formula: OneRepMaxFormula) -> [TrendPoint] {
        let samples = (exercise.sets ?? [])
            .filter { $0.isOwnerSet }
            .map { SetSample.from($0) }
            .filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }
            .sorted { $0.date < $1.date }
        var result: [TrendPoint] = []
        var best = -Double.greatestFiniteMagnitude
        for s in samples {
            let v = PRCalculator.metric(s, rule: rule, formula: formula)
            if v > best + 1e-9 {
                best = v
                result.append(TrendPoint(date: s.date, value: v))
            }
        }
        return result
    }

    /// Distinct training days (start-of-day) across all sessions (FR-5.4 heatmap).
    public static func trainingDays(_ context: ModelContext, calendar: Calendar = .current) throws -> Set<Date> {
        let sessions = try allSessions(context)
        return Set(sessions.map { calendar.startOfDay(for: $0.date) })
    }

    // MARK: Templates (FR-1.6)

    @discardableResult
    public static func createTemplate(name: String,
                                      exercises: [(name: String, sets: Int, reps: Int)],
                                      in context: ModelContext) throws -> SessionTemplate {
        let t = SessionTemplate(name: name)
        context.insert(t)
        for (i, e) in exercises.enumerated() {
            let te = TemplateExercise(exerciseName: e.name, order: i,
                                      targetSets: e.sets, targetReps: e.reps, template: t)
            context.insert(te)
        }
        try context.save()
        return t
    }

    public static func allTemplates(_ context: ModelContext) throws -> [SessionTemplate] {
        try context.fetch(FetchDescriptor<SessionTemplate>(sortBy: [SortDescriptor(\.name)]))
    }

    public static func deleteTemplate(_ t: SessionTemplate, in context: ModelContext) throws {
        context.delete(t)
        try context.save()
    }

    /// Starts a new empty session titled after a template, pre-resolving its
    /// exercises into the library (FR-1.6). Sets are still logged by the user.
    @discardableResult
    public static func startSession(from template: SessionTemplate,
                                    date: Date = Date(),
                                    in context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(title: template.name, date: date, templateName: template.name)
        context.insert(session)
        for te in template.orderedExercises {
            _ = try findOrCreateExercise(named: te.exerciseName, in: context)
        }
        try context.save()
        return session
    }

    /// Starts a session from a concrete `WorkoutPlan` (a strength preset,
    /// round4b §B-1). Pre-loads the prescribed movements as planned (ghost) cards
    /// and stamps `planKey` so the session view can render the scheme banner +
    /// per-item prescription.
    @discardableResult
    public static func startSession(from plan: WorkoutPlan,
                                    repLadder: [Int]? = nil,
                                    date: Date = Date(),
                                    isLogged: Bool = false,
                                    in context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(title: plan.displayTitle, date: date, isLogged: isLogged)
        session.planKey = plan.id
        session.plannedExerciseNames = plan.movementNames
        // A flexible template launched with a chosen rep scheme stamps the ladder
        // so the planned cards show "N sets · a-b-c" (feedback batch 3).
        if let repLadder, !repLadder.isEmpty { session.plannedRepLadder = repLadder }
        context.insert(session)
        for name in plan.movementNames {
            _ = try findOrCreateExercise(named: name, in: context)
        }
        try context.save()
        return session
    }

    /// Materializes a coaching `PrescribedSession` ("Do this workout", strength-pivot
    /// P5.3) into a fresh `WorkoutSession`: the prescribed movement(s) become planned
    /// (ghost) cards, the rep ladder seeds the pending set rows + default reps, and the
    /// prescribed load (if any) pre-fills the keypad. The session is otherwise an
    /// ordinary live strength session — the user logs the sets.
    @discardableResult
    public static func startSession(from prescribed: PrescribedSession,
                                    date: Date = Date(),
                                    in context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(title: prescribed.title, date: date)
        session.plannedExerciseNames = prescribed.exerciseNames
        if !prescribed.repLadder.isEmpty { session.plannedRepLadder = prescribed.repLadder }
        if let load = prescribed.loadKg, load > 0 { session.prescribedLoadKg = load }
        context.insert(session)
        for name in prescribed.exerciseNames {
            _ = try findOrCreateExercise(named: name, in: context)
        }
        try context.save()
        return session
    }

    // MARK: Cardio ingest (FR-2.1)

    /// Inserts ingested HealthKit workouts that aren't already present, keyed by
    /// HealthKit UUID (UC-2 alternate: duplicates skipped by UUID). Returns the
    /// number newly inserted.
    @discardableResult
    public static func ingest(_ workouts: [IngestedWorkout], in context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<CardioWorkout>())
        let known = Set(existing.compactMap { $0.healthKitWorkoutUUID })
        var inserted = 0
        for w in workouts where !known.contains(w.id) {
            let c = CardioWorkout(type: w.type, start: w.start, end: w.end,
                                   distance: w.distanceMeters, activeEnergy: w.activeEnergyKcal,
                                   avgHeartRate: w.avgHeartRate, maxHeartRate: w.maxHeartRate,
                                   source: w.source, healthKitWorkoutUUID: w.id,
                                   importedWorkoutKind: w.importedKind)
            context.insert(c)
            for p in w.hrSamples {
                context.insert(HRSample(t: p.t, bpm: p.bpm, cardio: c))
            }
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }

    public static func allCardio(_ context: ModelContext) throws -> [CardioWorkout] {
        try context.fetch(FetchDescriptor<CardioWorkout>(sortBy: [SortDescriptor(\.start, order: .reverse)]))
    }

    /// One-time migration: backfill `importedWorkoutKind` for existing .other
    /// CardioWorkout rows that were imported before the recovery-aware redesign.
    /// Without original HKWorkoutActivityType metadata, cannot backfill with
    /// certainty — retains nil (unknown).
    public static func backfillImportedWorkoutKinds(in context: ModelContext) throws {
        let all = try allCardio(context)
        for c in all where c.typeValue == .other && c.importedWorkoutKind == nil {
            _ = c
        }
    }

    /// Persists a workout recorded on the iPhone (FR-2.2–2.5) into the local
    /// store, computing avg/max HR and attaching HR + route samples. The
    /// `healthKitWorkoutUUID` links to the HK copy so re-ingest won't duplicate.
    @discardableResult
    public static func saveRecordedCardio(_ summary: CardioWorkoutSummary,
                                          source: CardioSource,
                                          healthKitWorkoutUUID: UUID?,
                                          in context: ModelContext) throws -> CardioWorkout {
        let bpms = summary.hrSamples.map(\.bpm).filter { $0 > 0 }
        let avg = bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count)
        let maxHR = bpms.max()
        let c = CardioWorkout(id: summary.id, type: summary.type, start: summary.start,
                              end: summary.end, distance: summary.distanceMeters,
                              activeEnergy: summary.activeEnergyKcal, avgHeartRate: avg,
                              maxHeartRate: maxHR,
                              targetDistance: summary.targetDistanceMeters, source: source,
                              healthKitWorkoutUUID: healthKitWorkoutUUID,
                              isLogged: summary.isLogged, customTitle: summary.customTitle)
        c.intervalSummary = summary.intervalSummary
        context.insert(c)
        for p in summary.hrSamples { context.insert(HRSample(t: p.t, bpm: p.bpm, cardio: c)) }
        for f in summary.route {
            context.insert(RouteSample(t: f.t, lat: f.lat, lon: f.lon, elevation: f.elevation, cardio: c))
        }
        try context.save()
        return c
    }

    /// Persists a **manually logged** cardio/interval workout (feedback batch 6
    /// item 3): the same shape as a recorded one — so it appears identically in
    /// history — but flagged `isLogged`, with no live HR or GPS route. `customTitle`
    /// carries an "Other Cardio" free-text label (e.g. "Rowing").
    @discardableResult
    public static func saveLoggedCardio(type: CardioType, start: Date,
                                        durationSeconds: TimeInterval,
                                        distanceMeters: Double? = nil,
                                        customTitle: String? = nil,
                                        intervalSummary: IntervalSummary? = nil,
                                        in context: ModelContext) throws -> CardioWorkout {
        let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = CardioWorkoutSummary(
            id: UUID(), type: type, start: start,
            end: start.addingTimeInterval(max(0, durationSeconds)),
            distanceMeters: distanceMeters,
            intervalSummary: intervalSummary,
            customTitle: (trimmed?.isEmpty == false) ? trimmed : nil,
            isLogged: true)
        return try saveRecordedCardio(summary, source: .iphone,
                                      healthKitWorkoutUUID: nil, in: context)
    }

    /// Persists a pool swim (round4b feedback #3): time + lap count only, no
    /// distance/calorie estimate. `targetLaps` is the goal the user set, `laps`
    /// what they completed.
    @discardableResult
    public static func saveSwim(start: Date, end: Date, laps: Int, targetLaps: Int?,
                                healthKitWorkoutUUID: UUID? = nil,
                                in context: ModelContext) throws -> CardioWorkout {
        let c = CardioWorkout(type: .swim, start: start, end: end,
                               laps: laps, targetLaps: targetLaps, source: .iphone)
        c.healthKitWorkoutUUID = healthKitWorkoutUUID
        context.insert(c)
        try context.save()
        return c
    }

    public static func deleteCardio(_ c: CardioWorkout, in context: ModelContext) throws {
        context.delete(c)
        try context.save()
    }

    public static func softDeleteCardio(_ c: CardioWorkout, in context: ModelContext) throws {
        c.deletedAt = Date()
        try context.save()
    }

    public static func restoreCardio(_ c: CardioWorkout, in context: ModelContext) throws {
        c.deletedAt = nil
        try context.save()
    }

    // MARK: Export / Import (FR-6)

    public static func buildExport(_ context: ModelContext,
                                     coachPreferences: ExportCoachPreferences? = nil) throws -> CadenceExport {
        let sessions = try allSessions(context).map { session -> ExportSession in
            let sets = session.orderedSets.map { set in
                ExportSet(id: set.id,
                          exerciseName: set.exercise?.name ?? "",
                          category: set.exercise?.category,
                          weightKg: set.weight, reps: set.reps, order: set.order,
                          isWarmup: set.isWarmup, rpe: set.rpe, note: set.note,
                          completedAt: set.completedAt,
                          performedBy: set.isOwnerSet ? nil : set.performedBy?.name,
                          barWeightKg: set.loadAccountingMode != nil ? set.barWeightKg : nil,
                          loadMultiplier: set.loadAccountingMode != nil ? set.loadMultiplier : nil,
                          loadAccountingMode: set.loadAccountingMode)
            }
            return ExportSession(id: session.id, title: session.title,
                                 date: session.date, notes: session.notes, sets: sets)
        }
        let cardio = try allCardio(context).map { c in
            ExportCardio(id: c.id, type: c.type, start: c.start, end: c.end,
                         distanceMeters: c.distance, activeEnergyKcal: c.activeEnergy,
                         avgHeartRate: c.avgHeartRate, source: c.source)
        }
        return CadenceExport(sessions: sessions, cardio: cardio, coachPreferences: coachPreferences)
    }

    /// Applies parsed sessions (from the Gmail importer) into the store,
    /// creating exercises as needed (UC-7). Returns sessions created.
    @discardableResult
    public static func apply(_ parsed: [ParsedSession], in context: ModelContext) throws -> Int {
        for ps in parsed {
            let session = WorkoutSession(title: ps.title, date: ps.date ?? Date())
            context.insert(session)
            var order = 0
            for pe in ps.exercises {
                let ex = try findOrCreateExercise(named: pe.name, category: pe.category, in: context)
                for set in pe.sets {
                    let s = SetEntry(weight: set.weightKg, reps: set.reps, order: order,
                                     completedAt: ps.date ?? Date(), session: session, exercise: ex)
                    context.insert(s)
                    order += 1
                }
            }
        }
        try context.save()
        return parsed.count
    }

    /// Merges a JSON export back into the store, skipping sessions whose id
    /// already exists (FR-6.2 import). Returns sessions added.
    @discardableResult
    public static func merge(_ export: CadenceExport, in context: ModelContext) throws -> Int {
        let existingIDs = Set(try allSessions(context).map(\.id))
        var added = 0
        for es in export.sessions where !existingIDs.contains(es.id) {
            let session = WorkoutSession(id: es.id, title: es.title, date: es.date, notes: es.notes)
            context.insert(session)
            for set in es.sets {
                let cat = set.category.flatMap(ExerciseCategory.init(rawValue:))
                let ex = try findOrCreateExercise(named: set.exerciseName, category: cat, in: context)
                let person = try set.performedBy.map { try findOrCreatePerson(named: $0, in: context) }
                let s = SetEntry(id: set.id, weight: set.weightKg, reps: set.reps, order: set.order,
                                 isWarmup: set.isWarmup, rpe: set.rpe, note: set.note,
                                 completedAt: set.completedAt, session: session, exercise: ex,
                                 performedBy: person,
                                 barWeightKg: set.barWeightKg ?? 0,
                                 loadMultiplier: set.loadMultiplier ?? 1.0,
                                 loadAccountingMode: set.loadAccountingMode)
                context.insert(s)
            }
            added += 1
        }
        try context.save()
        return added
    }
}
