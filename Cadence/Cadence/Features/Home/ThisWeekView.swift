import SwiftUI

/// Weekly review is a first-class root surface. It reuses the same value-only
/// projections and background refresh boundary as Today, while keeping the
/// dense map/history content out of the daily launch flow.
struct ThisWeekView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(surface: .thisWeek, navigationPath: $path)
        }
    }
}
