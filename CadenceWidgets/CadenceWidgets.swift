import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents
import CadenceFeatures

struct CadenceTodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceTodaySnapshot?
}

struct CadenceTodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenceTodayWidgetEntry {
        CadenceTodayWidgetEntry(
            date: Date(),
            snapshot: CadenceTodaySnapshot(dayKey: "preview", planTitle: "Today's plan",
                                            sessionTitles: ["Strength session", "Mobility"],
                                            readinessLabel: "Recovery looks good"))
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceTodayWidgetEntry) -> Void) {
        completion(CadenceTodayWidgetEntry(date: Date(), snapshot: snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceTodayWidgetEntry>) -> Void) {
        let entry = CadenceTodayWidgetEntry(date: Date(), snapshot: snapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func snapshot() -> CadenceTodaySnapshot? {
        CadencePlatformSnapshotStore.load()
    }
}

struct CadenceTodayWidget: Widget {
    let kind = "CadenceTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceTodayWidgetProvider()) { entry in
            CadenceTodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's workout")
        .description("See today's plan and readiness at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CadenceTodayWidgetView: View {
    let entry: CadenceTodayWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "figure.strengthtraining.traditional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                if let snapshot = entry.snapshot {
                    Text(snapshot.planTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if family == .systemMedium {
                        HStack(spacing: 10) {
                            widgetRing("Sets", symbol: "circle")
                            widgetRing("Cardio", symbol: "heart")
                            widgetRing("Sessions", symbol: "figure.strengthtraining.traditional")
                        }
                    }
                if snapshot.sessionTitles.isEmpty {
                    Text("Rest or add a session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(snapshot.sessionTitles.prefix(3)), id: \.self) { title in
                        Text(title)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                if let readinessLabel = snapshot.readinessLabel {
                    Text(readinessLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Open Cladiron to load today's plan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if family == .systemSmall, entry.snapshot != nil {
                Button(intent: WidgetStartWorkoutIntent()) {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                }
                .tint(.green)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.green.gradient, for: .widget)
        .widgetURL(URL(string: "cladiron://plan"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func widgetRing(_ title: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.green)
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityLabel: String {
        guard let snapshot = entry.snapshot else { return "Open Cladiron to load today's plan" }
        let sessions = snapshot.sessionTitles.isEmpty
            ? "rest or no sessions"
            : snapshot.sessionTitles.joined(separator: ", ")
        return "Today's plan: \(snapshot.planTitle). \(sessions)."
    }
}

struct WidgetStartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription("Open Cladiron to start today's workout.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var elapsedSeconds: Int
        var isPaused: Bool
        var restEndsAt: Date?
        var nextExercise: String?
    }
    var workoutTitle: String
}

struct CadenceWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.restEndsAt == nil ? "figure.strengthtraining.traditional" : "timer")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.restEndsAt == nil ? context.attributes.workoutTitle : "Rest")
                        .font(.headline)
                    if let end = context.state.restEndsAt {
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.title2.weight(.bold)).monospacedDigit()
                    } else {
                        Text(Format.duration(TimeInterval(context.state.elapsedSeconds)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let next = context.state.nextExercise {
                    Text(next).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer").foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = context.state.restEndsAt {
                        Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.nextExercise ?? context.attributes.workoutTitle)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.green)
            } compactTrailing: {
                if let end = context.state.restEndsAt {
                    Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
                } else {
                    Text(Format.duration(TimeInterval(context.state.elapsedSeconds))).monospacedDigit()
                }
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.green)
            }
        }
    }
}

@available(iOS 18.0, *)
struct CadenceStartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CadenceStartWorkoutControl") {
            ControlWidgetButton(action: WidgetStartWorkoutIntent()) {
                Label("Start workout", systemImage: "play.fill")
            }
            .tint(.green)
        }
        .displayName("Start workout")
        .description("Open Cladiron and start today's workout.")
    }
}

@main
struct CadenceWidgets: WidgetBundle {
    var body: some Widget {
        CadenceTodayWidget()
        CadenceWorkoutLiveActivity()
        if #available(iOS 18.0, *) {
            CadenceStartControl()
        }
    }
}
