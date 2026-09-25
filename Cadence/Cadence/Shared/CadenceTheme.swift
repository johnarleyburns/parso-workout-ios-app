import SwiftUI
import CadenceFeatures

/// The small semantic palette shared by the iPhone surfaces. Keeping roles
/// here makes it difficult for a screen to invent a one-off card or action
/// color and gives light/dark mode the same hierarchy.
enum CadenceTheme {
    static let accent = Color.green
    static let link = Color.cyan
    static let attention = Color.orange
    static let achievement = Color.yellow
    static let cardBackground = Color(.secondarySystemBackground)
    static let heroFill = accent.opacity(0.12)
    static let heroStroke = accent.opacity(0.25)
}

enum CadenceCardRole {
    case standard
    case hero
}

extension View {
    /// Native, quiet grouping for the redesigned app. Standard cards have no
    /// border or shadow; the hero role is reserved for the next action.
    func cadenceCard(_ role: CadenceCardRole = .standard) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return self
            .padding(12)
            .background(role == .hero ? CadenceTheme.heroFill : CadenceTheme.cardBackground,
                        in: shape)
            .overlay {
                if role == .hero {
                    shape.stroke(CadenceTheme.heroStroke, lineWidth: 1)
                }
            }
    }
}

struct CadenceProgressRing: View {
    let value: Double
    let total: Double
    let tint: Color
    let label: String

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 7)
                Circle().trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.number(value))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityLabel("\(label), \(Format.number(value)) of \(Format.number(total))")
            Text("\(Format.number(value)) / \(Format.number(total))")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private extension Format {
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
