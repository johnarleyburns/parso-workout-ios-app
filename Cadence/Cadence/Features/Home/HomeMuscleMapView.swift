import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeMuscleMapView: View {
    let dashboard: HomeDashboardState
    let volumeRows: [HomeDashboardState.VolumeRow]?
    /// True until the coach snapshot and weekly activity projection have both
    /// landed; painting earlier would flash every muscle red (issue #195).
    var isLoading = false
    @Binding var selectedPanel: MuscleMapPanel
    let onSelect: (MuscleGroup) -> Void

    private enum MapMetrics {
        static let displayHeight: CGFloat = 440
        static let hitPointSize: CGFloat = 64
    }

    private var rows: [HomeDashboardState.VolumeRow] {
        HomeDashboardPresenter.sortedVolumeRows(volumeRows ?? dashboard.volume)
    }

    /// Weekly tracked-set totals and target, shared with callers that render
    /// the "m / n sets" figure alongside their own header (issue: field
    /// testing wanted this on the same row as "Muscle coverage").
    static func weeklyTotals(for rows: [HomeDashboardState.VolumeRow]) -> (totals: Int, target: Int) {
        let tracked = rows.filter(\.isTracked)
        let totalSets = tracked.reduce(0.0) { $0 + $1.sets }
        return (Int(totalSets.rounded()), tracked.count * 12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MuscleMapPanelTabs(selection: $selectedPanel)
                .accessibilityIdentifier("home.week.muscleMap.picker")

            if isLoading {
                loadingPlaceholder
            } else if selectedPanel == .list {
                muscleList
            } else {
                heatMap
            }

            legend
        }
        .accessibilityHint("Switch to List for all muscles")
        .accessibilityIdentifier("home.week.sets.muscleMap")
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading this week's muscle coverage…")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: MapMetrics.displayHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading this week's muscle coverage")
        .accessibilityIdentifier("home.week.muscleMap.loading")
    }

    private var heatMap: some View {
        let panel = selectedPanel == .front ? MuscleMapPanel.front : .back
        let visibleGroups = Set(rows.map(\.group))
        let callouts = MuscleMapLayout.callouts(for: panel, visibleGroups: visibleGroups)
        let layers = MuscleMapLayout.colourLayers(for: panel, visibleGroups: visibleGroups)
        return GeometryReader { proxy in
            let imageSize = anatomyImageSize(in: proxy.size)
            let imageOrigin = CGPoint(x: (proxy.size.width - imageSize.width) / 2,
                                      y: (proxy.size.height - imageSize.height) / 2)
            ZStack {
                Image(panel == .front ? "MuscleMapFront" : "MuscleMapBack")
                    .resizable().scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .allowsHitTesting(false)
                    .accessibilityLabel("\(panel == .front ? "Front" : "Back") muscle heat map")
                // Untracked muscle takes its nearest tracked group's colour (field report 2026-10-04).
                ForEach(layers) { layer in
                    muscleRegion(for: layer, panel: panel, imageSize: imageSize)
                        .position(x: imageOrigin.x + imageSize.width / 2,
                                  y: imageOrigin.y + imageSize.height / 2)
                }
                ForEach(callouts) { callout in
                    heatButton(for: callout)
                        .position(x: imageOrigin.x + CGFloat(callout.anchorX) * imageSize.width,
                                  y: imageOrigin.y + CGFloat(callout.anchorY) * imageSize.height)
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Keep the artwork large enough that adjacent 44pt hit targets do not
        // stack on top of one another. The targets intentionally exceed
        // Apple's 44pt minimum because this map is used while moving.
        .frame(height: MapMetrics.displayHeight)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private func anatomyImageSize(in container: CGSize) -> CGSize {
        let ratio = MuscleMapLayout.panelRatio
        let height = min(container.height, container.width / ratio)
        return CGSize(width: height * ratio, height: height)
    }

    private func muscleRegion(for layer: MuscleMapColourLayer, panel: MuscleMapPanel,
                              imageSize: CGSize) -> some View {
        let row = rows.first { $0.group == layer.colourGroup }
        let level = MuscleHeatPresenter.level(sets: row?.sets ?? 0, target: 12)
        let mask = Image(MuscleMapLayout.maskAssetName(for: layer.mask, panel: panel))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: imageSize.width, height: imageSize.height)
            .foregroundStyle(muscleColor(for: level))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        return mask
    }

    /// red for 0% · yellow below productive · light green building toward
    /// productive · green productive (field report: muscle-coverage colouring).
    private func muscleColor(for level: HeatLevel) -> Color {
        switch level {
        case .none: return CadenceTheme.muscleZero
        case .low: return CadenceTheme.muscleBelow
        case .mid, .high: return CadenceTheme.muscleBuilding
        case .onTarget: return CadenceTheme.muscleProductive
        }
    }

    private func heatButton(for callout: MuscleMapCallout) -> some View {
        let row = rows.first { $0.group == callout.group }
        let sets = row?.sets ?? 0
        let level = MuscleHeatPresenter.level(sets: sets, target: 12)
        return Button { onSelect(callout.group) } label: {
            Circle().fill(.clear)
                .frame(width: MapMetrics.hitPointSize, height: MapMetrics.hitPointSize)
                .overlay {
                    if level == .none {
                        Circle().inset(by: 9).stroke(CadenceTheme.muscleZero,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(callout.group.displayName), \(WeeklySetProgress.formattedSets(sets)) of 12 sets")
        .accessibilityHint("Shows direct and indirect exercise history")
        .accessibilityIdentifier("home.week.muscle.\(callout.panel.rawValue).\(callout.group.rawValue)")
    }

    private var muscleList: some View {
        List {
            ForEach(rows) { row in
                Button { onSelect(row.group) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.displayName)
                            Spacer()
                            Text("\(WeeklySetProgress.formattedSets(row.sets))/12")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: row.normalized)
                            .tint(muscleColor(for: MuscleHeatPresenter.level(sets: row.sets, target: 12)))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.displayName), \(WeeklySetProgress.formattedSets(row.sets)) of 12 sets this week")
                .accessibilityIdentifier("home.week.muscleMap.list.\(row.group.rawValue)")
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .frame(height: CGFloat(max(1, rows.count) * 58))
        .accessibilityIdentifier("home.week.muscleMap.list")
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem("0 sets", color: CadenceTheme.muscleZero, dashed: true)
            legendItem("Below 4", color: CadenceTheme.muscleBelow)
            legendItem("4–7", color: CadenceTheme.muscleBuilding)
            legendItem("8+", color: CadenceTheme.muscleProductive)
        }
        .font(.headline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Muscle coverage legend: red for zero sets, yellow below the 4-set minimum, light green building toward productive volume, and green for productive volume")
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
                .overlay { if dashed { RoundedRectangle(cornerRadius: 2).stroke(CadenceTheme.attention, style: StrokeStyle(dash: [2, 2])) } }
            Text(title)
        }
    }

}

/// Replaces `Picker(.segmented)`: a native segmented control routes its title
/// text through `UISegmentedControl` appearance plumbing, which doesn't scale
/// with Dynamic Type the way `Text(...).font(.headline)` does, so it drifted
/// out of sync with the "Muscle coverage" title at larger text sizes. This is
/// a real `Text` per option, so it scales identically.
private struct MuscleMapPanelTabs: View {
    @Binding var selection: MuscleMapPanel
    @Namespace private var highlight

    private func title(_ panel: MuscleMapPanel) -> String {
        switch panel {
        case .front: "Front"
        case .back: "Back"
        case .list: "List"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MuscleMapPanel.allCases, id: \.self) { panel in
                Button {
                    selection = panel
                } label: {
                    Text(title(panel))
                        .font(.headline)
                        .foregroundStyle(selection == panel ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selection == panel {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.background)
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.week.muscleMap.picker.\(panel.rawValue)")
                .accessibilityAddTraits(selection == panel ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary))
        .animation(.default, value: selection)
    }
}
