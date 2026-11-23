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
            let tint = tint(for: option)
            Button {
                WatchHaptics.tap()
                selection.wrappedValue.selectAndStart(option)
                selection.wrappedValue.persist()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: option.symbol)
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.16), in: Circle())
                    Text(LocalizedStringKey(option.title))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                // Painterly row backgrounds inside the row are cheaper on the
                // Watch than a custom `.listRowBackground` shape per row.
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
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

/// The Watch List reserves a tall minimum row height by default. Home choices
/// are compact cards, so their own padding defines the spacing instead of
/// leaving a large gap between every row.
struct WatchCompactHomeList: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
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
