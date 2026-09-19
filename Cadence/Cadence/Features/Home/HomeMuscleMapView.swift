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
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscle map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(spacing: 16) {
                panelOption(.front)
                panelOption(.back)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Muscle map view")
            MuscleMapSideView(
                panel: selectedPanel,
                title: selectedPanel == .front ? "FRONT" : "BACK",
                callouts: MuscleMapLayout.callouts(for: selectedPanel),
                setsLabel: setsLabel(for:),
                statusColor: statusColor(for:),
                onSelect: onSelect)
            Button(action: onOpenCardio) {
                Label("Cardio · \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) min",
                      systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cardio, \(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) minutes this week")
            Text("Tap a highlighted muscle for this week's direct and indirect work")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func panelOption(_ panel: MuscleMapPanel) -> some View {
        let selected = selectedPanel == panel
        return Button {
            guard selectedPanel != panel else { return }
            Haptics.selection()
            selectedPanel = panel
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.subheadline)
                Text(panel == .front ? "Front" : "Back")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.week.muscleMap.\(panel.rawValue)")
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

    // The selected half is shown at a useful portrait size, with a label column
    // on each side. This is intentionally still compact enough for the narrowest
    // supported iPhone while leaving every callout tappable.
    private let labelWidth: CGFloat = 82
    private let imageWidth: CGFloat = 132
    private let rowHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 3

    private var imageHeight: CGFloat { imageWidth / CGFloat(MuscleMapLayout.halfRatio) }
    private var leftCallouts: [MuscleMapCallout] {
        callouts.enumerated().compactMap { index, callout in index.isMultiple(of: 2) ? callout : nil }
    }
    private var rightCallouts: [MuscleMapCallout] {
        callouts.enumerated().compactMap { index, callout in index.isMultiple(of: 2) ? nil : callout }
    }
    private var columnHeight: CGFloat {
        let rows = (callouts.count + 1) / 2
        return CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowSpacing
    }
    private var contentHeight: CGFloat {
        max(imageHeight, columnHeight)
    }
    private var canvasWidth: CGFloat { labelWidth * 2 + imageWidth + 8 }
    private var columnTop: CGFloat { (contentHeight - columnHeight) / 2 }

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: panel == .front ? .trailing : .leading)
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
        .accessibilityLabel("\(title.lowercased()) muscle map")
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
        .frame(width: labelWidth, height: columnHeight, alignment: .center)
    }

    private var image: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.04)
            Image("MusclesFrontBack")
                .resizable()
                // The asset contains front on the left and back on the right.
                // Cropping one exact half preserves the source aspect ratio.
                .frame(width: imageWidth * 2, height: imageHeight)
                .offset(x: panel == .front ? 0 : -imageWidth)
                .accessibilityHidden(true)
            ForEach(callouts) { callout in
                Button {
                    onSelect(callout.group)
                } label: {
                    Circle()
                        .fill(statusColor(callout.group).opacity(0.88))
                        .overlay { Circle().stroke(.white, lineWidth: 1.5) }
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .position(x: CGFloat(callout.anchorX) * imageWidth,
                          y: CGFloat(callout.anchorY) * imageHeight)
                .accessibilityLabel("\(callout.group.displayName), \(setsLabel(callout.group)) this week")
                .accessibilityHint("Shows direct and indirect exercise history")
                .accessibilityIdentifier("home.week.muscle.region.\(callout.panel.rawValue).\(callout.group.rawValue)")
            }
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
                              rowY: columnTop + CGFloat(index) * (rowHeight + rowSpacing) + rowHeight / 2,
                              imageOriginX: imageOriginX, imageOriginY: imageOriginY,
                              startX: labelWidth)
            }
            for (index, callout) in rightCallouts.enumerated() {
                drawConnector(context: &context, callout: callout,
                              rowY: columnTop + CGFloat(index) * (rowHeight + rowSpacing) + rowHeight / 2,
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
        context.fill(Path(ellipseIn: CGRect(x: anchorX - 2, y: anchorY - 2,
                                             width: 4, height: 4)),
                      with: .color(statusColor(callout.group)))
    }
}
