import SwiftUI
import CadenceCore

struct AdaptiveProgressRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Label("History", systemImage: "clock.arrow.circlepath")
                    Label("Personal records", systemImage: "trophy")
                }
                .navigationTitle("Progress")
            } detail: {
                TrainingProgressView()
            }
        } else {
            TrainingProgressView()
        }
    }
}

struct AdaptiveSettingsRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List {
                    Label("Settings", systemImage: "gearshape")
                        .font(.headline)
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                    Label("Health & Sensors", systemImage: "heart.text.square")
                    Label("Watch Sync", systemImage: "applewatch")
                    Label("Data & Privacy", systemImage: "lock.shield")
                }
                .navigationTitle("Settings")
            } detail: {
                SettingsView()
            }
        } else {
            SettingsView()
        }
    }
}

struct AdaptiveSessionRoot: View {
    @Bindable var session: WorkoutSession
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List {
                    Section("Exercises") {
                        ForEach(session.exercisesInOrder) { exercise in
                            Label(exercise.name, systemImage: "dumbbell")
                                .lineLimit(2)
                        }
                    }
                }
                .navigationTitle(session.title.isEmpty ? String(localized: "Workout") : session.title)
            } detail: {
                NavigationStack { SessionView(session: session) }
            }
        } else {
            NavigationStack { SessionView(session: session) }
        }
    }
}
