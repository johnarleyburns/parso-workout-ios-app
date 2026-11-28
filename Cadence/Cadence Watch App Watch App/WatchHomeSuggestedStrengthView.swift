import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Generates the personalized strength workout locally from the phone-built
/// 12-week mirror. No phone Coach snapshot is consumed here.
struct WatchHomeSuggestedStrengthView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    @Environment(\.modelContext) private var context
    @State private var launch: WatchLiftLaunch?
    @State private var citationIDs: [String] = []
    @State private var finished = false
    @State private var needsSync = false
    @State private var generatedRevision: String?
    @State private var isGenerating = false

    var body: some View {
        Group {
            if let launch {
                WatchStrengthPreview(launch: launch, citationIDs: citationIDs)
            } else if finished && needsSync {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync with iPhone").font(.headline)
                    Text("Open Cladiron on your iPhone once to send your 12-week training history.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("watchStrength.personalized.needsSync")
            } else if finished {
                Text("Couldn't create your Lift. Try again after syncing with iPhone.")
                    .accessibilityIdentifier("watchStrength.personalized.failed")
            } else {
                ProgressView("Preparing your Lift…")
            }
        }
        .navigationTitle("Lift")
        .task { await generateIfNeeded() }
        .onChange(of: manager.mesocycleMirrorRevision) { _, _ in
            Task { @MainActor in await generateIfNeeded() }
        }
    }

    @MainActor
    private func generateIfNeeded() async {
        guard !isGenerating else { return }
        let revision = manager.mesocycleMirrorRevision
        guard WatchSuggestedStrengthRefreshPolicy.shouldGenerate(
            lastRevision: generatedRevision,
            currentRevision: revision,
            hasLaunch: launch != nil) else { return }
        generatedRevision = revision
        isGenerating = true
        defer { isGenerating = false }
        await generate()
    }

    @MainActor
    private func generate() async {
        // Deliberately keep an already visible preview on screen while a newer
        // mirror is assembled. Blanking it here made the Lift screen flash and
        // reload every time the phone refreshed its mirror.
        needsSync = false
        if launch == nil { finished = false }
        guard let envelope = WatchMesocycleMirrorStore().load() else {
            if launch == nil {
                needsSync = true
                finished = true
            }
            return
        }
        let mirror = envelope.mirror
        let result = await Task.detached(priority: .userInitiated) {
            WatchMesocycleInputBuilder.strengthLaunch(from: mirror, now: mirror.generatedAt)
        }.value
        guard !Task.isCancelled else { return }
        if let result {
            launch = prefilled(result.launch)
            citationIDs = result.citationIDs
        } else if launch == nil {
            needsSync = true
        }
        finished = true
    }

    /// Fill the generated suggestion from this Watch's own history once, so the
    /// review screen shows real reps and loads and Start carries them through.
    private func prefilled(_ source: WatchLiftLaunch) -> WatchLiftLaunch {
        let exercises = (try? WorkoutRepository.allExercises(context)) ?? []
        return WatchStrengthPreviewSetup.prefilledSuggestion(source) { name in
            guard let exercise = exercises.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else { return .empty }
            let local = WorkoutRepository.lastTimeSets(for: exercise, performedBy: nil, excluding: nil)
                .filter { !$0.isWarmup }
            return .init(lastSets: local.map { .init(weightKg: $0.weight, reps: $0.reps) })
        }
    }
}
