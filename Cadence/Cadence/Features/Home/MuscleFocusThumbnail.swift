import SwiftUI
import CadenceCore

/// Count badge that floats over the Observations card's top-right corner.
struct MuscleFocusThumbnail: View {
    /// 64 rather than 88 so the artwork floats over the card's top-right corner
    /// without colliding with the heading at large Dynamic Type.
    static let size: CGFloat = 64

    let count: Int

    var body: some View {
        ZStack {
            Circle().fill(CadenceTheme.accent.opacity(0.14))
            Text("\(count)")
                .font(.title.weight(.semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(8)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) observations")
        .accessibilityIdentifier("home.observationsCount")
    }
}
