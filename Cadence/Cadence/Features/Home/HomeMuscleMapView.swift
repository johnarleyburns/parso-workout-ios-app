import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeMuscleMapView: View {
    let dashboard: HomeDashboardState
    let volumeRows: [HomeDashboardState.VolumeRow]?
    @Binding var selectedPanel: MuscleMapPanel
    let onSelect: (MuscleGroup) -> Void
    let onOpenCardio: () -> Void

    var body: some View {
        // The map must mirror the rows currently rendered by Volume exactly.
        // Using `isTracked` here dropped real rows that were present because a
        // user had performed work for a previously untracked group.
        let displayedGroups = Set((volumeRows ?? dashboard.volume).map(\.group))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                panelSegment(.front)
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 1, height: 18)
                    .accessibilityHidden(true)
                panelSegment(.back)
            }
            .padding(3)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sets per muscle group view")
            MuscleMapSideView(
                panel: selectedPanel,
                title: selectedPanel == .front ? "FRONT" : "BACK",
                callouts: MuscleMapLayout.callouts(for: selectedPanel)
                    .filter { displayedGroups.contains($0.group) },
                setsLabel: setsLabel(for:),
                statusColor: statusColor(for:),
                onSelect: onSelect)
            Button(action: onOpenCardio) {
                Label("Cardio · \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded()))/\(Int(dashboard.cardioDetail.targetMinutes.rounded())) min credit",
                      systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cardio, \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) of \(Int(dashboard.cardioDetail.targetMinutes.rounded())) minutes credit this week")
            Text("Tap a highlighted muscle for this week's direct and indirect work")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func panelSegment(_ panel: MuscleMapPanel) -> some View {
        let selected = selectedPanel == panel
        return Button {
            guard selectedPanel != panel else { return }
            Haptics.selection()
            selectedPanel = panel
        } label: {
            Text(panel == .front ? "Front" : "Back")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.16) : .clear,
                            in: Capsule())
        }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.week.sets.muscleMap.\(panel.rawValue)")
        .accessibilityLabel(panel == .front ? "Front" : "Back")
    }

    private func setsLabel(for group: MuscleGroup) -> String {
        let sets = (volumeRows ?? dashboard.volume).first(where: { $0.group == group })?.sets ?? 0
        return "\(WeeklySetProgress.formattedSets(sets))/12"
    }

    private func statusColor(for group: MuscleGroup) -> Color {
        guard let row = (volumeRows ?? dashboard.volume).first(where: { $0.group == group }) else { return .blue }
        switch row.zone {
        case .belowMinimum: return .blue
        case .building: return .yellow
        case .productive: return .green
        case .aboveMaximum: return .red
        }
    }
}

private struct MuscleMapSideView: View {
    let panel: MuscleMapPanel
    let title: String
    let callouts: [MuscleMapCallout]
    let setsLabel: (MuscleGroup) -> String
    let statusColor: (MuscleGroup) -> Color
    let onSelect: (MuscleGroup) -> Void

    // The selected panel is shown at a useful portrait size, with a label column
    // on each side. The artwork is a pre-rendered panel-local asset: do not
    // reintroduce a combined SVG crop here because Xcode's SVG importer does
    // not preserve this source's complex Inkscape coordinate system faithfully.
    private let labelWidth: CGFloat = 84
    private let imageWidth: CGFloat = 128
    private let rowHeight: CGFloat = 36
    private let rowSpacing: CGFloat = 3

    private var imageHeight: CGFloat { imageWidth / CGFloat(MuscleMapLayout.panelRatio) }
    private var leftCallouts: [MuscleMapCallout] {
        callouts.filter { $0.side == .left }
    }
    private var rightCallouts: [MuscleMapCallout] {
        callouts.filter { $0.side == .right }
    }
    private func columnHeight(for callouts: [MuscleMapCallout]) -> CGFloat {
        let rows = callouts.count
        return CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowSpacing
    }
    private var columnHeight: CGFloat {
        max(columnHeight(for: leftCallouts), columnHeight(for: rightCallouts))
    }
    private var contentHeight: CGFloat {
        max(imageHeight, columnHeight)
    }
    private var canvasWidth: CGFloat { labelWidth * 2 + imageWidth + 8 }
    private func columnTop(for callouts: [MuscleMapCallout]) -> CGFloat {
        (contentHeight - columnHeight(for: callouts)) / 2
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            ZStack {
                HStack(spacing: 4) {
                    calloutColumn(leftCallouts, alignment: .trailing)
                    image
                    calloutColumn(rightCallouts, alignment: .leading)
                }
                connectorLines
            }
            .frame(width: canvasWidth, height: contentHeight)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title.lowercased()) sets per muscle group")
    }

    private func calloutColumn(_ callouts: [MuscleMapCallout], alignment: HorizontalAlignment) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(callouts) { callout in
                Button {
                    onSelect(callout.group)
                } label: {
                    Text("\(callout.group.displayName)\n\(setsLabel(callout.group))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: alignment == .trailing ? .trailing : .leading)
                        .padding(.horizontal, 4)
                        .background(statusColor(callout.group).opacity(0.20),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(statusColor(callout.group).opacity(0.65), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: labelWidth, height: rowHeight)
                .contentShape(Rectangle())
                .accessibilityLabel("\(callout.group.displayName), \(setsLabel(callout.group)) this week")
                .accessibilityHint("Shows direct and indirect exercise history")
                .accessibilityIdentifier("home.week.muscle.\(callout.panel.rawValue).\(callout.group.rawValue)")
            }
        }
        .frame(width: labelWidth, height: columnHeight(for: callouts), alignment: .center)
    }

    private var image: some View {
        ZStack(alignment: .topLeading) {
            // Preserve the source artwork's alpha channel. The map is placed on
            // the dashboard card, so an opaque backing would turn the empty
            // space around the anatomy white on dark themes.
            Color.clear
            Image(panel == .front ? "MuscleMapFront" : "MuscleMapBack")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: imageWidth, height: imageHeight)
                .accessibilityHidden(true)
        }
        .frame(width: imageWidth, height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipped()
    }

    private var connectorLines: some View {
        Canvas { context, size in
            let imageOriginX: CGFloat = labelWidth + 4
            let imageOriginY = (contentHeight - imageHeight) / 2
            for (index, callout) in leftCallouts.enumerated() {
                drawConnector(context: &context, callout: callout,
                              rowY: columnTop(for: leftCallouts) + CGFloat(index) * (rowHeight + rowSpacing) + rowHeight / 2,
                              imageOriginX: imageOriginX, imageOriginY: imageOriginY,
                              startX: labelWidth)
            }
            for (index, callout) in rightCallouts.enumerated() {
                drawConnector(context: &context, callout: callout,
                              rowY: columnTop(for: rightCallouts) + CGFloat(index) * (rowHeight + rowSpacing) + rowHeight / 2,
                              imageOriginX: imageOriginX, imageOriginY: imageOriginY,
                              startX: labelWidth + 4 + imageWidth + 4)
            }
        }
        .allowsHitTesting(false)
        .frame(width: canvasWidth, height: contentHeight)
    }

    private func drawConnector(context: inout GraphicsContext,
                               callout: MuscleMapCallout,
                               rowY: CGFloat,
                               imageOriginX: CGFloat,
                               imageOriginY: CGFloat,
                               startX: CGFloat) {
        let anchorX = imageOriginX + CGFloat(callout.anchorX) * imageWidth
        let anchorY = imageOriginY + CGFloat(callout.anchorY) * imageHeight
        var path = Path()
        path.move(to: CGPoint(x: startX, y: rowY))
        path.addLine(to: CGPoint(x: anchorX, y: anchorY))
        context.stroke(path,
                       with: .color(statusColor(callout.group).opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }
}
#if DEBUG
#Preview("Muscle-map asset calibration") {
    MuscleMapCalibrationPreview()
}

private struct MuscleMapCalibrationPreview: View {
    @State private var panel: MuscleMapPanel = .front

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("Panel", selection: $panel) {
                    Text("Front").tag(MuscleMapPanel.front)
                    Text("Back").tag(MuscleMapPanel.back)
                }
                .pickerStyle(.segmented)
                HStack(alignment: .top, spacing: 10) {
                    referencePanel(title: "Combined source", imageName: "MusclesFrontBack", panel: nil)
                    referencePanel(title: "Split PNG + anchors",
                                   imageName: panel == .front ? "MuscleMapFront" : "MuscleMapBack",
                                   panel: panel)
                }
            }
            .padding()
        }
    }

    private func referencePanel(title: String, imageName: String,
                                panel: MuscleMapPanel?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            GeometryReader { proxy in
                ZStack {
                    Image(imageName).resizable().scaledToFit()
                    if let panel {
                        ForEach(Array(MuscleMapLayout.callouts(for: panel).enumerated()), id: \.element.id) { index, item in
                            Circle().fill(.red).frame(width: 18, height: 18)
                                .overlay(Text("\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                                .position(x: proxy.size.width * item.anchorX,
                                          y: proxy.size.height * item.anchorY)
                        }
                    }
                }
                .overlay(Rectangle().stroke(.orange, lineWidth: 1))
            }
            .aspectRatio(panel == nil ? 1.148 : 0.575, contentMode: .fit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
