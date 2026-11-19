import CadenceFeatures
import Foundation

/// Watch-only launcher state. The picker offers exactly the phone's workout
/// options, in the phone's order, with the phone's titles. Selection changes
/// never create a route; only the Start action snapshots a destination.
public struct WatchHomeWorkoutSelection: Equatable, Sendable {
    public static let storageKey = "watch.home.choice"
    /// Older Watch builds stored one choice per mode. Read those so an
    /// existing selection survives this single-picker migration.
    public static let legacyStrengthStorageKey = "watch.home.strengthChoice"
    public static let legacyCardioStorageKey = "watch.home.cardioChoice"

    public private(set) var choice: HomeWorkoutStartChoice
    public private(set) var launchChoice: HomeWorkoutStartChoice?

    public init(savedID: String? = nil, legacyStrengthID: String? = nil,
                legacyCardioID: String? = nil, legacyChoiceID: String? = nil) {
        let identifier = savedID ?? legacyStrengthID ?? legacyCardioID ?? legacyChoiceID
        choice = identifier.flatMap { id in
            HomeWorkoutStartChoice.allChoices.first { $0.id == id }
        } ?? HomeWorkoutStartChoice.defaultChoice
    }

    public static func persisted(defaults: UserDefaults = .standard) -> Self {
        Self(savedID: defaults.string(forKey: storageKey),
             legacyStrengthID: defaults.string(forKey: legacyStrengthStorageKey),
             legacyCardioID: defaults.string(forKey: legacyCardioStorageKey),
             legacyChoiceID: defaults.string(forKey: HomeWorkoutStartChoice.selectionStorageKey))
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(choice.id, forKey: Self.storageKey)
    }

    /// The phone's exact options and order, including Personalized Cardio.
    public var choices: [HomeWorkoutStartChoice] { HomeWorkoutStartChoice.allChoices }

    public mutating func select(_ choice: HomeWorkoutStartChoice) {
        guard choices.contains(choice) else { return }
        self.choice = choice
    }

    public mutating func start() {
        launchChoice = choice
    }

    public mutating func dismissStart() {
        launchChoice = nil
    }
}
