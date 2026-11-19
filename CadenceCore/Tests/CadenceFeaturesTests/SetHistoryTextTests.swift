import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct SetHistoryTextTests {

    @Test func lastSetThisSessionText() {
        // 83.9146 kg ≈ 185 lb
        let set = SetEntry(weight: 83.9146, reps: 8, rpe: 7)
        #expect(SetHistoryText.lastSetThisSession(set, unit: .pounds) ==
                       "Last set 185 lb × 8 · RPE 7")
    }

    @Test func lastSetThisSessionKilograms() {
        let set = SetEntry(weight: 80, reps: 5)
        #expect(SetHistoryText.lastSetThisSession(set, unit: .kilograms) ==
                       "Last set 80 kg × 5")
    }

    @Test func lastSetBodyweightFormat() {
        let set = SetEntry(weight: 10, reps: 12, usesBodyweight: true, rpe: 7)
        #expect(SetHistoryText.lastSetThisSession(set, unit: .kilograms) ==
                       "Last set BW + 10 kg × 12 · RPE 7")
        let pure = SetEntry(weight: 0, reps: 12, usesBodyweight: true)
        #expect(SetHistoryText.lastSetThisSession(pure, unit: .kilograms) ==
                       "Last set BW × 12")
    }

    @Test func lastSetNilForFirstSet() {
        #expect(SetHistoryText.lastSetThisSession(nil, unit: .kilograms) == nil,
                     "No this-session set → nil, never a fabricated default")
    }
}
