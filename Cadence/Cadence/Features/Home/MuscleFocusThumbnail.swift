import SwiftUI
import CadenceCore

/// Muscle-map thumbnail that floats over the Observations card; it replaced the
/// stock coach cartoons.
struct MuscleFocusThumbnail: View {
    /// 64 rather than 88 so the artwork floats over the card's top-right corner
    /// without colliding with the heading at large Dynamic Type.
    static let size: CGFloat = 64

    let group: MuscleGroup

    var body: some View {
        ZStack {
            Circle().fill(CadenceTheme.accent.opacity(0.14))
            Image(MuscleMapLayout.maskAssetName(for: group,
                                                panel: MuscleMapLayout.primaryPanel(for: group)))
                .resizable()
                .scaledToFit()
                .padding(8)
                .accessibilityHidden(true)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityLabel("Muscle focus: \(group.displayName)")
        .accessibilityIdentifier("home.muscleFocusThumbnail")
    }
}
