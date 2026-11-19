import Testing
@testable import CadenceCore

struct CardioMathTests {

    @Test func hRZones() {
        #expect(CardioMath.hrZone(bpm: 100, maxHR: 200) == 1) // 50%
        #expect(CardioMath.hrZone(bpm: 130, maxHR: 200) == 2) // 65%
        #expect(CardioMath.hrZone(bpm: 150, maxHR: 200) == 3) // 75%
        #expect(CardioMath.hrZone(bpm: 170, maxHR: 200) == 4) // 85%
        #expect(CardioMath.hrZone(bpm: 190, maxHR: 200) == 5) // 95%
    }

    @Test func hRZoneBoundaries() {
        #expect(CardioMath.hrZone(bpm: 120, maxHR: 200) == 2) // exactly 60% → Z2
        #expect(CardioMath.hrZone(bpm: 0, maxHR: 200) == 1)
        #expect(CardioMath.hrZone(bpm: 150, maxHR: 0) == 1)
    }

    @Test func defaultMaxHR() {
        #expect(abs(CardioMath.defaultMaxHR(age: 30) - 187) <= 0.001) // 208 - 21
        #expect(CardioMath.defaultMaxHR(age: nil) == 190)
    }

    @Test func pace() {
        // 1 km in 300 s → 300 s/km
        #expect(abs(CardioMath.paceSecPerKm(distanceMeters: 1000, seconds: 300)! - 300) <= 1e-6)
        #expect(CardioMath.paceSecPerKm(distanceMeters: 0, seconds: 300) == nil)
        #expect(CardioMath.formatPace(secPerKm: 305) == "5:05 /km")
        #expect(CardioMath.formatPace(secPerKm: nil) == "—")
    }

    @Test func caloriesMETFallback() {
        // running 30 min @75kg, no HR: 9.8 * 75 * 0.5 = 367.5
        let kcal = CardioMath.estimateCalories(type: .run, seconds: 1800, avgHR: nil, weightKg: 75)
        #expect(abs(kcal - 367.5) <= 0.5)
    }

    @Test func caloriesHRBasedPositive() {
        let kcal = CardioMath.estimateCalories(type: .run, seconds: 1800, avgHR: 150, weightKg: 75)
        #expect(kcal > 0)
    }

    // MARK: - VO2max estimation

    @Test func cooperVO2max() {
        let vo2 = CardioMath.cooperVO2max(distanceMeters: 2400)
        #expect(abs(vo2 - 42.35) <= 0.1)
    }

    @Test func cooperVO2maxZeroDistance() {
        let vo2 = CardioMath.cooperVO2max(distanceMeters: 0)
        #expect(vo2 < 0)
    }

    @Test func run1_5mileVO2max() {
        let vo2 = CardioMath.run1_5mileVO2max(timeSeconds: 720)
        #expect(abs(vo2 - 43.75) <= 0.1)
    }

    @Test func run1_5mileVO2maxZeroTime() {
        let vo2 = CardioMath.run1_5mileVO2max(timeSeconds: 0)
        #expect(vo2 == 0)
    }

    @Test func rockportVO2max() {
        let vo2 = CardioMath.rockportVO2max(weightKg: 70, ageYears: 30,
                                            sexCode: 1, walkTimeSeconds: 840,
                                            endingHR: 140)
        #expect(vo2 > 20)
        #expect(vo2 < 80)
    }

    @Test func queensCollegeVO2maxMale() {
        let vo2 = CardioMath.queensCollegeVO2max(recoveryHR: 140, sexCode: 1)
        #expect(abs(vo2 - 52.53) <= 0.1)
    }

    @Test func queensCollegeVO2maxFemale() {
        let vo2 = CardioMath.queensCollegeVO2max(recoveryHR: 140, sexCode: 0)
        #expect(abs(vo2 - 39.952) <= 0.1)
    }

    // MARK: - Fitness category

    @Test func fitnessCategoryYoungMaleGood() {
        let cat = CardioMath.fitnessCategory(vo2max: 46.0, ageYears: 25, sexCode: 1)
        #expect(cat == .good)
    }

    @Test func fitnessCategoryOlderFemaleSuperior() {
        let cat = CardioMath.fitnessCategory(vo2max: 50.0, ageYears: 25, sexCode: 0)
        #expect(cat == .superior)
    }

    @Test func fitnessCategoryVeryPoor() {
        let cat = CardioMath.fitnessCategory(vo2max: 15.0, ageYears: 40, sexCode: 1)
        #expect(cat == .veryPoor)
    }
}
