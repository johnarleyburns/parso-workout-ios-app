import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeekRingsCard: View {
    let dashboard: HomeDashboardState
    let summary: String

    private var rings: [WeekRing] {
        WeekRingsPresenter.rings(
            workingSets: dashboard.volume.reduce(0) { $0 + $1.sets },
            setTarget: dashboard.volume.filter(\.isTracked).reduce(0) { total, _ in total + 12 },
            cardioMinutes: dashboard.cardioDetail.moderateEquivalentMinutes,
            cardioTarget: dashboard.cardioDetail.targetMinutes)
    }

    private var cardioTint: Color {
        switch WeeklyCardioProgress.tintRole(for: dashboard.cardioDetail.moderateEquivalentMinutes) {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                open()
            } label: {
                HStack {
                    Text("This Week").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open This Week")
            HStack(spacing: 6) {
                ringButton(rings[0], tint: CadenceTheme.accent)
                ringButton(rings[1], tint: cardioTint)
            }
            .frame(maxWidth: .infinity)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("home.weekSummary")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard()
        .accessibilityIdentifier("home.weekRings")
    }

    /// Every tap on the card opens the top of This Week.
    private func ringButton(_ value: WeekRing, tint: Color) -> some View {
        Button {
            open()
        } label: {
            ring(value, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.weekRing.\(value.kind == .sets ? "sets" : "cardio")")
    }

    private func open() {
        Haptics.selection()
        NotificationCenter.default.post(name: .cadenceShowThisWeek, object: nil)
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
        }
    }
}
