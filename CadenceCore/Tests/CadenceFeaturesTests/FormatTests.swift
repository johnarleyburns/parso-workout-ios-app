import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct FormatTests {
    @Test func weightKilograms() {
        #expect(Format.weight(100, unit: .kilograms, decimals: 0) == "100 kg")
    }

    @Test func weightValueNoUnit() {
        #expect(Format.weightValue(60, unit: .kilograms, decimals: 0) == "60")
    }

    @Test func weightValueQuarterPreservesQuarterUnitLoads() {
        #expect(Format.weightValueQuarter(20.25, unit: .kilograms) == "20.25")
        #expect(Format.weightValueQuarter(20.26, unit: .kilograms) == "20.25")
    }

    @Test func previousShort() {
        #expect(Format.previousShort(60, reps: 8, unit: .kilograms) == "60×8")
    }

    @Test func duration() {
        #expect(Format.duration(90) == "1:30")
        #expect(Format.duration(3661) == "1:01:01")
        #expect(Format.duration(0) == "0:00")
    }

    @Test func clock() {
        #expect(Format.clock(90) == "1:30")
        #expect(Format.clock(5) == "0:05")
    }

    @Test func distance() {
        #expect(Format.distance(1500) == "1.50 km")
        #expect(Format.distance(500) == "500 m")
    }

    @Test func heartRate() {
        #expect(Format.heartRate(nil) == "—")
        #expect(Format.heartRate(180) == "180 bpm")
    }

    @Test func rxLoadPounds() {
        #expect(Format.rxLoad(male: 95, female: 65, unit: .pounds) == "95/65 lb")
        #expect(Format.rxLoad(male: 95, female: nil, unit: .pounds) == "95 lb")
        #expect(Format.rxLoad(male: 95, female: 95, unit: .pounds) == "95 lb")
        #expect(Format.rxLoad(male: nil, female: 65, unit: .pounds) == nil)
    }

    @Test func rxLoadKilogramsAddsConversion() {
        #expect(Format.rxLoad(male: 95, female: 65, unit: .kilograms) == "95/65 lb (43/29 kg)")
    }
}
