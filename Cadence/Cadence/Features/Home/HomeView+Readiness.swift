import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeView {
    var readinessCard: some View {
        Button {
            Haptics.selection()
            readinessPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todayReadiness == nil ? "heart.text.square" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(todayReadiness == nil ? .orange : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(todayReadiness == nil ? "How are you feeling?" : "Today's readiness")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let todayReadiness {
                        Text(ReadinessCheckInPresenter.summary(for: todayReadiness))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(ReadinessCheckInPresenter.detail(for: todayReadiness))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Optional context for the coach")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassBackground(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: .orange,
                interactive: true,
                fallback: AnyShapeStyle(.orange.opacity(0.13)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todayReadiness == nil
            ? "Add today's optional readiness check-in"
            : "Today's readiness: \(ReadinessCheckInPresenter.summary(for: todayReadiness!))")
        .accessibilityIdentifier("home.readiness")
    }
}
