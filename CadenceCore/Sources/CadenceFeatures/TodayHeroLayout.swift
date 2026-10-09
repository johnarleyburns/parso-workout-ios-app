import Foundation

public enum TodayHeroLayout {
    /// Content/loading never changes the allocation. Compact screens retain
    /// tappable controls; larger windows cap the preview instead of stretching it.
    public static func height(viewportHeight: Double) -> Double {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return 360 }
        return min(440, max(320, viewportHeight * 0.5))
    }
}
