import Foundation

public struct WeekRing: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case sets, cardioMinutes, sessions }
    public let kind: Kind
    public let value: Double
    public let target: Double
    public var id: Kind { kind }
    public var progress: Double { target > 0 ? min(1, max(0, value / target)) : 0 }

    public init(kind: Kind, value: Double, target: Double) {
        self.kind = kind
        self.value = max(0, value)
        self.target = max(0, target)
    }
}

public enum WeekRingsPresenter {
    public static func rings(workingSets: Double, setTarget: Double,
                             cardioMinutes: Double, cardioTarget: Double,
                             sessions: Double, sessionTarget: Double) -> [WeekRing] {
        [WeekRing(kind: .sets, value: workingSets, target: setTarget),
         WeekRing(kind: .cardioMinutes, value: cardioMinutes, target: cardioTarget),
         WeekRing(kind: .sessions, value: sessions, target: sessionTarget)]
    }
}
