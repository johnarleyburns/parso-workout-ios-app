import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WatchHomeStartControls: View {
    let pendingCardio: [WatchCardioCompletion]
    let cardioDestination: (CardioType) -> AnyView
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
            Picker("Cardio workout", selection: $cardio) {
                ForEach(recent) { Text($0.displayName).tag(Optional($0)) }
                Text("More..").tag(Optional<CardioType>.none)
            }
            .pickerStyle(.navigationLink)
            .onChange(of: cardio) { _, next in if next == nil { onMoreCardio() } }
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
