import CadenceFeatures
import Foundation
import CadenceCore
import CadenceWorkoutFeatures

public enum HomeDashboardPresenter {
    /// The first warning is fully visible; the rest are behind Show more.
    public static func visibleSuggestions(_ suggestions: [HomeSuggestion], expanded: Bool) -> [HomeSuggestion] {
        expanded ? suggestions : Array(suggestions.prefix(1))
    }

    public static func make(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences,
                            goal: TrainingGoal, experience: ExperienceLevel,
                            userAge: Int?, liveVolumeDelta: [MuscleGroup: Double] = [:],
                            weeklyCardio: WeeklyCardioSummary? = nil,
                            activityDose: WeeklyActivitySummary? = nil,
                            restoredWeeklySetsByMuscle: [String: Double]? = nil) -> HomeDashboardState {
        let balance = snapshot.decision.weeklyBalance
        // Weekly sets, not days per week: frequency is not an independent
        // indicator of training impact (O'Donovan/Lee et al. 2022).
        // Before the coach pipeline produces real facts (cold launch), the
        // durably cached same-day counts avoid a "0 of N sets" flash.
        let strengthSets = restoredWeeklySetsByMuscle?.values.reduce(0, +)
            ?? snapshot.facts.weeklySetsByGroup.values.reduce(0, +)
        let strengthTarget = Double(max(1, schedule.trackedMuscleGroups.count)) * 12
        let strength = HomeDashboardState.Progress(completed: strengthSets, target: strengthTarget,
            displayText: {
                #if os(Linux)
                "\(Int(strengthSets.rounded()))/\(Int(strengthTarget)) sets"
                #else
                String(localized: "\(Int(strengthSets.rounded()))/\(Int(strengthTarget)) sets", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            normalized: min(1, strengthSets / strengthTarget))
        let cardioCredit = weeklyCardio?.moderateEquivalentMinutes ?? balance.moderateEquivalentMinutes
        let cardioTarget = weeklyCardio?.guidelineTarget ?? WeeklyCardioProgress.target
        let cardio = HomeDashboardState.Progress(completed: cardioCredit, target: cardioTarget,
            displayText: {
                #if os(Linux)
                "\(Int(cardioCredit.rounded()))/\(Int(cardioTarget)) min"
                #else
                String(localized: "\(Int(cardioCredit.rounded()))/\(Int(cardioTarget)) min", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            normalized: min(1, max(0, cardioCredit / cardioTarget)))
        // Home's visible volume must use the same explicit Monday-to-now
        // boundary as the Strength and Cardio rows. DB++'s observation is still
        // used by coaching/adherence, but merging it here allowed a stale or
        // differently-windowed engine projection to make this card look like
        // it contained multiple weeks of muscle volume.
        let volume: [HomeDashboardState.VolumeRow]
        if let restoredWeeklySetsByMuscle {
            volume = volumeRows(setsByMuscle: restoredWeeklySetsByMuscle, tracked: schedule.trackedMuscleGroups)
        } else {
            var currentWeekVolume = snapshot.facts.weeklySetsByGroup
            for (group, delta) in liveVolumeDelta where delta != 0 {
                currentWeekVolume[group, default: 0] += delta
            }
            volume = volumeRows(setsByGroup: currentWeekVolume, tracked: schedule.trackedMuscleGroups)
        }
        // Averaged over the TRACKED rows only, so half a set of incidental neck
        // work cannot drag the headline number down.
        let averageSets = averageCappedSets(volume.filter(\.isTracked).map(\.sets))
        let volumeCoverage = HomeDashboardState.Progress(
            completed: averageSets, target: WeeklySetProgress.maximum,
            displayText: {
                #if os(Linux)
                "\(format(averageSets)) sets"
                #else
                String(localized: "\(format(averageSets)) sets", bundle: FeatureLocalization.bundle)
                #endif
            }(),
            normalized: WeeklySetProgress.normalized(averageSets))
        let cardioDetail = HomeDashboardState.CardioDetail(
            loggedMinutes: weeklyCardio?.actualMinutes ?? balance.loggedAerobicMinutes,
            easyMinutes: weeklyCardio?.belowModerateMinutes ?? balance.easyMinutesLogged,
            moderateMinutes: weeklyCardio?.moderateMinutes ?? balance.moderateMinutesLogged,
            vigorousMinutes: weeklyCardio?.vigorousMinutes ?? balance.vigorousMinutesLogged,
            moderateEquivalentMinutes: cardioCredit,
            targetMinutes: cardioTarget,
            citationID: CitationRegistry.piercy2018PhysicalActivityGuidelines.id,
            citationIDs: [
                CitationRegistry.piercy2018PhysicalActivityGuidelines.id,
                CitationRegistry.swainLeutholtz1997HRR.id,
                CitationRegistry.mezzani2013AerobicIntensity.id,
                CitationRegistry.acsmGarber2011AerobicGuidelines.id
            ],
            belowModerateMinutes: weeklyCardio?.belowModerateMinutes,
            unclassifiedMinutes: weeklyCardio?.unclassifiedMinutes ?? 0,
            zoneMinutes: weeklyCardio?.zoneMinutes ?? [:],
            algorithmVersion: weeklyCardio?.algorithmVersion ?? .legacy)
        return .init(profileContext: .init(goal: goal.displayName, experience: experience.displayName,
                                           ageText: userAge.map(String.init) ?? {
                                               #if os(Linux)
                                               "Age not set"
                                               #else
                                               String(localized: "Age not set", bundle: FeatureLocalization.bundle)
                                               #endif
                                           }()),
                     strength: strength, cardio: cardio, volumeCoverage: volumeCoverage,
                     volume: volume,
                     cardioDetail: cardioDetail, activityDose: activityDose,
                     suggestions: suggestions(snapshot: snapshot, schedule: schedule))
    }

    /// Compatibility helper for callers that still provide an engine observation.
    /// The Home card intentionally uses the app facts as its source of truth:
    /// `TrainingFacts.weeklySetsByGroup` is explicitly Monday-to-now and includes
    /// both catalog and app-created exercises. The engine remains available for
    /// coaching/adherence surfaces, but must not widen this visible week window.
    public static func weeklyVolume(engine: [MuscleGroup: Double]?,
                                    facts: [MuscleGroup: Double]) -> [MuscleGroup: Double] {
        _ = engine
        return facts
    }

    /// The tracked groups still short of a productive week (zero, below the
    /// minimum, or building), most behind first. Uncapped so Fill the Gaps
    /// addresses every gap the muscle-group list shows.
    public static func gapGroups(from rows: [HomeDashboardState.VolumeRow]) -> [MuscleGroup] {
        rows
            .filter { $0.isTracked && ($0.zone == .belowMinimum || $0.zone == .building) }
            .sorted { $0.normalized == $1.normalized
                ? MuscleGroup.canonicalIndex($0.group) < MuscleGroup.canonicalIndex($1.group)
                : $0.normalized < $1.normalized }
            .map(\.group)
    }

    /// Gap groups split by severity, in priority order: no sets at all (missing),
    /// some but under the minimum, then at/above minimum but under recommended.
    public struct GapTiers: Equatable, Sendable {
        public var missing: [MuscleGroup]
        public var belowMinimum: [MuscleGroup]
        public var belowRecommended: [MuscleGroup]
        public init(missing: [MuscleGroup] = [], belowMinimum: [MuscleGroup] = [],
                    belowRecommended: [MuscleGroup] = []) {
            self.missing = missing
            self.belowMinimum = belowMinimum
            self.belowRecommended = belowRecommended
        }
        public var all: [MuscleGroup] { missing + belowMinimum + belowRecommended }
    }

    public static func gapTiers(from rows: [HomeDashboardState.VolumeRow]) -> GapTiers {
        let ordered = Set(gapGroups(from: rows))
        let byGroup = Dictionary(rows.map { ($0.group, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = gapGroups(from: rows).filter(ordered.contains)
        var t = GapTiers()
        for g in groups {
            guard let r = byGroup[g] else { continue }
            if r.zone == .building { t.belowRecommended.append(g) }
            else if r.sets <= 0 { t.missing.append(g) }
            else { t.belowMinimum.append(g) }
        }
        return t
    }

    /// Every tracked muscle group, plus any untracked group the user has actually
    /// trained, alphabetically by displayed name.
    public static func volumeRows(setsByGroup: [MuscleGroup: Double],
                                  tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked)
    -> [HomeDashboardState.VolumeRow] {
        MuscleGroup.allCases.compactMap { group -> HomeDashboardState.VolumeRow? in
            let sets = setsByGroup[group] ?? 0
            let isTracked = tracked.contains(group)
            // An untracked group with no work is noise: the coach does not target
            // it and the user has not trained it, so it does not need a row.
            guard isTracked || sets > 0 else { return nil }
            let zone = WeeklySetProgress.zone(for: sets)
            return .init(group: group,
                         displayName: group.displayName,
                         scientificName: group.scientificName,
                         sets: sets,
                         zone: zone,
                         rangeText: zone.displayText,
                         normalized: WeeklySetProgress.normalized(sets),
                         isTracked: isTracked,
                         citationID: CitationRegistry.iversenTimeEfficient2021.id)
        }
        .sorted {
            let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return order == .orderedSame ? $0.group.rawValue < $1.group.rawValue
                                         : order == .orderedAscending
        }
    }

    /// Convenience for callers holding a raw-value-keyed tally.
    public static func volumeRows(setsByMuscle: [String: Double],
                                  tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked)
    -> [HomeDashboardState.VolumeRow] {
        var byGroup: [MuscleGroup: Double] = [:]
        for (id, sets) in setsByMuscle {
            guard let group = MuscleGroup.canonical(id) else { continue }
            byGroup[group, default: 0] += sets
        }
        return volumeRows(setsByGroup: byGroup, tracked: tracked)
    }

    /// This Week's detailed volume list: largest weekly set count first, with
    /// a stable alphabetical tie-break so it does not jump between renders.
    public static func sortedVolumeRows(_ rows: [HomeDashboardState.VolumeRow])
    -> [HomeDashboardState.VolumeRow] {
        rows.sorted {
            if $0.sets != $1.sets { return $0.sets > $1.sets }
            let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
            return nameOrder == .orderedSame
                ? $0.group.rawValue < $1.group.rawValue
                : nameOrder == .orderedAscending
        }
    }

    private static func suggestions(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences) -> [HomeSuggestion] {
        var candidates: [HomeSuggestion] = snapshot.decision.warnings.map {
            .init(id: $0.id, category: .safety, title: {
                #if os(Linux)
                "Recovery note"
                #else
                String(localized: "Recovery note", bundle: FeatureLocalization.bundle)
                #endif
            }(), message: $0.message,
                  citationID: $0.citationIds.first, sourceClaimKey: "warning:\($0.id)", priority: 100, confidence: 100)
        }
        // Every insight carries a citation. Attention insights are warnings;
        // info insights (trends, what's going well, coaching advice) are shown
        // as neutral progress observations ranked after the warnings, so the
        // card is not empty on a day with nothing urgent. The cold-start
        // placeholder is excluded: it is onboarding, not an observation.
        candidates += snapshot.insights.filter { $0.kind != .coldStart }.map { insight in
            let category: HomeSuggestion.Category = insight.severity == .attention ? .volumeRecovery : .progress
            return .init(id: insight.id, category: category, title: insight.title, message: insight.message,
                         citationID: insight.citation.id, sourceClaimKey: "insight:\(insight.id)",
                         priority: insight.severity.rawValue, confidence: snapshot.decision.confidence.rawValue)
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.sourceClaimKey).inserted }.sorted {
            ($0.category.rawValue, -$0.priority, -$0.confidence, $0.id) <
            ($1.category.rawValue, -$1.priority, -$1.confidence, $1.id)
        }
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func averageCappedSets(_ sets: [Double]) -> Double {
        guard !sets.isEmpty else { return 0 }
        return sets.map { min(max($0, 0), WeeklySetProgress.maximum) }.reduce(0, +) / Double(sets.count)
    }
}
