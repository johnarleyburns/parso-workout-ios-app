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
        Group {
            if usesExternalNavigation {
                homeNavigationDestinations(dashboardScrollContent)
            } else {
                NavigationStack(path: pathBinding) {
                    homeNavigationDestinations(dashboardScrollContent)
                }
            }
        }
        // Warm-up is owned by RootTabView above the tab bar so the workout
        // cover can replace it without exposing Home for a frame.
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
        .background { CadenceGlassBackdrop(tint: .green) }
        .navigationTitle(surface.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if surface == .today {
                // The Supporter badge is a status mark at the leading edge; one
                // overflow menu owns navigation on the trailing edge.
                ToolbarItem(placement: .topBarLeading) {
                    if let badge = HomeHeaderPresentation(isSupporter: contributions.store.isSupporter).supporterBadge {
                        HStack(spacing: 4) {
                            Image(systemName: badge.systemImage)
                            Text(badge.text)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CadenceTheme.achievement)
                        .padding(.horizontal, badge.horizontalPadding)
                        .padding(.vertical, badge.verticalPadding)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(badge.accessibilityLabel)
                        .accessibilityIdentifier(badge.accessibilityIdentifier)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            path.append(HomeRoute.history)
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .accessibilityIdentifier(HomeMenuDestination.history.accessibilityIdentifier)
                        Button {
                            weekSurface?.open(.strength)
                        } label: {
                            Label("Strength this week", systemImage: "dumbbell.fill")
                        }
                        .accessibilityIdentifier(HomeMenuDestination.strengthWeek.accessibilityIdentifier)
                        Button {
                            weekSurface?.open(.cardio)
                        } label: {
                            Label("Cardio this week", systemImage: "heart.fill")
                        }
                        .accessibilityIdentifier(HomeMenuDestination.cardioWeek.accessibilityIdentifier)
                        Button {
                            Haptics.selection()
                            path.append(HomeRoute.settings)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier(HomeMenuDestination.settings.accessibilityIdentifier)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("home.menu")
                    .accessibilityLabel("Home options")
                }
            }
        }
    }

    /// Today is fully scrollable. The start list is inline rather than a
    /// floating popup, and each row starts its workout directly.
    private var todayDashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardTopContent
                if resumeSession == nil {
                    workoutStartControls
                }
            }
            .id("week.top")
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom)
            .frame(maxWidth: .infinity, alignment: .top)
        }
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
