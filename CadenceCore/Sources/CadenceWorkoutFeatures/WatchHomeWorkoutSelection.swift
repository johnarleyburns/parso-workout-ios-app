import CadenceFeatures
import Foundation

/// Watch-only launcher state. Selection and mode changes never create a route;
/// only the Start action snapshots a destination for navigation.
public struct WatchHomeWorkoutSelection: Equatable, Sendable {
    public enum Mode: Sendable { case strength, cardio }
    public static let strengthStorageKey = "watch.home.strengthChoice"
    public static let cardioStorageKey = "watch.home.cardioChoice"

    public private(set) var mode: Mode = .strength
    public private(set) var strengthChoice: HomeWorkoutStartChoice
    public private(set) var cardioChoice: HomeWorkoutStartChoice
    public private(set) var launchChoice: HomeWorkoutStartChoice?

    public init(savedStrengthID: String? = nil, savedCardioID: String? = nil,
                legacyChoiceID: String? = nil) {
        strengthChoice = HomeWorkoutStartChoice.strengthChoices.first {
            $0.id == (savedStrengthID ?? legacyChoiceID)
        } ?? .strength(.suggested)
        cardioChoice = HomeWorkoutStartChoice.cardioChoices.first {
            $0 != .suggestedCardio && $0.id == (savedCardioID ?? legacyChoiceID)
        } ?? .cardio(.hiit)
    }

    public static func persisted(defaults: UserDefaults = .standard) -> Self {
        Self(savedStrengthID: defaults.string(forKey: strengthStorageKey),
             savedCardioID: defaults.string(forKey: cardioStorageKey),
             legacyChoiceID: defaults.string(forKey: HomeWorkoutStartChoice.selectionStorageKey))
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(strengthChoice.id, forKey: Self.strengthStorageKey)
        defaults.set(cardioChoice.id, forKey: Self.cardioStorageKey)
    }

    /// "Personalized Cardio" (`.suggestedCardio`) is phone-only for now — the
    /// Watch has no suggestion-preview destination for it yet, so it's
    /// excluded here rather than shown as a dead/blank wheel entry.
    public var choices: [HomeWorkoutStartChoice] {
        if mode == .strength { return HomeWorkoutStartChoice.strengthChoices }
        return HomeWorkoutStartChoice.cardioChoices.filter { $0 != .suggestedCardio }
    }

    public var selection: HomeWorkoutStartChoice {
        mode == .strength ? strengthChoice : cardioChoice
    }

    public func title(for choice: HomeWorkoutStartChoice) -> String {
        switch choice {
        case .strength(.suggested): "Personalized"
        case .strength(.previous): "Previous"
        default: choice.title
        }
    }

    public mutating func show(_ mode: Mode) { self.mode = mode }

    public mutating func select(_ choice: HomeWorkoutStartChoice) {
        guard choices.contains(choice) else { return }
        if mode == .strength { strengthChoice = choice } else { cardioChoice = choice }
    }

    public mutating func start() { launchChoice = selection }
    public mutating func dismissStart() { launchChoice = nil }

    /// Picks `choice` and launches it in one step -- tapping a row in the
    /// instantly-displayed list is itself the start action, collapsing the
    /// old two-step "scroll the wheel, then tap Start" interaction.
    public mutating func selectAndStart(_ choice: HomeWorkoutStartChoice) {
        select(choice)
        start()
    }
}
