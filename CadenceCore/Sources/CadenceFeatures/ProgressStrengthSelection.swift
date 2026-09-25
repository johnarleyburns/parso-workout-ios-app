import Foundation

/// The lifts selected in Progress → Strength over time. The default powerlifting
/// view is persisted separately from the chart data so custom lifts can be
/// selected without changing the four canonical series.
public struct ProgressStrengthSelection: Equatable, Sendable {
    public static let persistenceKey = "progress.selectedStrengthLifts.v1"
    public static let defaultNames: Set<String> = [
        "Bench Press", "Barbell Squat", "Deadlift", "Combined"
    ]

    public private(set) var selectedNames: Set<String>

    public init(selectedNames: Set<String> = Self.defaultNames) {
        self.selectedNames = selectedNames
    }

    public static func persisted(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: persistenceKey),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return Self()
        }
        return Self(selectedNames: Set(names.map(migratedName)))
    }

    public func persist(defaults: UserDefaults = .standard) {
        let names = selectedNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }

    public mutating func toggle(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }

    private static func migratedName(_ name: String) -> String {
        name == "Squat" ? "Barbell Squat" : name
    }
}
