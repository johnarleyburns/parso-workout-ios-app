import SwiftUI

enum CadenceTabBarClearance {
    /// The root dock's safe-area inset reserves its measured height; this is
    /// the additional breathing room that lets the final row clear the glass.
    static let extraBottom: CGFloat = 16

    /// Content padding applied inside long root-tab ScrollViews. A root
    /// `safeAreaInset` reserves the dock's frame, but nested NavigationStacks
    /// can otherwise leave the final card directly under the glass hit area.
    static let scrollContentBottom: CGFloat = 32
}

/// Adds a small scroll-end breathing room after the root dock has reserved its
/// actual safe-area inset. Applying this at the root tab content lets nested
/// NavigationStacks and their ScrollViews inherit the clearance without adding
/// a second fake dock to modal sheets.
extension View {
    func cadenceTabBarClearance(extra: CGFloat = CadenceTabBarClearance.extraBottom) -> some View {
        safeAreaPadding(.bottom, extra)
    }
}
