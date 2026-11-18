import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// "Suggested Cardio for You": always shown below the personalized strength workout. It
/// behaves like the strength card — cached suggestion first, a newer one behind
/// an explicit link, Start, and Suggest Another.
struct HomeTodayCardioCard: View {
    let suggestion: CardioSuggestion?
    let completedTitle: String?
    let isCalculating: Bool
    /// True while an explicit "Suggest cardio" request is running.
    let isRequesting: Bool
    let hasNewer: Bool
    /// Opens the review sheet (rationale, citations, Suggest Another); never launches directly.
    let onStart: () -> Void
    let onShowNewer: () -> Void
    /// Explicit "Suggest cardio" action; nil disables it.
    let onRequest: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Personalized Cardio for You", systemImage: "heart.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(CadenceTheme.accent)
            if let completedTitle {
                Label("Cardio Done for Today", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(CadenceTheme.achievement)
                Text(completedTitle).font(.subheadline).foregroundStyle(.secondary)
            } else if let suggestion {
                Text(suggestion.protocolName.map { "\($0) · \(suggestion.type.displayName)" }
                     ?? suggestion.type.displayName)
                    .font(.title3.weight(.bold))
                Text("\(suggestion.durationMinutes) min · \(suggestion.intensity.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if hasNewer {
                    Button("Show newer personalized workout…", action: onShowNewer)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CadenceTheme.link)
                        .accessibilityIdentifier("home.cardio.showNewer")
                }
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CadenceTheme.accent)
                .controlSize(.large)
                .accessibilityIdentifier("home.cardio.start")
            } else if isCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing your personalized cardio workout…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if isRequesting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Suggesting…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Button(onRequest != nil ? "Suggest cardio" : "No personalized cardio workout is available right now.") {
                    onRequest?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(onRequest == nil)
                .accessibilityIdentifier("home.cardio.request")
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

    /// Explicit "Suggest cardio" tap — always generates on tap; nothing runs
    /// automatically on launch or history change.
    func requestCardioSuggestion() {
        guard cardioRequestState != .requesting else { return }
        cardioRequestState = .requesting
        let snapshots = cardioSnapshots()
        let weeklyMinutes = dashboard.cardioDetail.moderateEquivalentMinutes
        let targetMinutes = dashboard.cardioDetail.targetMinutes
        let experience = settings.experienceLevel
        let excludedTypes = settings.excludedCardioTypes
        let excludedProtocolIDs = Set(settings.excludedHIITProtocolIDs)
        Task {
            await ensureCoachSnapshotForExplicitRequest()
            let (input, fresh) = await Task.detached(priority: .userInitiated) {
                let input = Self.cardioSuggestionInput(from: snapshots, weeklyMinutes: weeklyMinutes,
                                                       targetMinutes: targetMinutes, experience: experience,
                                                       excludedTypes: excludedTypes,
                                                       excludedProtocolIDs: excludedProtocolIDs, asOf: Date())
                return (input, CardioSuggestionGenerator.generate(input: input))
            }.value
            guard !Task.isCancelled else { return }
            todayCardioInput = input
            guard let fresh else {
                cardioRequestState = .failed(String(localized: "No personalized cardio workout is available right now."))
                return
            }
            todayCardio = fresh
            pendingTodayCardio = nil
            model.updateWatchCardioSuggestion(WatchCardioSuggestionEnvelope.make(suggestion: fresh, issuedAt: Date()))
            TodayCardioSuggestionCache().save(fresh)
            cardioRequestState = .result
        }
    }

    /// Watch `request_settings_sync`: regenerate and push the personalized cardio workout.
    func refreshWatchCardioSuggestion() {
        guard surface == .today else { return }
        requestCardioSuggestion()
    }

    func showNewerTodayCardio() {
        guard let pending = pendingTodayCardio else { return }
        todayCardio = pending
        pendingTodayCardio = nil
        TodayCardioSuggestionCache().save(pending)
    }

    /// Replaces today's personalized cardio workout with a different one.
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
            suggestedCardioFailure = String(localized: "No other personalized cardio workout is available. You can still pick cardio yourself.")
            return
        }
        todayCardio = next
        pendingTodayCardio = nil
        TodayCardioSuggestionCache().save(next)
    }
}
