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
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                selectorTitle("Strength")
                Picker("Strength workout", selection: $strength) {
                    ForEach(HomeStrengthStartChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 60)
                .accessibilityIdentifier("watch.strengthPicker")

                NavigationLink {
                    switch strength {
                    case .quickStart: WatchStrengthView(title: "Strength")
                    case .suggested: WatchHomeSuggestedStrengthView()
                    case .previous: WatchPreviousListView()
                    }
                } label: {
                    startLabel("Start strength")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("watch.startStrength")
            }

            VStack(spacing: 4) {
                selectorTitle("Cardio")
                Picker("Cardio workout", selection: $cardio) {
                    ForEach(recent) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                    Text("More…").tag(Optional<CardioType>.none)
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 60)
                .accessibilityIdentifier("watch.cardioPicker")

                if let cardio {
                    NavigationLink { cardioDestination(cardio) } label: {
                        startLabel("Start cardio")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityIdentifier("watch.startCardio")
                } else {
                    Button(action: onMoreCardio) { startLabel("Start cardio") }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .accessibilityIdentifier("watch.startCardio")
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .task {
            var descriptor = FetchDescriptor<WatchCardioHistoryRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)])
            descriptor.fetchLimit = WatchSync.CardioHistorySnapshot.maxLiveItems
            let mirrored = ((try? context.fetch(descriptor)) ?? []).map { ($0.start, CardioType(rawValue: $0.typeRaw) ?? .other) }
            let local = pendingCardio.map { ($0.start, $0.type) }
            recent = HomeRecentCardioChoices.recent((mirrored + local).sorted { $0.0 > $1.0 }.map(\.1))
            cardio = recent.first
        }
    }

    private func selectorTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func startLabel(_ workout: LocalizedStringKey) -> some View {
        Label(workout, systemImage: "play.fill")
            .font(.caption.bold())
            .frame(maxWidth: .infinity, minHeight: 28)
    }
}
