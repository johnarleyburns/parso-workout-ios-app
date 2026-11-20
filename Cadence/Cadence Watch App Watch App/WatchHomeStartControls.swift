import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension WatchRootView {
    /// One scrollable-list row per phone workout choice. Tapping a row both
    /// selects and launches it; the parent `List` owns the scrolling.
    @ViewBuilder
    func homeWorkoutChoiceRows(selection: Binding<WatchHomeWorkoutSelection>) -> some View {
        ForEach(selection.wrappedValue.choices) { option in
            Button {
                WatchHaptics.tap()
                selection.wrappedValue.selectAndStart(option)
                selection.wrappedValue.persist()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: option.symbol)
                        .foregroundStyle(tint(for: option))
                        .frame(width: 26, height: 26)
                        .background(tint(for: option).opacity(0.16), in: Circle())
                    Text(LocalizedStringKey(option.title))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(tint(for: option).opacity(0.12)))
            .accessibilityIdentifier("watch.workoutChoice.\(option.id)")
            .accessibilityHint("Starts or opens \(option.title)")
        }
    }

    private func tint(for option: HomeWorkoutStartChoice) -> Color {
        switch option {
        case .strength, .cardio(.weights): return WatchTone.accent
        case .suggestedCardio: return WatchTone.gold
        case .cardio(.hiit), .cardio(.boxing): return WatchTone.heart
        case .cardio(.swim): return .teal
        case .cardio(.rowing): return WatchTone.cardio
        case .cardio(.cycle), .cardio(.elliptical), .cardio(.stairClimber): return .indigo
        case .cardio(.run), .cardio(.walk): return .orange
        case .cardio(.other): return .pink
        }
    }
}

/// Attach outside the List's lazy rows so navigation destinations are always
/// registered, and the home toolbar stays anchored to the screen corners.
struct WatchHomeStartNavigation: ViewModifier {
    @Binding var selection: WatchHomeWorkoutSelection
    let cardioDestination: (CardioType) -> AnyView
    let suggestedCardioDestination: () -> AnyView

    func body(content: Content) -> some View {
        content
        .navigationDestination(item: Binding(
            get: { selection.launchChoice },
            set: { if $0 == nil { selection.dismissStart() } })) { choice in
                destination(for: choice)
            }
    }

    @ViewBuilder
    private func destination(for choice: HomeWorkoutStartChoice) -> some View {
        switch choice {
        case .strength(.suggested):
            WatchHomeSuggestedStrengthView()
        case .cardio(let type):
            if let cardio = type.cardioType { cardioDestination(cardio) }
        case .suggestedCardio:
            suggestedCardioDestination()
        }
    }
}
