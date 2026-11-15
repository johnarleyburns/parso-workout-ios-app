import Foundation

public enum HomeStrengthStartChoice: String, CaseIterable, Identifiable, Sendable {
    case quickStart, suggested, previous
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .quickStart: "Quick Start"
        case .suggested: "Suggested"
        case .previous: "Previous"
        }
    }
}

public enum HomeRecentCardioChoices {
    public static func recent<T: Hashable>(_ types: [T]) -> [T] {
        var seen = Set<T>()
        return Array(types.filter { seen.insert($0).inserted }.prefix(3))
    }
}
