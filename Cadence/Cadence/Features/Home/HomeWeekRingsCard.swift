import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeekRingsCard: View {
    let dashboard: HomeDashboardState

    private var setValue: Double { dashboard.volume.reduce(0) { $0 + $1.sets } }
    private var setTarget: Double { dashboard.volume.filter(\.isTracked).reduce(0) { $0 + ($1.isTracked ? 12 : 0) } }

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
                    ring(value: setValue, target: setTarget, label: "Sets", tint: CadenceTheme.accent)
                    ring(value: dashboard.cardioDetail.moderateEquivalentMinutes,
                         target: dashboard.cardioDetail.targetMinutes,
                         label: "Cardio min", tint: CadenceTheme.link)
                    ring(value: dashboard.strength.completed, target: dashboard.strength.target,
                         label: "Sessions", tint: CadenceTheme.attention)
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

    private func ring(value: Double, target: Double, label: String, tint: Color) -> some View {
        CadenceProgressRing(value: value, total: target, tint: tint, label: label)
            .frame(maxWidth: .infinity)
    }
}
