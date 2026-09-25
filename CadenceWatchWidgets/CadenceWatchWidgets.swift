import SwiftUI
import WidgetKit
import CadenceFeatures

struct CadenceWatchWidgetEntry: TimelineEntry {
    let date: Date
    let state: CadenceWatchWidgetState?
    let snapshot: CadenceTodaySnapshot?
}

struct CadenceWatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenceWatchWidgetEntry {
        CadenceWatchWidgetEntry(
            date: Date(),
            state: CadenceWatchWidgetState(workoutTitle: "Upper strength"),
            snapshot: CadenceTodaySnapshot(
                dayKey: "preview",
                planTitle: "Upper strength",
                sessionTitles: ["Strength session"]))
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceWatchWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<CadenceWatchWidgetEntry>) -> Void) {
        let current = Date()
        let nextRefresh: Date
        if let restEndsAt = CadenceWatchWidgetStore.load()?.restEndsAt,
           restEndsAt > current {
            nextRefresh = min(restEndsAt, current.addingTimeInterval(60))
        } else {
            nextRefresh = current.addingTimeInterval(30 * 60)
        }
        completion(Timeline(entries: [entry(date: current)], policy: .after(nextRefresh)))
    }

    private func entry(date: Date = Date()) -> CadenceWatchWidgetEntry {
        CadenceWatchWidgetEntry(
            date: date,
            state: CadenceWatchWidgetStore.load(),
            snapshot: CadencePlatformSnapshotStore.load())
    }
}

struct CadenceWatchSmartStackView: View {
    let entry: CadenceWatchWidgetEntry

    var body: some View {
        Group {
            if let restEndsAt = entry.state?.restEndsAt, restEndsAt > Date() {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Rest", systemImage: "timer")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(timerInterval: Date()...restEndsAt, countsDown: true)
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(entry.state?.workoutTitle ?? "Workout")
                        .font(.caption2)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(entry.state?.workoutTitle ?? entry.snapshot?.planTitle ?? "Open Cladiron")
                        .font(.headline)
                        .lineLimit(2)
                    if let session = entry.snapshot?.sessionTitles.first {
                        Text(session)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .containerBackground(.green.gradient, for: .widget)
        .widgetURL(URL(string: "cladiron://plan"))
    }
}

struct CadenceWatchSmartStackWidget: Widget {
    let kind = "CadenceWatchSmartStackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceWatchWidgetProvider()) { entry in
            CadenceWatchSmartStackView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("See today's workout or the active rest timer.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct CadenceWatchWidgets: WidgetBundle {
    var body: some Widget {
        CadenceWatchSmartStackWidget()
    }
}
