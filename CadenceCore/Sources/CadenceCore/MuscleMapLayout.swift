import Foundation

/// The stable, source-image coordinate map used by the weekly anatomy view.
/// Coordinates are normalized inside one half of the bundled front/back SVG;
/// the UI is therefore free to resize the image without losing its callouts.
public enum MuscleMapPanel: String, CaseIterable, Codable, Sendable {
    case front
    case back
}

public struct MuscleMapCallout: Equatable, Hashable, Sendable, Identifiable {
    public let group: MuscleGroup
    public let panel: MuscleMapPanel
    public let anchorX: Double
    public let anchorY: Double

    public var id: String { "\(panel.rawValue)-\(group.rawValue)" }

    public init(group: MuscleGroup, panel: MuscleMapPanel, anchorX: Double, anchorY: Double) {
        self.group = group
        self.panel = panel
        self.anchorX = anchorX
        self.anchorY = anchorY
    }
}

/// The map intentionally uses a small, legible set of regions rather than
/// pretending that a portrait-sized illustration can label all 20 ontology
/// rows at once. Every displayed region still resolves to the canonical
/// MuscleGroup and opens the complete direct/indirect history sheet.
public enum MuscleMapLayout {
    public static let sourceRatio = 406.99026 / 354.43411
    public static let halfRatio = 203.49526 / 354.43411

    public static let callouts: [MuscleMapCallout] = [
        .init(group: .shoulders, panel: .front, anchorX: 0.24, anchorY: 0.25),
        .init(group: .chest, panel: .front, anchorX: 0.50, anchorY: 0.32),
        .init(group: .biceps, panel: .front, anchorX: 0.18, anchorY: 0.42),
        .init(group: .abdominals, panel: .front, anchorX: 0.50, anchorY: 0.47),
        .init(group: .quadriceps, panel: .front, anchorX: 0.50, anchorY: 0.63),
        .init(group: .calves, panel: .front, anchorX: 0.50, anchorY: 0.88),
        .init(group: .traps, panel: .back, anchorX: 0.50, anchorY: 0.24),
        .init(group: .lats, panel: .back, anchorX: 0.50, anchorY: 0.34),
        .init(group: .triceps, panel: .back, anchorX: 0.82, anchorY: 0.43),
        .init(group: .glutes, panel: .back, anchorX: 0.50, anchorY: 0.54),
        .init(group: .hamstrings, panel: .back, anchorX: 0.50, anchorY: 0.70),
        .init(group: .calves, panel: .back, anchorX: 0.50, anchorY: 0.88)
    ]

    public static func callouts(for panel: MuscleMapPanel) -> [MuscleMapCallout] {
        callouts.filter { $0.panel == panel }
    }
}
