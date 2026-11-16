import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WatchHomeStartControls: View {
    let pendingCardio: [WatchCardioCompletion]
    let cardioDestination: (CardioType) -> AnyView
    let fullCardioDestination: () -> AnyView
    let onMoreCardio: () -> Void
    @Environment(\.modelContext) private var context
    @State private var strength: HomeStrengthStartChoice = .quickStart
    @State private var cardio: CardioType?
    @State private var recent: [CardioType] = []

    var body: some View {
        VStack(spacing: 4) {
            Picker("Strength workout", selection: $strength) {
                ForEach(HomeStrengthStartChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.navigationLink)
            NavigationLink {
                switch strength {
                case .quickStart: WatchStrengthView(title: "Strength")
                case .suggested: WatchHomeSuggestedStrengthView()
                case .previous: WatchPreviousListView()
                }
            } label: { Label("Strength", systemImage: "dumbbell.fill") }
                .buttonStyle(WatchPillStyle(kind: .primary))
            NavigationLink {
                WatchHomeCardioChoices(recent: recent, selection: $cardio,
                                       fullCatalog: fullCardioDestination)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cardio workout").font(.caption2).foregroundStyle(.secondary)
                    Text(cardio?.displayName ?? "More..")
                }
            }
            if let cardio {
                NavigationLink { cardioDestination(cardio) } label: {
                    Label("Cardio", systemImage: "figure.run")
                }
                .buttonStyle(WatchCardioPillStyle())
            } else {
                Button(action: onMoreCardio) { Label("Cardio", systemImage: "figure.run") }
                    .buttonStyle(WatchCardioPillStyle())
            }
        }
        .task {
            var descriptor = FetchDescriptor<WatchCardioHistoryRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)])
            descriptor.fetchLimit = WatchSync.CardioHistorySnapshot.maxLiveItems
            let mirrored = ((try? context.fetch(descriptor)) ?? []).map { ($0.start, CardioType(rawValue: $0.typeRaw) ?? .other) }
            let local = pendingCardio.map { ($0.start, $0.type) }
            recent = HomeRecentCardioChoices.recent((mirrored + local).sorted { $0.0 > $1.0 }.map(\.1))
            cardio = recent.first
        }
    }
}

private struct WatchHomeCardioChoices: View {
    let recent: [CardioType]
    @Binding var selection: CardioType?
    let fullCatalog: () -> AnyView
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(recent) { type in
                Button { selection = type; dismiss() } label: {
                    HStack {
                        Text(type.displayName)
                        Spacer()
                        if selection == type { Image(systemName: "checkmark") }
                    }
                }
            }
            NavigationLink(destination: fullCatalog) { Text("More..") }
        }
        .navigationTitle("Cardio workout")
    }
}
