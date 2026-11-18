import Testing
@testable import CadenceCore

struct GeoMathTests {

    @Test func zeroDistanceSamePoint() {
        #expect(abs(GeoMath.distance(lat1: 37.0, lon1: -122.0, lat2: 37.0, lon2: -122.0) - 0) <= 1e-6)
    }

    @Test func knownDistanceOneDegreeLatitude() {
        // ~111.19 km per degree of latitude
        let d = GeoMath.distance(lat1: 0, lon1: 0, lat2: 1, lon2: 0)
        #expect(abs(d - 111_195) <= 500)
    }

    @Test func pathDistanceAccumulates() {
        let fixes = [
            LocationFix(t: 0, lat: 0, lon: 0),
            LocationFix(t: 1, lat: 0, lon: 0.001),
            LocationFix(t: 2, lat: 0, lon: 0.002)
        ]
        let total = GeoMath.pathDistance(fixes)
        let single = GeoMath.distance(lat1: 0, lon1: 0, lat2: 0, lon2: 0.001)
        #expect(abs(total - single * 2) <= 1e-3)
    }

    @Test func pathDistanceEmptyOrSingle() {
        #expect(GeoMath.pathDistance([]) == 0)
        #expect(GeoMath.pathDistance([LocationFix(t: 0, lat: 1, lon: 1)]) == 0)
    }
}
