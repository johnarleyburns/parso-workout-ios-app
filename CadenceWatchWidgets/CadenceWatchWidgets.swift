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
            state: CadenceWatchWidgetState(workoutTitle: String(localized: "Upper strength")),
            snapshot: CadenceTodaySnapshot(
                dayKey: "preview",
                planTitle: String(localized: "Upper strength"),
                sessionTitles: [String(localized: "Strength session")]))
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

/// Watch redesign A2 — during rest: a ring that drains to the end of rest, the countdown, and the
/// next set; outside a workout: today's plan with Start (`cladiron://start`, the same path as the
/// Action Button). The rest ring and countdown are system-driven, so they stay live with no reloads.
struct CadenceWatchSmartStackView: View {
    let entry: CadenceWatchWidgetEntry

    var body: some View {
        Group {
            if let state = entry.state, let restEndsAt = state.restEndsAt, restEndsAt > entry.date {
                rest(state: state, endsAt: restEndsAt)
                    .widgetURL(URL(string: "cladiron://workout"))
            } else if let state = entry.state {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(state.workoutTitle).font(.headline).lineLimit(1)
                    if let next = state.nextSet {
                        Text("Next · \(next)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .widgetURL(URL(string: "cladiron://workout"))
            } else {
                today
                    .widgetURL(URL(string: "cladiron://start"))
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    private func rest(state: CadenceWatchWidgetState, endsAt: Date) -> some View {
        let total = TimeInterval(max(1, state.restTotalSeconds ?? 90))
        let startedAt = min(entry.date, endsAt.addingTimeInterval(-total))
        return HStack(spacing: 8) {
            ProgressView(timerInterval: startedAt...endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "timer").font(.caption2)
            }
            .progressViewStyle(.circular)
            .tint(accent)
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(timerInterval: entry.date...endsAt, countsDown: true)
                    .font(.title3.weight(.bold).monospacedDigit())
                if let next = state.nextSet {
                    Text("Next · \(next)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(state.workoutTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Rest"))
    }

    private var today: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Today", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                Text(entry.snapshot?.planTitle ?? String(localized: "Open Cladiron"))
                    .font(.headline)
                    .lineLimit(1)
                if let session = entry.snapshot?.sessionTitles.first {
                    Text(session).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.snapshot?.sessionTitles.isEmpty == false {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent))
                    .accessibilityLabel(Text("Start"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var accent: Color { Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255) }
}

struct CadenceWatchSmartStackWidget: Widget {
    let kind = "CadenceWatchSmartStackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceWatchWidgetProvider()) { entry in
            CadenceWatchSmartStackView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today's plan with Start, or your rest and next set during a workout.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct CadenceWatchWidgets: WidgetBundle {
    var body: some Widget {
        CadenceWatchSmartStackWidget()
    }
}
