import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeMuscleMapView: View {
    let dashboard: HomeDashboardState
    let volumeRows: [HomeDashboardState.VolumeRow]?
    @Binding var selectedPanel: MuscleMapPanel
    let onSelect: (MuscleGroup) -> Void
    let onOpenCardio: () -> Void

    private var rows: [HomeDashboardState.VolumeRow] {
        HomeDashboardPresenter.sortedVolumeRows(volumeRows ?? dashboard.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Muscle view", selection: $selectedPanel) {
                Text("Front").tag(MuscleMapPanel.front)
                Text("Back").tag(MuscleMapPanel.back)
                Text("List").tag(MuscleMapPanel.list)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("home.week.muscleMap.picker")

            if selectedPanel == .list {
                muscleList
            } else {
                heatMap
            }

            let totals = rows.filter(\.isTracked).reduce(0) { $0 + $1.sets }
            let target = rows.filter(\.isTracked).count * 12
            HStack(alignment: .firstTextBaseline) {
                Text("\(WeeklySetProgress.formattedSets(totals))")
                    .font(.title2.weight(.bold)).monospacedDigit()
                Text("/ \(target) sets").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenCardio()
                } label: {
                    Label("Cardio \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) min",
                          systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
            }
            legend
        }
        .accessibilityHint("Switch to List for all muscles")
        .accessibilityIdentifier("home.week.sets.muscleMap")
    }

    private var heatMap: some View {
        let panel = selectedPanel == .front ? MuscleMapPanel.front : .back
        let callouts = MuscleMapLayout.callouts(for: panel)
        return GeometryReader { proxy in
            let imageSize = anatomyImageSize(in: proxy.size)
            let imageOrigin = CGPoint(x: (proxy.size.width - imageSize.width) / 2,
                                      y: (proxy.size.height - imageSize.height) / 2)
            ZStack {
                Image(panel == .front ? "MuscleMapFront" : "MuscleMapBack")
                    .resizable().scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .accessibilityLabel("\(panel == .front ? "Front" : "Back") muscle heat map")
                ForEach(callouts) { callout in
                    muscleRegion(for: callout, imageSize: imageSize)
                        .position(x: imageOrigin.x + imageSize.width / 2,
                                  y: imageOrigin.y + imageSize.height / 2)
                    heatButton(for: callout)
                        .position(x: imageOrigin.x + CGFloat(callout.anchorX) * imageSize.width,
                                  y: imageOrigin.y + CGFloat(callout.anchorY) * imageSize.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 250)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }

    private func anatomyImageSize(in container: CGSize) -> CGSize {
        let ratio = MuscleMapLayout.panelRatio
        let height = min(container.height, container.width / ratio)
        return CGSize(width: height * ratio, height: height)
    }

    private func muscleRegion(for callout: MuscleMapCallout, imageSize: CGSize) -> some View {
        let row = rows.first { $0.group == callout.group }
        let level = MuscleHeatPresenter.level(sets: row?.sets ?? 0, target: 12)
        return Image("MuscleMask-\(callout.panel.rawValue)-\(callout.group.rawValue)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: imageSize.width, height: imageSize.height)
            .foregroundStyle(CadenceTheme.accent.opacity(opacity(for: level)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func heatButton(for callout: MuscleMapCallout) -> some View {
        let row = rows.first { $0.group == callout.group }
        let sets = row?.sets ?? 0
        let level = MuscleHeatPresenter.level(sets: sets, target: 12)
        return Button { onSelect(callout.group) } label: {
            Circle().fill(.clear).frame(width: 44, height: 44)
                .overlay {
                    if level == .none {
                        Circle().inset(by: 8).stroke(CadenceTheme.attention,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    }
                }
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
                            Text(row.rangeText).font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: row.normalized).tint(CadenceTheme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.displayName), \(row.rangeText)")
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
            legendItem("0", color: CadenceTheme.attention, dashed: true)
            legendItem("< ⅓", color: CadenceTheme.accent.opacity(0.25))
            legendItem("⅓–½", color: CadenceTheme.accent.opacity(0.45))
            legendItem("½–¾", color: CadenceTheme.accent.opacity(0.7))
            legendItem("on target", color: CadenceTheme.accent)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Muscle coverage legend: zero, under one third, one third to one half, one half to three quarters, and on target")
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
                .overlay { if dashed { RoundedRectangle(cornerRadius: 2).stroke(CadenceTheme.attention, style: StrokeStyle(dash: [2, 2])) } }
            Text(title)
        }
    }

    private func opacity(for level: HeatLevel) -> Double {
        switch level {
        case .none: return 0.12
        case .low: return 0.25
        case .mid: return 0.45
        case .high: return 0.7
        case .onTarget: return 1
        }
    }
}
