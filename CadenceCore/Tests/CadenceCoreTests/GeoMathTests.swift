import XCTest
@testable import CadenceCore

final class GeoMathTests: XCTestCase {

    func testZeroDistanceSamePoint() {
        XCTAssertEqual(GeoMath.distance(lat1: 37.0, lon1: -122.0, lat2: 37.0, lon2: -122.0), 0, accuracy: 1e-6)
    }

    func testKnownDistanceOneDegreeLatitude() {
        // ~111.19 km per degree of latitude
        let d = GeoMath.distance(lat1: 0, lon1: 0, lat2: 1, lon2: 0)
        XCTAssertEqual(d, 111_195, accuracy: 500)
    }

    func testPathDistanceAccumulates() {
        let fixes = [
            LocationFix(t: 0, lat: 0, lon: 0),
            LocationFix(t: 1, lat: 0, lon: 0.001),
            LocationFix(t: 2, lat: 0, lon: 0.002)
        ]
        let total = GeoMath.pathDistance(fixes)
        let single = GeoMath.distance(lat1: 0, lon1: 0, lat2: 0, lon2: 0.001)
        XCTAssertEqual(total, single * 2, accuracy: 1e-3)
    }

    func testPathDistanceEmptyOrSingle() {
        XCTAssertEqual(GeoMath.pathDistance([]), 0)
        XCTAssertEqual(GeoMath.pathDistance([LocationFix(t: 0, lat: 1, lon: 1)]), 0)
    }
}
