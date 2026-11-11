import SwiftUI
import CadenceCore
import CadenceFeatures

/// Split out of HomeView+Dashboard.swift (2026-11) to stay under the
/// test-pyramid's 400-LOC cap once issue #619's weekly-credit wiring landed
/// alongside unrelated concurrent work in that file. No behavior change -
/// these are the same computed properties on the same `HomeView` extension,
/// just in a sibling file.
extension HomeView {
    /// Register destinations inside the NavigationStack that owns the screen.
    /// A destination modifier applied outside ThisWeekView's stack produces the
    /// system's blank warning destination for workout history routes.
    @ViewBuilder
    var dashboardNavigationRoot: some View {
        if usesExternalNavigation {
            homeNavigationDestinations(dashboardScrollContent)
        } else {
            NavigationStack(path: pathBinding) {
                homeNavigationDestinations(dashboardScrollContent)
            }
        }
    }

    var dashboardScrollContent: some View {
        TodayHeroViewport {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("week.top")
                        if surface == .today {
                            dashboardTopContent
                        } else {
                            thisWeekContent
                        }
                    }
                    .padding()
                }
                .background { CadenceGlassBackdrop(tint: .green) }
                .navigationTitle(surface.title)
                .navigationBarTitleDisplayMode(.large)
                .onReceive(NotificationCenter.default.publisher(for: .cadenceShowThisWeek)) { _ in
                    guard surface != .today else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("week.top", anchor: .top) }
                }
                .onChange(of: weekScrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    weekScrollTarget = nil
                }
                .toolbar {
                    // Settings is no longer a bottom tab; Today owns the single
                    // entry point, shown only on the Today surface.
                    if surface == .today {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Haptics.selection()
                                path.append(HomeRoute.settings)
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityIdentifier("home.settings")
                            .accessibilityLabel("Settings")
                        }
                    }
                }
            }
        }
    }
}
