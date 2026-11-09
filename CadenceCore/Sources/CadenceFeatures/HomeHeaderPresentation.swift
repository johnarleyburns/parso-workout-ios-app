import Foundation

/// Pure presentation model for the Home header. Status-only: the Supporter
/// badge is a thank-you mark that is never tappable and gates nothing.
public struct HomeHeaderPresentation: Equatable, Sendable {
    public enum Tint: Equatable, Sendable { case achievement }

    public struct SupporterBadge: Equatable, Sendable {
        public let text: String
        public let accessibilityLabel: String
        public let systemImage: String
        public let tint: Tint
        public let accessibilityIdentifier: String
    }

    public let supporterBadge: SupporterBadge?

    public init(isSupporter: Bool) {
        supporterBadge = isSupporter
            ? SupporterBadge(text: "Supporter", accessibilityLabel: "Supporter",
                             systemImage: "heart.fill", tint: .achievement,
                             accessibilityIdentifier: "home.supporterBadge")
            : nil
    }
}
