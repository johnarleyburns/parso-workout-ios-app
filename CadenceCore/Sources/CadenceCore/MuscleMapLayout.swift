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

/// The map uses exact left/right viewBox halves derived from the original
/// combined front/back SVG. Each anchor is normalized within its selected half,
/// and its side determines which outside label column owns the connector.
public enum MuscleMapLayout {
    public static let sourceWidth = 406.99026
    public static let sourceHeight = 354.43411
    public static let halfWidth = sourceWidth / 2
    public static let sourceRatio = sourceWidth / sourceHeight
    public static let halfRatio = halfWidth / sourceHeight

    public static let callouts: [MuscleMapCallout] = [
        // Front-visible groups.
        .init(group: .neck, panel: .front, anchorX: 0.46, anchorY: 0.17, side: .left),
        .init(group: .shoulders, panel: .front, anchorX: 0.32, anchorY: 0.23, side: .left),
        .init(group: .biceps, panel: .front, anchorX: 0.29, anchorY: 0.34, side: .left),
        .init(group: .hipFlexors, panel: .front, anchorX: 0.42, anchorY: 0.50, side: .left),
        .init(group: .abductors, panel: .front, anchorX: 0.34, anchorY: 0.58, side: .left),
        .init(group: .quadriceps, panel: .front, anchorX: 0.41, anchorY: 0.65, side: .left),
        .init(group: .tibialis, panel: .front, anchorX: 0.43, anchorY: 0.80, side: .left),
        .init(group: .chest, panel: .front, anchorX: 0.58, anchorY: 0.29, side: .right),
        .init(group: .abdominals, panel: .front, anchorX: 0.58, anchorY: 0.39, side: .right),
        .init(group: .forearms, panel: .front, anchorX: 0.72, anchorY: 0.46, side: .right),
        .init(group: .adductors, panel: .front, anchorX: 0.58, anchorY: 0.57, side: .right),
        .init(group: .calves, panel: .front, anchorX: 0.60, anchorY: 0.80, side: .right),

        // Back-visible groups.
        .init(group: .neck, panel: .back, anchorX: 0.46, anchorY: 0.17, side: .left),
        .init(group: .shoulders, panel: .back, anchorX: 0.34, anchorY: 0.24, side: .left),
        .init(group: .triceps, panel: .back, anchorX: 0.30, anchorY: 0.35, side: .left),
        .init(group: .lats, panel: .back, anchorX: 0.40, anchorY: 0.37, side: .left),
        .init(group: .abductors, panel: .back, anchorX: 0.35, anchorY: 0.52, side: .left),
        .init(group: .hamstrings, panel: .back, anchorX: 0.42, anchorY: 0.65, side: .left),
        .init(group: .traps, panel: .back, anchorX: 0.56, anchorY: 0.24, side: .right),
        .init(group: .rotatorCuff, panel: .back, anchorX: 0.66, anchorY: 0.29, side: .right),
        .init(group: .middleBack, panel: .back, anchorX: 0.56, anchorY: 0.34, side: .right),
        .init(group: .forearms, panel: .back, anchorX: 0.70, anchorY: 0.45, side: .right),
        .init(group: .lowerBack, panel: .back, anchorX: 0.56, anchorY: 0.46, side: .right),
        .init(group: .glutes, panel: .back, anchorX: 0.56, anchorY: 0.51, side: .right),
        .init(group: .calves, panel: .back, anchorX: 0.60, anchorY: 0.81, side: .right)
    ]

    public static func callouts(for panel: MuscleMapPanel) -> [MuscleMapCallout] {
        callouts.filter { $0.panel == panel }
    }
}
