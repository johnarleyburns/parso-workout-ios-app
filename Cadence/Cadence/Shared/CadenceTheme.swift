import SwiftUI
import CadenceFeatures

/// The small semantic palette shared by the iPhone surfaces. Keeping roles
/// here makes it difficult for a screen to invent a one-off card or action
/// color and gives light/dark mode the same hierarchy.
enum CadenceTheme {
    /// AccentColor contains light, dark, and high-contrast variants. Using the
    /// named color keeps system controls and custom surfaces in sync.
    static let accent = Color("AccentColor")
    /// Source-compatible alias while the remaining screens migrate.
    static let link = accent
    static let attention = Color.orange
    static let positive = Color.green
    static let achievement = Color(red: 0.95, green: 0.66, blue: 0.23)
    /// Muscle-coverage heat colours: red (0%), yellow (below the 4-set
    /// minimum), light green (building toward productive), green (productive).
    static let muscleZero = Color.red
    static let muscleBelow = Color.yellow
    static let muscleBuilding = Color.mint
    static let muscleProductive = Color.green
    static let cardBackground = Color(.secondarySystemBackground)
    static let heroFill = accent.opacity(0.12)
    static let heroStroke = accent.opacity(0.25)

    /// The shared weekly red/yellow/green scale (`WeeklySetTintRole`). System
    /// colors keep their dark-mode and Increase Contrast variants.
    static func weeklyTint(_ role: WeeklySetTintRole) -> Color {
        switch role {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        }
    }
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
