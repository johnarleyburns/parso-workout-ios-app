import Foundation
import CadenceCore

/// Where a phone-owned strength workout's heart-rate observation came from.
public enum HeartRateObservationSource: String, Codable, Sendable {
    case watchHealthKit, watchBLE, phoneBLE

    public var coverageSource: HeartRateSource {
        switch self {
        case .watchHealthKit: return .watchHealthKit
        case .watchBLE: return .watchBLE
        case .phoneBLE: return .phone
        }
    }
}
