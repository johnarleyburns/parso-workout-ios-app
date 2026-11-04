import Foundation
import Testing
@testable import CadenceFeatures

@Suite struct WatchNumericEntryTests {
    private func type(_ keys: [String], _ field: WatchNumericField) -> String {
        keys.reduce("") { WatchNumericKeypad.apply($1, to: $0, field: field) }
    }

    @Test func weightKeypad() {
        #expect(type(["1"], .weight) == "1")
        #expect(type(["1", "0"], .weight) == "10")
        #expect(type(["1", "0", ".", "2", "5"], .weight) == "10.25")
        #expect(type(["1", ".", "2", ".", "5"], .weight) == "1.25")
        #expect(type(["1", ".", "2", "5", "7"], .weight) == "1.25")
        #expect(type([".", "5"], .weight) == "0.5")
        #expect(type(["1", "0", "⌫"], .weight) == "1")
        #expect(type(["⌫"], .weight) == "")
    }

    @Test func repsKeypadRejectsDecimal() {
        #expect(type(["1", "2", "."], .reps) == "12")
        #expect(type(["."], .reps) == "")
        #expect(type(["0", "5"], .reps) == "5")
    }

    @Test func spokenNumbers() {
        #expect(WatchSpokenNumber.normalize("eight") == "8")
        #expect(WatchSpokenNumber.normalize("ten point two five") == "10.25")
        #expect(WatchSpokenNumber.normalize("one hundred twenty-five") == "125")
        #expect(WatchSpokenNumber.normalize("point five") == "0.5")
        #expect(WatchSpokenNumber.normalize("about ten") == nil)
        #expect(WatchSpokenNumber.normalize("negative five") == nil)
        #expect(WatchSpokenNumber.normalize("infinity") == nil)
        #expect(WatchSpokenNumber.normalize("ten point") == nil)
        #expect(WatchSpokenNumber.normalize("twenty twenty") == nil)
    }

    @Test func parserUsesSpokenAndRejectsUnits() {
        let us = Locale(identifier: "en_US")
        #expect(WatchSetEntryParser.weight("ten point two five", unit: .pounds, range: 0...650, locale: us) == .success(10.25))
        #expect(WatchSetEntryParser.weight("eight kilograms", unit: .pounds, range: 0...650, locale: us) == .failure(.wrongUnit))
        #expect(WatchSetEntryParser.weight("about ten", unit: .pounds, range: 0...650, locale: us) == .failure(.notANumber))
        #expect(WatchSetEntryParser.reps("ten point five", locale: us) == .failure(.fractionalReps))
    }
}
