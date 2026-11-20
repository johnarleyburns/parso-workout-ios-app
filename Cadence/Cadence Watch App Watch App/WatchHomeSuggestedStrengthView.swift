import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Generates the personalized strength workout locally from the phone-built
/// 12-week mirror. No phone Coach snapshot is consumed here.
struct WatchHomeSuggestedStrengthView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    @State private var launch: WatchLiftLaunch?
    @State private var citationIDs: [String] = []
    @State private var finished = false
    @State private var needsSync = false

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
        .task(id: manager.mesocycleMirrorRevision) {
            await generate()
        }
    }

    @MainActor
    private func generate() async {
        launch = nil
        citationIDs = []
        needsSync = false
        finished = false
        guard let envelope = WatchMesocycleMirrorStore().load() else {
            needsSync = true
            finished = true
            return
        }
        let mirror = envelope.mirror
        let result = await Task.detached(priority: .userInitiated) {
            WatchMesocycleInputBuilder.strengthLaunch(from: mirror, now: mirror.generatedAt)
        }.value
        guard !Task.isCancelled else { return }
        if let result {
            launch = result.launch
            citationIDs = result.citationIDs
        }
        finished = true
    }
}
