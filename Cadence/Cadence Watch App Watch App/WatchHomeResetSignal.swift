import SwiftUI

/// Lets any view pushed from Home (at any navigation depth) ask to return all
/// the way to Home, instead of popping only one level with `@Environment(\.dismiss)`
/// -- whose destination otherwise depends on how deep the stack was when the
/// workout started (direct from Home vs. via a setup/preview screen vs. via a
/// previous-workout detail screen).
private struct WatchReturnToHomeKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

/// Broadcasts every `watchReturnToHome()` call so views that own their own
/// local navigation-gating state deep in the tree (state `WatchRootView`
/// itself has no reference to) can reset that state too.
private struct WatchHomeResetTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var watchReturnToHome: () -> Void {
        get { self[WatchReturnToHomeKey.self] }
        set { self[WatchReturnToHomeKey.self] = newValue }
    }
    var watchHomeResetToken: Int {
        get { self[WatchHomeResetTokenKey.self] }
        set { self[WatchHomeResetTokenKey.self] = newValue }
    }
}
