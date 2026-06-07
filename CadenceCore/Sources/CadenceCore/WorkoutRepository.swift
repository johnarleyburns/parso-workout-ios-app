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
                // Backfill facets on a pre-facets built-in (e.g. the legacy 25).
                if !ex.isCustom && ex.searchKeywords.isEmpty {
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
        let keywords = ExerciseSearch.keywords(name: trimmed, equipment: equipment, isLateral: isLateral,
                                               force: force, mechanics: mechanics,
                                               primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles)
        let ex = Exercise(name: trimmed, category: category, muscleGroups: primaryMuscles + secondaryMuscles,
                          isCustom: true, equipment: equipment, isLateral: isLateral, mechanics: mechanics,
                          force: force, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
                          searchKeywords: keywords)
        context.insert(ex)
        try context.save()
        return ex
    }

    // MARK: Sessions & sets (FR-1.1, FR-1.2)

    @discardableResult
    public static func createSession(title: String = "Workout",
                                     date: Date = Date(),
                                     in context: ModelContext) throws -> WorkoutSession {
        let s = WorkoutSession(title: title, date: date)
        context.insert(s)
        try context.save()
        return s
    }

    public static func allSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
    }

    /// Appends a set to a session, assigning the next order index. Stamps
    /// `updatedAt` for sync (FR-9.2).
    @discardableResult
    public static func addSet(to session: WorkoutSession,
                              exercise: Exercise,
                              weightKg: Double,
                              reps: Int,
                              rpe: Double? = nil,
                              isWarmup: Bool = false,
                              note: String? = nil,
                              completedAt: Date = Date(),
                              in context: ModelContext) throws -> SetEntry {
        let nextOrder = (session.sets ?? []).map(\.order).max().map { $0 + 1 } ?? 0
        let set = SetEntry(weight: weightKg, reps: reps, order: nextOrder,
                           isWarmup: isWarmup, rpe: rpe, note: note,
                           completedAt: completedAt, session: session, exercise: exercise)
        context.insert(set)
        session.updatedAt = Date()
        try context.save()
        return set
    }

    public static func updateSet(_ set: SetEntry,
                                 weightKg: Double? = nil,
                                 reps: Int? = nil,
                                 rpe: Double?? = nil,
                                 isWarmup: Bool? = nil,
                                 note: String?? = nil,
                                 in context: ModelContext) throws {
        if let weightKg { set.weight = weightKg }
        if let reps { set.reps = reps }
        if let rpe { set.rpe = rpe }
        if let isWarmup { set.isWarmup = isWarmup }
        if let note { set.note = note }
        set.updatedAt = Date()
        set.session?.updatedAt = Date()
        try context.save()
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

    // MARK: Last-time & PRs (FR-1.3, FR-1.4, FR-5.2)

    /// All non-warmup sets for an exercise as pure samples, newest first.
    public static func sampleHistory(for exercise: Exercise) -> [SetSample] {
        (exercise.sets ?? [])
            .map { SetSample(weight: $0.weight, reps: $0.reps,
                             date: $0.completedAt, isWarmup: $0.isWarmup) }
            .sorted { $0.date > $1.date }
    }

    /// The most recent prior session's working sets for an exercise (FR-1.3),
    /// excluding the given session. Returns sets in logged order.
    public static func lastTimeSets(for exercise: Exercise,
                                    excluding session: WorkoutSession?) -> [SetEntry] {
        let sets = (exercise.sets ?? []).filter { $0.session?.id != session?.id }
        // Group by session, pick the most recent session by date.
        let grouped = Dictionary(grouping: sets) { $0.session?.id ?? UUID() }
        let mostRecent = grouped.values.max { a, b in
            (a.first?.session?.date ?? .distantPast) < (b.first?.session?.date ?? .distantPast)
        }
        return (mostRecent ?? []).sorted { $0.order < $1.order }
    }

    /// Current PR value for an exercise under the rule, optionally excluding a
    /// session (so we can ask "is this set a PR vs everything before it").
    public static func currentPR(for exercise: Exercise,
                                 rule: PRRule,
                                 formula: OneRepMaxFormula,
                                 excluding session: WorkoutSession? = nil) -> Double? {
        let samples = (exercise.sets ?? [])
            .filter { session == nil || $0.session?.id != session?.id }
            .map { SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt, isWarmup: $0.isWarmup) }
        return PRCalculator.best(samples, rule: rule, formula: formula)
    }

    /// Whether a prospective set would be a new PR for the exercise.
    public static func wouldBePR(exercise: Exercise,
                                 weightKg: Double,
                                 reps: Int,
                                 isWarmup: Bool,
                                 rule: PRRule,
                                 formula: OneRepMaxFormula,
                                 excluding session: WorkoutSession? = nil) -> Bool {
        let candidate = SetSample(weight: weightKg, reps: reps, isWarmup: isWarmup)
        let previous = (exercise.sets ?? [])
            .filter { session == nil || $0.session?.id != session?.id }
            .map { SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt, isWarmup: $0.isWarmup) }
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
    public static func trendSeries(for exercise: Exercise,
                                   rule: PRRule,
                                   formula: OneRepMaxFormula,
                                   calendar: Calendar = .current) -> [TrendPoint] {
        let sets = (exercise.sets ?? []).filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }
        let byDay = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.completedAt) }
        return byDay.map { day, daySets in
            let samples = daySets.map { SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt, isWarmup: false) }
            let best = PRCalculator.best(samples, rule: rule, formula: formula) ?? 0
            return TrendPoint(date: day, value: best)
        }
        .sorted { $0.date < $1.date }
    }

    /// The progressive PR history for an exercise: each point that set a new
    /// all-time record under the rule, ascending by date (FR-5.2).
    public static func prTimeline(for exercise: Exercise,
                                  rule: PRRule,
                                  formula: OneRepMaxFormula) -> [TrendPoint] {
        let samples = (exercise.sets ?? [])
            .map { SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt, isWarmup: $0.isWarmup) }
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
                                  source: w.source, healthKitWorkoutUUID: w.id)
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
                              maxHeartRate: maxHR, source: source,
                              healthKitWorkoutUUID: healthKitWorkoutUUID)
        context.insert(c)
        for p in summary.hrSamples { context.insert(HRSample(t: p.t, bpm: p.bpm, cardio: c)) }
        for f in summary.route {
            context.insert(RouteSample(t: f.t, lat: f.lat, lon: f.lon, elevation: f.elevation, cardio: c))
        }
        try context.save()
        return c
    }

    public static func deleteCardio(_ c: CardioWorkout, in context: ModelContext) throws {
        context.delete(c)
        try context.save()
    }

    // MARK: Export / Import (FR-6)

    public static func buildExport(_ context: ModelContext) throws -> CadenceExport {
        let sessions = try allSessions(context).map { session -> ExportSession in
            let sets = session.orderedSets.map { set in
                ExportSet(id: set.id,
                          exerciseName: set.exercise?.name ?? "",
                          category: set.exercise?.category,
                          weightKg: set.weight, reps: set.reps, order: set.order,
                          isWarmup: set.isWarmup, rpe: set.rpe, note: set.note,
                          completedAt: set.completedAt)
            }
            return ExportSession(id: session.id, title: session.title,
                                 date: session.date, notes: session.notes, sets: sets)
        }
        let cardio = try allCardio(context).map { c in
            ExportCardio(id: c.id, type: c.type, start: c.start, end: c.end,
                         distanceMeters: c.distance, activeEnergyKcal: c.activeEnergy,
                         avgHeartRate: c.avgHeartRate, source: c.source)
        }
        return CadenceExport(sessions: sessions, cardio: cardio)
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
                let s = SetEntry(id: set.id, weight: set.weightKg, reps: set.reps, order: set.order,
                                 isWarmup: set.isWarmup, rpe: set.rpe, note: set.note,
                                 completedAt: set.completedAt, session: session, exercise: ex)
                context.insert(s)
            }
            added += 1
        }
        try context.save()
        return added
    }
}
