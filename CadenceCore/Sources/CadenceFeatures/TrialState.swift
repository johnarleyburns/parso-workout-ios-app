import Foundation
import CadenceCore

/// Pure trial-window arithmetic split out of the app's `StoreService`
/// (test-pyramid Phase 2). The entitlement *resolution* already lives in
/// `CadenceCore.EntitlementResolver`; this covers the remaining StoreKit-free
/// bits: which records define the current trial's end, and how many whole days
/// remain. The StoreKit glue (listening for transactions, scheduling the
/// reminder) stays in the app.
public enum TrialState {

    /// The earliest expiration among active introductory-offer records — the end
    /// of the current free trial, or nil if none.
    public static func endDate(from records: [EntitlementRecord]) -> Date? {
        records
            .filter { $0.isIntroductoryOffer && $0.revocationDate == nil }
            .compactMap(\.expirationDate)
            .min()
    }

    /// Whole days remaining until `end`, clamped at 0; nil when there is no trial.
    public static func daysRemaining(until end: Date?,
                                     now: Date = Date(),
                                     calendar: Calendar = .current) -> Int? {
        guard let end else { return nil }
        let days = calendar.dateComponents([.day], from: now, to: end).day ?? 0
        return max(0, days)
    }
}
