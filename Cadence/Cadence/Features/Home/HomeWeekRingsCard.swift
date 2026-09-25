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
        Button {
            Haptics.selection()
            NotificationCenter.default.post(name: .cadenceShowThisWeek, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This week").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ring(rings[0], tint: CadenceTheme.accent)
                    ring(rings[1], tint: CadenceTheme.link)
                    ring(rings[2], tint: CadenceTheme.attention)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cadenceCard()
        .accessibilityIdentifier("home.weekRings")
        .accessibilityLabel("This week. Open weekly muscle coverage")
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
        case .sets: return "Sets"
        case .cardioMinutes: return "Cardio minutes"
        case .sessions: return "Sessions"
        }
    }
}
