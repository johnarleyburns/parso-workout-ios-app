import SwiftUI
import CadenceCore

struct TrendBadge: View {
    let trend: AssessmentTrend
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.symbol).font(.caption2)
            Text(trend.label).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(trend.tint)
        .background(trend.tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trend: \(trend.label)")
    }
}
