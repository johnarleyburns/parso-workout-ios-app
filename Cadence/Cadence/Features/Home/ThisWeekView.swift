import SwiftUI

/// Weekly review is a first-class root surface. It reuses the same value-only
/// projections and background refresh boundary as Today, while keeping the
/// dense map/history content out of the daily launch flow.
struct ThisWeekView: View {
    var body: some View {
        HomeView(surface: .thisWeek)
    }
}
