import SwiftUI
import CadenceFeatures

/// A regular-width dashboard gets a useful two-column canvas on iPad. At AX5
/// the cards return to one column so localized, enlarged text never has to
/// compete with a neighboring card.
struct AdaptiveDashboardColumns<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let layout = AdaptiveSurfaceLayout.resolve(
            isRegularWidth: horizontalSizeClass == .regular,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                content()
            }
        case .twoColumn:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: CGFloat(LayoutMetrics.cardRowSpacing)),
                                GridItem(.flexible(), spacing: CGFloat(LayoutMetrics.cardRowSpacing))],
                      alignment: .leading,
                      spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                content()
            }
        }
    }
}
