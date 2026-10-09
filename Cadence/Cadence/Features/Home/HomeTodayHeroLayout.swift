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
            content().environment(\.todayHeroHeight,
                                  CGFloat(TodayHeroLayout.height(viewportHeight: Double(proxy.size.height))))
        }
    }
}
