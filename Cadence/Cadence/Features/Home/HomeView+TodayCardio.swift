import SwiftUI
import CadenceCore
import CadenceFeatures

/// "Suggested Cardio for You": always shown below the strength suggestion. It
/// behaves like the strength card — cached suggestion first, a newer one behind
/// an explicit link, Start, and Suggest Another.
struct HomeTodayCardioCard: View {
    let suggestion: CardioSuggestion?
    let isCalculating: Bool
    let hasNewer: Bool
    let onStart: (CardioSuggestion) -> Void
    let onSuggestAnother: (CardioSuggestion) -> Void
    let onShowNewer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Suggested Cardio for You", systemImage: "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(CadenceTheme.accent)
            if let suggestion {
                Text(suggestion.protocolName.map { "\($0) · \(suggestion.type.displayName)" }
                     ?? suggestion.type.displayName)
                    .font(.title3.weight(.bold))
                Text("\(suggestion.durationMinutes) min · \(suggestion.intensity.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(suggestion.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if !suggestion.citationIDs.isEmpty {
                    CoachSourcesLink(
                        citationIds: suggestion.citationIDs,
                        contexts: Dictionary(suggestion.citationIDs.map { ($0, String(localized: "How this cardio suggestion is selected")) },
                                             uniquingKeysWith: { first, _ in first }),
                        identifier: "home.cardio.science")
                }
                if hasNewer {
                    Button("Show newer suggested workout…", action: onShowNewer)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CadenceTheme.link)
                        .accessibilityIdentifier("home.cardio.showNewer")
                }
                Button { onStart(suggestion) } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CadenceTheme.accent)
                .controlSize(.large)
                .accessibilityIdentifier("home.cardio.start")
                Button("Suggest Another") { onSuggestAnother(suggestion) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CadenceTheme.link)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home.cardio.another")
            } else if isCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing your cardio suggestion…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("No cardio suggestion is available right now.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard()
        .accessibilityIdentifier("home.cardio")
    }
}

extension HomeView {
    func cardioSnapshots() -> [CardioSuggestionSnapshot] {
        cardio.compactMap { workout -> CardioSuggestionSnapshot? in
            guard workout.deletedAt == nil, workout.end != nil, workout.duration > 0 else { return nil }
            return CardioSuggestionSnapshot(type: workout.typeValue, duration: workout.duration,
                                            start: workout.start,
                                            intensitySummaryData: workout.intensitySummaryData,
                                            intervalDetailData: workout.intervalDetailData)
        }
    }

    /// Shows today's cached cardio suggestion first, then computes a fresh one in
    /// the background; a different result waits behind "Show newer…".
    func prepareTodayCardio() async {
        guard surface == .today else { return }
        if todayCardio == nil { todayCardio = TodayCardioSuggestionCache().load() }
        let snapshots = cardioSnapshots()
        let weeklyMinutes = dashboard.cardioDetail.moderateEquivalentMinutes
        let targetMinutes = dashboard.cardioDetail.targetMinutes
        let experience = settings.experienceLevel
        let excludedTypes = settings.excludedCardioTypes
        let excludedProtocolIDs = Set(settings.excludedHIITProtocolIDs)
        if todayCardio == nil { todayCardioCalculating = true }
        let (input, fresh) = await Task.detached(priority: .userInitiated) {
            let input = Self.cardioSuggestionInput(from: snapshots, weeklyMinutes: weeklyMinutes,
                                                   targetMinutes: targetMinutes, experience: experience,
                                                   excludedTypes: excludedTypes,
                                                   excludedProtocolIDs: excludedProtocolIDs, asOf: Date())
            return (input, CardioSuggestionGenerator.generate(input: input))
        }.value
        guard !Task.isCancelled else { return }
        todayCardioCalculating = false
        todayCardioInput = input
        guard let fresh else { return }
        switch TodayCardioReplacementGate.decide(displayed: todayCardio, fresh: fresh) {
        case .applyImmediately:
            todayCardio = fresh
            pendingTodayCardio = nil
            TodayCardioSuggestionCache().save(fresh)
        case .holdPending:
            pendingTodayCardio = fresh
        }
    }

    func showNewerTodayCardio() {
        guard let pending = pendingTodayCardio else { return }
        todayCardio = pending
        pendingTodayCardio = nil
        TodayCardioSuggestionCache().save(pending)
    }

    /// Replaces today's cardio suggestion with a different one.
    func suggestAnotherTodayCardio(_ current: CardioSuggestion) {
        guard let base = todayCardioInput else { return }
        if let id = current.protocolID { skippedHIITProtocolIDs.insert(id) }
        func generate(excluding types: Set<CardioType>) -> CardioSuggestion? {
            CardioSuggestionGenerator.generate(input: CardioSuggestionInput(
                history: base.history,
                weeklyModerateEquivalentMinutes: base.weeklyModerateEquivalentMinutes,
                weeklyTargetMinutes: base.weeklyTargetMinutes,
                experience: base.experience, asOf: base.asOf,
                excludedTypes: base.excludedTypes.union(types),
                excludedProtocolIDs: base.excludedProtocolIDs,
                skippedProtocolIDs: skippedHIITProtocolIDs))
        }
        var next = generate(excluding: [])
        if next == nil || next?.id == current.id { next = generate(excluding: [current.type]) }
        guard let next, next.id != current.id else {
            suggestedCardioFailure = String(localized: "No other cardio suggestion is available. You can still pick cardio yourself.")
            return
        }
        todayCardio = next
        pendingTodayCardio = nil
        TodayCardioSuggestionCache().save(next)
    }
}
