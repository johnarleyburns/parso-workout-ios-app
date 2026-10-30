import Testing
import Foundation
import CadenceCore
@testable import CadenceFeatures

@Suite struct WatchSetEntryParserTests {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")
    private func lb(_ s: String, _ l: Locale? = nil) -> Result<Double, WatchSetEntryParser.Failure> {
        WatchSetEntryParser.weight(s, unit: .pounds, range: 0...650, locale: l ?? us)
    }

    @Test func plainAndSuffixedPounds() {
        for s in ["125", "125 lb", "125 lbs", "125 pounds", " 125 LB "] { #expect(lb(s) == .success(125)) }
    }

    @Test func decimals() {
        #expect(lb("12.5") == .success(12.5))
        #expect(lb("12,5", de) == .success(12.5))
    }

    @Test func wrongUnitRejected() {
        #expect(lb("125 kg") == .failure(.wrongUnit))
        #expect(WatchSetEntryParser.weight("60 lb", unit: .kilograms, range: 0...300) == .failure(.wrongUnit))
        #expect(WatchSetEntryParser.weight("60 kilograms", unit: .kilograms, range: 0...300, locale: us) == .success(60))
    }

    @Test func invalidInputFailsWithoutCrash() {
        #expect(lb("") == .failure(.empty))
        #expect(lb("   ") == .failure(.empty))
        #expect(lb("lb") == .failure(.empty))
        #expect(lb("heavy") == .failure(.notANumber))
        #expect(lb("NaN") == .failure(.notANumber))
        #expect(lb("inf") == .failure(.notANumber))
        #expect(lb("infinity") == .failure(.notANumber))
    }

    @Test func rangesNeverClamp() {
        #expect(lb("-1") == .failure(.outOfRange))
        #expect(lb("650.1") == .failure(.outOfRange))
        #expect(lb("650") == .success(650))
        #expect(WatchSetEntryParser.weight("300.1", unit: .kilograms, range: 0...300, locale: us) == .failure(.outOfRange))
    }

    @Test func reps() {
        #expect(WatchSetEntryParser.reps("8", locale: us) == .success(8))
        #expect(WatchSetEntryParser.reps("0012", locale: us) == .success(12))
        #expect(WatchSetEntryParser.reps("8.5", locale: us) == .failure(.fractionalReps))
        #expect(WatchSetEntryParser.reps("0", locale: us) == .failure(.outOfRange))
        #expect(WatchSetEntryParser.reps("101", locale: us) == .failure(.outOfRange))
        #expect(WatchSetEntryParser.reps("eight", locale: us) == .failure(.notANumber))
        #expect(WatchSetEntryParser.reps("", locale: us) == .failure(.empty))
    }

    @Test func failureCopyMentionsRangeAndUnit() {
        #expect(WatchSetEntryParser.weightMessage(for: .outOfRange, unit: .pounds, range: 0...650).contains("650"))
        #expect(WatchSetEntryParser.weightMessage(for: .wrongUnit, unit: .kilograms, range: 0...300).contains("kg"))
        #expect(WatchSetEntryParser.repsMessage(for: .fractionalReps).contains("100"))
    }
}
