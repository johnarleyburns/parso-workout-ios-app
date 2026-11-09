import SwiftUI

/// The weekly strength review is a first-class root surface.
struct StrengthView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(surface: .strength, navigationPath: $path)
        }
    }
}

/// Cardio has its own weekly surface so strength coverage and aerobic credit
/// never compete for vertical space or navigation priority.
struct CardioWeekView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(surface: .cardio, navigationPath: $path)
        }
    }
}
