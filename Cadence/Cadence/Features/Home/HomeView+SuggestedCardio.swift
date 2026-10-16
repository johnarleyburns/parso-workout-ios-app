import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    /// A cheap, Sendable projection of a cardio record.  The old path decoded
    /// intensity/interval JSON and walked route samples while the Home view's
    /// main actor was trying to present the suggestion.  Keep the render path
    /// to scalar reads and do all history interpretation off-main.
    struct CardioSuggestionSnapshot: Sendable {
        let type: CardioType
        let duration: TimeInterval
        let start: Date
        let intensitySummaryData: String
        let intervalDetailData: String
    }

    /// Captures only value data from recorded cardio. The generator never sees
    /// SwiftData objects, HR samples, routes, or the main-actor dashboard.
    func requestSuggestedCardio() {
        Haptics.selection()
        let snapshots = cardio.compactMap { workout -> CardioSuggestionSnapshot? in
            guard workout.deletedAt == nil, workout.end != nil, workout.duration > 0 else {
                return nil
            }
            return CardioSuggestionSnapshot(type: workout.typeValue,
                                             duration: workout.duration,
                                             start: workout.start,
                                             intensitySummaryData: workout.intensitySummaryData,
                                             intervalDetailData: workout.intervalDetailData)
        }
        let weeklyMinutes = dashboard.cardioDetail.moderateEquivalentMinutes
        let targetMinutes = dashboard.cardioDetail.targetMinutes
        let experience = settings.experienceLevel
        let excludedTypes = settings.excludedCardioTypes
        let excludedProtocolIDs = Set(settings.excludedHIITProtocolIDs)
        skippedHIITProtocolIDs = []
        cancelSuggestedCardioGeneration()
        suggestedCardioCalculating = true
        let task = Task {
            let input = await Task.detached(priority: .userInitiated) {
                Self.cardioSuggestionInput(from: snapshots,
                                            weeklyMinutes: weeklyMinutes,
                                            targetMinutes: targetMinutes,
                                            experience: experience,
                                            excludedTypes: excludedTypes,
                                            excludedProtocolIDs: excludedProtocolIDs,
                                            asOf: Date())
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard suggestedCardioTask != nil else { return }
                suggestedCardioCalculating = false
                suggestedCardioTask = nil
                // The originating Start Workout sheet may still be dismissing.
                // Queue the value-only input and let its onDismiss present it.
                presentSuggestedCardio(input)
            }
        }
        suggestedCardioTask = task
    }

    nonisolated static func cardioSuggestionInput(
        from snapshots: [CardioSuggestionSnapshot],
        weeklyMinutes: Double,
        targetMinutes: Double,
        experience: ExperienceLevel,
        excludedTypes: Set<CardioType>,
        excludedProtocolIDs: Set<String>,
        asOf: Date
    ) -> CardioSuggestionInput {
        let decoder = JSONDecoder()
        let history = snapshots.map { snapshot -> CardioSuggestionHistory in
            let summary = snapshot.intensitySummaryData.data(using: .utf8)
                .flatMap { try? decoder.decode(CardioMinuteSummary.self, from: $0) }
            let actualDuration = summary?.actualDuration ?? snapshot.duration
            let intensity: RelativeIntensity
            if let summary, summary.actualDuration > 0 {
                let vigorousFraction = summary.vigorousDuration / summary.actualDuration
                let moderateFraction = summary.moderateDuration / summary.actualDuration
                if vigorousFraction >= 0.5 {
                    intensity = .vigorous
                } else if moderateFraction >= 0.5 {
                    intensity = .moderate
                } else {
                    intensity = .light
                }
            } else {
                intensity = .unknown
            }
            let moderateEquivalent = summary?.moderateEquivalentMinutes
                ?? snapshot.duration / 60
                    * ((snapshot.type == .hiit || snapshot.type == .boxing) ? 2 : 1)
            let hasIntervalSummary = !snapshot.intervalDetailData.isEmpty
            return CardioSuggestionHistory(
                type: snapshot.type,
                durationMinutes: actualDuration / 60,
                moderateEquivalentMinutes: moderateEquivalent,
                intensity: intensity,
                isInterval: hasIntervalSummary
                    || snapshot.type == .hiit
                    || snapshot.type == .boxing,
                isIndoor: snapshot.type.usesGPS ? nil : true,
                start: snapshot.start)
        }
        return CardioSuggestionInput(history: history,
                                     weeklyModerateEquivalentMinutes: weeklyMinutes,
                                     weeklyTargetMinutes: targetMinutes,
                                     experience: experience,
                                     asOf: asOf,
                                     excludedTypes: excludedTypes,
                                     excludedProtocolIDs: excludedProtocolIDs,
                                     skippedProtocolIDs: [])
    }
}
