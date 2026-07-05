import SwiftUI
import CadenceCore

/// The ambient coach surface (coach-surface-design.md §3): a compact, directory-style
/// row — not a promo card — placed below the user's own data on Home. When a live
/// coach observation is available it expands to two lines showing that insight
/// (the amendment: insights are always shown; only the upsell CTA is paced).
struct CoachRow: View {
    /// The continuously-updated observation, if any.
    let topInsight: Insight?
    var onTap: () -> Void
    var onHide: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    if let topInsight {
                        Text("Coach noticed")
                            .font(.subheadline.weight(.semibold))
                        Text(topInsight.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Coach")
                            .font(.subheadline.weight(.semibold))
                        Text("Builds and adjusts your program")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cadenceGlassBackground(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true,
                fallback: AnyShapeStyle(.background.secondary))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onTap() } label: { Label("Learn more", systemImage: "info.circle") }
            Button(role: .destructive) { onHide() } label: {
                Label("Hide Coach offers", systemImage: "eye.slash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(topInsight == nil ? "coach.row" : "coach.row.insight")
        .accessibilityLabel(topInsight == nil
            ? "Coach — builds and adjusts your program"
            : "Coach noticed: \(topInsight?.title ?? "")")
        .accessibilityHint("Opens the Coach preview")
    }
}
