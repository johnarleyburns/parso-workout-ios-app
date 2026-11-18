import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

enum HomeWeekDashboardScope { case strength, cardio }

struct HomeWeekDashboardSection: View {
    let dashboard: HomeDashboardState
    let scope: HomeWeekDashboardScope
    @Binding var detailSelection: WeeklyDetailSelection
    @Binding var muscleMapPanel: MuscleMapPanel
    let plannedItems: [PlannedWorkoutsPresenter.Item]
    let inProgressSessions: [WorkoutSession]
    let completedEntries: [TodayActivityPresenter.Entry]
    let muscleHistory: [HomeMuscleHistory]
    let muscleHistoryByPerformer: [String: [HomeMuscleHistory]]
    let weeklyVolumeByPerformer: [String: [MuscleGroup: Double]]
    let weeklyVolumeKgByPerformer: [String: Double]
    let weeklyVolumePerformers: [VolumeSummaryPerformer]
    let totalVolumeKg: Double
    var isVolumeLoading = false
    let unit: MeasurementUnitPreference
    let onOpenWorkout: (TodayActivityPresenter.Entry) -> Void
    let onOpenPlanned: (UUID) -> Void
    let onResumeWorkout: (WorkoutSession) -> Void
    let onStartWorkout: (WorkoutSession) -> Void
    let onPlanWorkout: (EditablePlan) -> Void
    let onSuggestCardio: () -> Void
    let onShowHistory: () -> Void
    @State var showsCardioDetails = false
    @State var volumeWarningMessage: String?
    /// A fresh identity on every selection lets SwiftUI present the detail sheet
    /// again even when the user taps the same muscle after dismissing it.
    private struct MuscleDetailSelection: Identifiable {
        let id = UUID()
        let group: MuscleGroup
    }
    @State private var selectedMuscleSelection: MuscleDetailSelection?
    @State private var selectedVolumePerformerKey: String?

    private var selectedVolume: [MuscleGroup: Double] {
        guard let selectedVolumePerformerKey,
              let value = weeklyVolumeByPerformer[selectedVolumePerformerKey] else {
            return Dictionary(uniqueKeysWithValues: dashboard.volume.map { ($0.group, $0.sets) })
        }
        return value
    }

    private var displayedVolumeRows: [HomeDashboardState.VolumeRow] {
        guard !weeklyVolumeByPerformer.isEmpty else { return dashboard.volume }
        let tracked = Set(dashboard.volume.filter(\.isTracked).map(\.group))
        return HomeDashboardPresenter.volumeRows(setsByGroup: selectedVolume,
                                                 tracked: tracked)
    }

    var body: some View {
        AdaptiveDashboardColumns {
            if scope == .strength {
                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        let totals = HomeMuscleMapView.weeklyTotals(for: displayedVolumeRows)
                        HStack {
                            Text("Muscle coverage").font(.headline)
                                .foregroundStyle(CadenceTheme.weeklyTint(WeeklyActivityColor.strength(dashboard.strength.completed)))
                            Spacer()
                            Text("\(WeeklySetProgress.formattedSets(Double(totals.totals))) / \(totals.target) sets")
                                .font(.headline)
                                .foregroundStyle(CadenceTheme.weeklyTint(WeeklyActivityColor.strength(Double(totals.totals))))
                        }
                        muscleMapSummary
                    }
                }
                .id(WeeklyDetailMode.muscleMap)
            }
            if scope == .cardio {
                sectionCard {
                    cardioOverview
                }
                .id(WeeklyDetailMode.cardio)
            }
        }
        .alert("Volume warning", isPresented: Binding(
            get: { volumeWarningMessage != nil },
            set: { if !$0 { volumeWarningMessage = nil } })) {
                Button("OK", role: .cancel) { volumeWarningMessage = nil }
            } message: {
                Text(volumeWarningMessage ?? "")
            }
        .onAppear {
            if selectedVolumePerformerKey == nil {
                selectedVolumePerformerKey = weeklyVolumePerformers.first?.id
            }
        }
        .onChange(of: weeklyVolumePerformers) { _, next in
            let currentKey = selectedVolumePerformerKey
            let selectionStillExists = currentKey.map { key in
                next.contains { performer in performer.id == key }
            } ?? false
            guard !selectionStillExists else { return }
            selectedVolumePerformerKey = next.first?.id
        }
    }


    private func sectionCard<Content: View>(
        @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceCard()
    }

    private var volumeDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                legendItem(String(localized: "Below"), color: .blue)
                legendItem(String(localized: "Building"), color: .yellow)
                legendItem(String(localized: "Productive"), color: .green)
                legendItem(String(localized: "Above"), color: .red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Muscle volume legend: below, building, productive, and above maximum")
            .accessibilityIdentifier("home.week.muscleGroupVolume.heading")
            if weeklyVolumePerformers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weeklyVolumePerformers) { performer in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedVolumePerformerKey = performer.id
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedVolumePerformerKey == performer.id
                                          ? "largecircle.fill.circle" : "circle")
                                    Text(performer.name)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(selectedVolumePerformerKey == performer.id
                                            ? Color.accentColor.opacity(0.14)
                                            : Color.secondary.opacity(0.08),
                                            in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedVolumePerformerKey == performer.id
                                             ? Color.accentColor : .secondary)
                            .accessibilityIdentifier("home.week.muscleGroupVolume.performer.\(performer.id)")
                        }
                    }
                }
                .accessibilityIdentifier("home.week.muscleGroupVolume.performers")
            }
            CoachSourcesLink(
                citationIds: CitationRegistry.strengthVolumePool.citationIds,
                identifier: "home.week.muscleGroupVolume.science")
            HStack {
                Text("Total Volume").font(.subheadline.weight(.semibold))
                Spacer()
                Text(WorkoutMath.tonnageLabel(
                    volumeKg: selectedVolumePerformerKey.flatMap {
                        weeklyVolumeKgByPerformer[$0]
                    } ?? totalVolumeKg,
                    unit: unit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.week.muscleGroupVolume.total")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.week.muscleGroupVolume.expanded")
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private var muscleMapSummary: some View {
        HomeMuscleMapView(
            dashboard: dashboard,
            volumeRows: displayedVolumeRows,
            isLoading: isVolumeLoading,
            selectedPanel: $muscleMapPanel,
            onSelect: { group in
                // Only publish a lightweight value. The detail payload is
                // resolved when the sheet is built, keeping the tap path cheap
                // and giving repeated taps a new sheet identity.
                selectedMuscleSelection = MuscleDetailSelection(group: group)
            })
        .sheet(item: $selectedMuscleSelection) { selection in
            let currentSets = selectedVolume[selection.group] ?? 0
            let selectedHistory = selectedVolumePerformerKey.flatMap {
                muscleHistoryByPerformer[$0]
            } ?? muscleHistory
            let cached = selectedHistory.first(where: { $0.group == selection.group })
            let history = HomeMuscleHistory(
                group: selection.group,
                displayName: cached?.displayName ?? selection.group.displayName,
                creditedSets: currentSets,
                exercises: cached?.exercises ?? [])
            HomeMuscleDetailSheet(history: history, unit: unit)
        }
        .accessibilityIdentifier("home.week.sets.muscleMap")
    }

    private func disclosureRow<Content: View>(title: String, value: String,
                                              progress: Double, tint: Color,
                                              mode: WeeklyDetailMode, identifier: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        let isExpanded = detailSelection.isExpanded(mode)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { detailSelection.toggle(mode) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress).tint(tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isExpanded
                                     ? "\(identifier).showLess"
                                     : "\(identifier).showMore")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                content()
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

}
