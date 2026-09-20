import Foundation

/// The stable, source-image coordinate map used by the weekly anatomy view.
/// Coordinates are normalized inside one half of the bundled front/back SVG;
/// the UI is therefore free to resize the image without losing its callouts.
public enum MuscleMapPanel: String, CaseIterable, Codable, Sendable {
    case front
    case back
}

public enum MuscleMapCalloutSide: String, Codable, Hashable, Sendable {
    case left
    case right
}

public struct MuscleMapCallout: Equatable, Hashable, Sendable, Identifiable {
    public let group: MuscleGroup
    public let panel: MuscleMapPanel
    public let anchorX: Double
    public let anchorY: Double
    public let side: MuscleMapCalloutSide

    public var id: String { "\(panel.rawValue)-\(group.rawValue)" }

    public init(group: MuscleGroup,
                panel: MuscleMapPanel,
                anchorX: Double,
                anchorY: Double,
                side: MuscleMapCalloutSide) {
        self.group = group
        self.panel = panel
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.side = side
    }
}

/// The map uses the original combined front/back SVG. The UI clips its exact
/// left or right geometric half, so the illustration remains undistorted while
/// every visible region has a corresponding label column on either side.
public enum MuscleMapLayout {
    public static let sourceWidth = 406.99026
    public static let sourceHeight = 354.43411
    public static let halfWidth = sourceWidth / 2
    public static let sourceRatio = sourceWidth / sourceHeight
    public static let halfRatio = halfWidth / sourceHeight

    public static let callouts: [MuscleMapCallout] = [
        // Front-visible groups.
        .init(group: .neck, panel: .front, anchorX: 0.50, anchorY: 0.18, side: .left),
        .init(group: .shoulders, panel: .front, anchorX: 0.25, anchorY: 0.26, side: .left),
        .init(group: .chest, panel: .front, anchorX: 0.50, anchorY: 0.32, side: .right),
        .init(group: .biceps, panel: .front, anchorX: 0.20, anchorY: 0.40, side: .left),
        .init(group: .forearms, panel: .front, anchorX: 0.18, anchorY: 0.51, side: .right),
        .init(group: .abdominals, panel: .front, anchorX: 0.50, anchorY: 0.47, side: .right),
        .init(group: .hipFlexors, panel: .front, anchorX: 0.38, anchorY: 0.57, side: .left),
        .init(group: .abductors, panel: .front, anchorX: 0.22, anchorY: 0.62, side: .left),
        .init(group: .adductors, panel: .front, anchorX: 0.70, anchorY: 0.62, side: .right),
        .init(group: .quadriceps, panel: .front, anchorX: 0.42, anchorY: 0.68, side: .left),
        .init(group: .tibialis, panel: .front, anchorX: 0.36, anchorY: 0.84, side: .left),
        .init(group: .calves, panel: .front, anchorX: 0.68, anchorY: 0.85, side: .right),

        // Back-visible groups.
        .init(group: .neck, panel: .back, anchorX: 0.50, anchorY: 0.18, side: .left),
        .init(group: .traps, panel: .back, anchorX: 0.50, anchorY: 0.25, side: .right),
        .init(group: .shoulders, panel: .back, anchorX: 0.25, anchorY: 0.29, side: .left),
        .init(group: .rotatorCuff, panel: .back, anchorX: 0.75, anchorY: 0.33, side: .right),
        .init(group: .triceps, panel: .back, anchorX: 0.20, anchorY: 0.41, side: .left),
        .init(group: .forearms, panel: .back, anchorX: 0.82, anchorY: 0.51, side: .right),
        .init(group: .middleBack, panel: .back, anchorX: 0.50, anchorY: 0.36, side: .right),
        .init(group: .lats, panel: .back, anchorX: 0.50, anchorY: 0.43, side: .left),
        .init(group: .lowerBack, panel: .back, anchorX: 0.50, anchorY: 0.54, side: .right),
        .init(group: .abductors, panel: .back, anchorX: 0.27, anchorY: 0.60, side: .left),
        .init(group: .glutes, panel: .back, anchorX: 0.50, anchorY: 0.58, side: .right),
        .init(group: .hamstrings, panel: .back, anchorX: 0.34, anchorY: 0.71, side: .left),
        .init(group: .calves, panel: .back, anchorX: 0.68, anchorY: 0.87, side: .right)
    ]

    public static func callouts(for panel: MuscleMapPanel) -> [MuscleMapCallout] {
        callouts.filter { $0.panel == panel }
    }
}
