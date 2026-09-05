import Foundation

/// Send-time invariant for §10.4: a shared plan must carry concrete loads for
/// every percentage prescription. The client's e1RM is consulted before this
/// boundary; it is never needed by the recipient and can never drift a sent
/// plan later.
public enum PlanSendPreflightError: Error, Equatable, Sendable {
    case unsnapshottedPercentLoads([UUID])
    case invalidPercentLoads([UUID])
}

public enum PlanSendPreflight {
    public static func validate(_ plan: Plan) throws {
        try plan.validate()
        var unsnapshotted: [UUID] = []
        var invalid: [UUID] = []

        for week in plan.weeks {
            for day in week.days {
                for session in day.sessions {
                    for item in session.items {
                        guard case let .strength(strength) = item else { continue }
                        for set in strength.sets {
                            guard case let .percent1RM(percent, calculatedWeight) = set.load else { continue }
                            if !(0...1).contains(percent) || calculatedWeight.map({ $0 <= 0 }) == true {
                                invalid.append(set.id)
                            } else if calculatedWeight == nil {
                                unsnapshotted.append(set.id)
                            }
                        }
                    }
                }
            }
        }

        if !invalid.isEmpty { throw PlanSendPreflightError.invalidPercentLoads(invalid) }
        if !unsnapshotted.isEmpty {
            throw PlanSendPreflightError.unsnapshottedPercentLoads(unsnapshotted)
        }
    }
}
