import SwiftUI
import WidgetKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "figure.strengthtraining.traditional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            if let snapshot = entry.snapshot {
                Text(snapshot.planTitle)
                    .font(.headline)
                    .lineLimit(2)
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
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.green.gradient, for: .widget)
        .widgetURL(URL(string: "cladiron://plan"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let snapshot = entry.snapshot else { return "Open Cladiron to load today's plan" }
        let sessions = snapshot.sessionTitles.isEmpty
            ? "rest or no sessions"
            : snapshot.sessionTitles.joined(separator: ", ")
        return "Today's plan: \(snapshot.planTitle). \(sessions)."
    }
}

@main
struct CadenceWidgets: WidgetBundle {
    var body: some Widget {
        CadenceTodayWidget()
    }
}
