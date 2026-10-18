import SwiftUI
import CadenceFeatures

private struct TodayHeroHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 360
}

extension EnvironmentValues {
    var todayHeroHeight: CGFloat {
        get { self[TodayHeroHeightKey.self] }
        set { self[TodayHeroHeightKey.self] = newValue }
    }
}

struct TodayHeroViewport<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            // The large nav title collapsing while scrolling shrinks the top safe
            // area and grows proxy.size by the same amount; add the insets back
            // so the hero height stays constant during scroll.
            let stableHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            content().environment(\.todayHeroHeight,
                                  CGFloat(TodayHeroLayout.height(viewportHeight: Double(stableHeight))))
        }
    }
}
