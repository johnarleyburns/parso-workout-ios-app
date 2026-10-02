import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeekRingsCard: View {
    let dashboard: HomeDashboardState

    private var rings: [WeekRing] {
        WeekRingsPresenter.rings(
            workingSets: dashboard.volume.reduce(0) { $0 + $1.sets },
            setTarget: dashboard.volume.filter(\.isTracked).reduce(0) { total, _ in total + 12 },
            cardioMinutes: dashboard.cardioDetail.moderateEquivalentMinutes,
            cardioTarget: dashboard.cardioDetail.targetMinutes,
            sessions: dashboard.strength.completed,
            sessionTarget: dashboard.strength.target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                open(.muscleCoverage)
            } label: {
                HStack {
                    Text("This week").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open This Week")
            HStack(spacing: 6) {
                ringButton(rings[0], tint: CadenceTheme.accent)
                ringButton(rings[1], tint: CadenceTheme.link)
                ringButton(rings[2], tint: CadenceTheme.attention)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard()
        .accessibilityIdentifier("home.weekRings")
    }

    /// Each ring deep-links to the This Week section it summarizes: sets to
    /// muscle coverage, cardio minutes to Cardio, sessions to Strength.
    private func ringButton(_ value: WeekRing, tint: Color) -> some View {
        let destination = ThisWeekDestination.forRing(value.kind)
        return Button {
            open(destination)
        } label: {
            ring(value, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.weekRing.\(destination.rawValue)")
    }

    private func open(_ destination: ThisWeekDestination) {
        Haptics.selection()
        CadencePlatformRequestStore.requestThisWeekSection(destination)
        NotificationCenter.default.post(name: .cadenceShowThisWeek, object: destination.rawValue)
    }

    private func ring(_ value: WeekRing, tint: Color) -> some View {
        CadenceProgressRing(value: value.value, total: value.target, tint: tint,
                            label: value.kind.accessibilityName)
            .frame(maxWidth: .infinity)
    }
}

private extension WeekRing.Kind {
    var accessibilityName: String {
        switch self {
        case .sets: return String(localized: "Sets")
        case .cardioMinutes: return String(localized: "Cardio minutes")
        case .sessions: return String(localized: "Sessions")
        }
    }
}
