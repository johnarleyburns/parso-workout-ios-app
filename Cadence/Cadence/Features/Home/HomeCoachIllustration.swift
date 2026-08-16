import SwiftUI

/// The coach artwork is selected once when Home's view identity is created.
/// Keeping the catalog separate from the view makes the selection rule explicit
/// and prevents redraws from changing the artwork.
enum HomeCoachIllustration: String, CaseIterable, Identifiable {
    case liftingDumbbells
    case usingStopwatch
    case usingWhistle
    case yelling

    var id: String { rawValue }

    var imageName: String {
        switch self {
        case .liftingDumbbells: "CoachLiftingDumbbells"
        case .usingStopwatch: "CoachUsingStopwatch"
        case .usingWhistle: "CoachUsingWhistle"
        case .yelling: "CoachYelling"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .liftingDumbbells: "Coach lifting dumbbells"
        case .usingStopwatch: "Coach checking a stopwatch"
        case .usingWhistle: "Coach blowing a whistle"
        case .yelling: "Coach calling encouragement through a megaphone"
        }
    }

    static func random() -> Self {
        allCases.randomElement() ?? .liftingDumbbells
    }
}

struct HomeCoachIllustrationView: View {
    let illustration: HomeCoachIllustration

    var body: some View {
        Image(illustration.imageName)
            .resizable()
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(illustration.accessibilityLabel)
            .accessibilityIdentifier("home.coachIllustration")
    }
}
