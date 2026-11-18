import Foundation
import Observation
import CadenceCore
import CoreLocation

/// Observable GPS tracker for iPhone-only outdoor cardio (FR-2.2). Accumulates
/// `LocationFix`es and exposes running distance.
@Observable
final class LocationTracker: NSObject, LocationTracking, @unchecked Sendable {
    private(set) var fixes: [LocationFix] = []
    private(set) var authorized = false

    private var manager: CLLocationManager?
    private var startDate: Date?

    override init() {
        super.init()
        let m = CLLocationManager()
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.activityType = .fitness
        m.allowsBackgroundLocationUpdates = false
        manager = m
        manager?.delegate = self
    }

    var distanceMeters: Double { GeoMath.pathDistance(fixes) }

    /// GPS accuracy tier (field-testing §05/§06, decision #19). Balanced by
    /// default to save battery (NFR-7); high for racing/precision.
    func setHighAccuracy(_ high: Bool) {
        manager?.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
    }

    func requestAuthorization() {
        manager?.requestWhenInUseAuthorization()
    }

    func start() {
        fixes.removeAll()
        startDate = Date()
        // Keep recording the route during a call / pocket (field-testing §05).
        // The "location" background mode + usage string are in Info.plist.
        manager?.allowsBackgroundLocationUpdates = true
        manager?.showsBackgroundLocationIndicator = true
        manager?.startUpdatingLocation()
    }

    func stop() {
        manager?.allowsBackgroundLocationUpdates = false
        manager?.stopUpdatingLocation()
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorized = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let start = startDate ?? Date()
        for loc in locations {
            fixes.append(LocationFix(
                t: loc.timestamp.timeIntervalSince(start),
                lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                elevation: loc.altitude, horizontalAccuracy: loc.horizontalAccuracy))
        }
    }
}
