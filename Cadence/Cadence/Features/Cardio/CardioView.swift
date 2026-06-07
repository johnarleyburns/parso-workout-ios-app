import SwiftUI
import SwiftData
import CadenceCore

/// Cardio home (FR-2.1, FR-2.5): sync Watch workouts from Health, record an
/// iPhone workout, and review cardio history.
struct CardioView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \CardioWorkout.start, order: .reverse) private var workouts: [CardioWorkout]

    @State private var recordPresented = false
    @State private var syncing = false
    @State private var syncMessage: String?

    var body: some View {
        List {
            Section {
                    Button {
                        recordPresented = true
                    } label: { Label("Record Workout", systemImage: "record.circle") }
                        .accessibilityIdentifier("cardio.record")

                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            Label("Sync from Apple Health", systemImage: "heart.text.square")
                            if syncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(syncing)
                    .accessibilityIdentifier("cardio.sync")

                    if let syncMessage {
                        Text(syncMessage).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("cardio.syncMessage")
                    }
                }

                Section("History") {
                    if workouts.isEmpty {
                        Text("No cardio yet — record one or sync from Health.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { w in
                        NavigationLink {
                            CardioDetailView(workout: w)
                        } label: {
                            cardioRow(w)
                        }
                        .accessibilityIdentifier("cardioRow.\(w.typeValue.rawValue)")
                        .swipeActions {
                            Button(role: .destructive) {
                                try? WorkoutRepository.deleteCardio(w, in: context)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        .navigationTitle("Cardio")
        .sheet(isPresented: $recordPresented) {
            RecordCardioView()
        }
        .task { if workouts.isEmpty { await sync() } }
    }

    private func cardioRow(_ w: CardioWorkout) -> some View {
        HStack {
            Image(systemName: w.typeValue.symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.typeValue.displayName).font(.headline)
                Text(w.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.duration(w.duration)).monospacedDigit()
                if let d = w.distance { Text(Format.distance(d)).font(.caption).foregroundStyle(.secondary) }
                if let hr = w.avgHeartRate { Text(Format.heartRate(hr)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func sync() async {
        syncing = true
        defer { syncing = false }
        let new = await model.health.newWorkouts(since: model.lastHealthSync)
        let inserted = (try? WorkoutRepository.ingest(new, in: context)) ?? 0
        model.lastHealthSync = Date()
        syncMessage = inserted == 0 ? "Up to date" : "Imported \(inserted) workout\(inserted == 1 ? "" : "s")"
    }
}
