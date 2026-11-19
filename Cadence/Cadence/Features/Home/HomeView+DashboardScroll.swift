import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

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

    @ViewBuilder
    var dashboardScrollContent: some View {
        Group {
            if surface == .today {
                todayDashboardContent
            } else {
                weeklyDashboardScroll
            }
        }
        .safeAreaInset(edge: .bottom) {
            if surface == .today, resumeSession == nil {
                workoutStartControls
                    .padding(.horizontal)
                    .padding(.vertical, 16)
            }
        }
        .background { CadenceGlassBackdrop(tint: .green) }
        .navigationTitle(surface.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Settings is no longer a bottom tab; Today owns the single
            // entry point, shown only on the Today surface.
            if surface == .today {
                ToolbarItem(placement: .topBarLeading) {
                    Button { path.append(HomeRoute.history) } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Workout history")
                    .accessibilityIdentifier("home.history")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let badge = HomeHeaderPresentation(isSupporter: contributions.store.isSupporter).supporterBadge {
                        HStack(spacing: 4) {
                            Image(systemName: badge.systemImage)
                            Text(badge.text)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CadenceTheme.achievement)
                        .padding(.horizontal, badge.horizontalPadding)
                        .padding(.vertical, badge.verticalPadding)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(badge.accessibilityLabel)
                        .accessibilityIdentifier(badge.accessibilityIdentifier)
                    }
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

    /// Today is one flexible card above the bottom start controls, so This Week
    /// fills the available height instead of leaving a scroll view's unused
    /// space below it. Strength/Cardio remain scrollable.
    private var todayDashboardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            dashboardTopContent
        }
        .id("week.top")
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var weeklyDashboardScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    thisWeekContent
                }
                .id("week.top")
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom)
            }
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
        }
    }
}
