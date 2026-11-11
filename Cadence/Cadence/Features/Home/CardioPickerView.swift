import SwiftUI
import CadenceCore
import CadenceFeatures

/// Shared cardio choice surface. Start mode has no schedule controls on the
/// cardio tiles; scheduling is a separate intent reached by the bottom action.
/// Start mode leads with this week's credit and the Suggest Cardio action;
/// the section order comes from `CardioPickerLayoutPresenter`.
struct CardioPickerView: View {
    let mode: CardioPickerMode
    let recentCardioTypes: [WorkoutType]
    let onSelect: (WorkoutType) -> Void
    let onSchedule: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var onSuggestCardio: (() -> Void)? = nil
    /// Prepared by Home from its cached dashboard; the picker never computes it.
    var weeklyCredit: CardioWeeklyCreditDisplay? = nil
    @State private var expanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    private let cardioTypes: [WorkoutType] = [
        .run, .walk, .cycle, .rowing, .swim, .elliptical, .stairClimber,
        .hiit, .boxing, .other
    ]
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var initialTypes: [WorkoutType] {
        CardioStartChoicesPresenter.initial(recent: recentCardioTypes,
                                            all: cardioTypes.filter { $0 != .other })
    }

    private var additionalTypes: [WorkoutType] {
        CardioStartChoicesPresenter.remaining(initial: initialTypes, all: cardioTypes)
    }

    private var sections: [CardioPickerSection] {
        CardioPickerLayoutPresenter.sections(for: mode,
                                             showsWeeklyCredit: weeklyCredit != nil,
                                             showsSuggestCardio: onSuggestCardio != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections, id: \.self) { section in
                    sectionContent(section)
                }
            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .navigationTitle(mode == .start ? String(localized: "Cardio This Week")
                                        : String(localized: "Schedule Cardio"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(mode == .start ? "cardioPicker" : "cardioPicker.scheduleMode")
    }

    @ViewBuilder
    private func sectionContent(_ section: CardioPickerSection) -> some View {
        switch section {
        case .weeklyCredit:
            if let weeklyCredit { CardioWeeklyCreditSurface(display: weeklyCredit) }
        case .suggestCardio:
            if let onSuggestCardio { suggestCardioButton(onSuggestCardio) }
        case .excludedTypesNoteWhenPresent:
            excludedTypesNote
        case .cardioSection:
            Text("Cardio")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("cardioPicker.cardioSection")
        case .typeGrid:
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(initialTypes) { type in cardioChoice(type) }
            }
        case .showMore:
            showMoreContent
        }
    }

    private func suggestCardioButton(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars").font(.headline)
                Text("Suggest Cardio").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .cadenceActionLabel()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("pickCardio.suggestCardio")
        .accessibilityHint("Suggests one cardio session from your history and weekly goal, with the science behind it. You review it before starting.")
    }

    private var showMoreContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(expanded ? "Show less" : "Show more…")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity,
                       minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardioPicker.showMore")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(additionalTypes.filter { $0 != .other }) { type in
                        cardioChoice(type)
                    }
                    otherCardioChoice
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Transparency: lists modalities hidden from suggestions and lets the user undo.
    @ViewBuilder
    private var excludedTypesNote: some View {
        let excluded = settings.excludedCardioTypes.sorted { $0.rawValue < $1.rawValue }
        let excludedProtocols = settings.excludedHIITProtocolIDs.compactMap(HIITProtocol.find(id:))
        if !excluded.isEmpty || !excludedProtocols.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Never suggested (you can still pick them below):")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(excluded, id: \.self) { type in
                    HStack {
                        Text(type.displayName).font(.footnote)
                        Spacer()
                        Button("Allow again") { settings.setCardioTypeExcluded(type, false) }
                            .font(.footnote)
                            .accessibilityLabel("Allow \(type.displayName) in suggestions again")
                    }
                }
                ForEach(excludedProtocols) { hiit in
                    HStack {
                        Text(hiit.name).font(.footnote)
                        Spacer()
                        Button("Allow again") { settings.setHIITProtocolExcluded(hiit.id, false) }
                            .font(.footnote)
                            .accessibilityLabel("Allow \(hiit.name) in suggestions again")
                    }
                }
            }
            .accessibilityIdentifier("pickCardio.excludedTypes")
        }
    }

    private func cardioChoice(_ type: WorkoutType) -> some View {
        Button {
            dismiss()
            if mode == .start { onSelect(type) } else { onSchedule(type) }
        } label: {
            WorkoutHero(type: type, compact: true)
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .accessibilityIdentifier("cardioPicker.\(mode == .start ? "start" : "schedule").\(type.rawValue)")
        .accessibilityLabel(mode == .start ? "Start \(type.displayName)" : "Schedule \(type.displayName)")
    }

    @ViewBuilder
    private var otherCardioChoice: some View {
        if mode == .start {
            NavigationLink { OtherCardioEntryView(onStart: onOtherCardio) } label: {
                WorkoutHero(type: .other, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardioPicker.start.other")
        } else {
            Button {
                dismiss()
                onSchedule(.other)
            } label: {
                WorkoutHero(type: .other, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardioPicker.schedule.other")
        }
    }
}

/// This week's moderate-equivalent cardio credit: a determinate system
/// circular ring plus the exact "m of n min credit" text, read by VoiceOver
/// as one element. Colors come from the shared weekly cardio tint policy.
struct CardioWeeklyCreditSurface: View {
    let display: CardioWeeklyCreditDisplay
    @ScaledMetric(relativeTo: .title) private var ringDiameter: CGFloat = 64

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: display.normalizedProgress)
                .progressViewStyle(.circular)
                .controlSize(.extraLarge)
                .tint(CadenceTheme.weeklyTint(display.tintRole))
                .frame(width: ringDiameter, height: ringDiameter)
                .accessibilityIdentifier(CardioWeeklyCreditDisplay.Identifier.ring)
            Text(display.visibleText)
                .font(.headline.monospacedDigit())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(CardioWeeklyCreditDisplay.Identifier.value)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityValue(display.accessibilityValue)
        .accessibilityIdentifier(CardioWeeklyCreditDisplay.Identifier.surface)
    }
}
