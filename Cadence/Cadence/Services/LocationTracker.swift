import Foundation
import Observation
import CadenceCore
import CoreLocation

/// Observable GPS tracker for iPhone-only outdoor cardio (FR-2.2). Accumulates
/// `LocationFix`es and exposes running distance. Has a `simulated` mode for
/// previews/UI tests that synthesizes a moving track.
@Observable
final class LocationTracker: NSObject, LocationTracking {
    private(set) var fixes: [LocationFix] = []
    private(set) var authorized = false

    private let simulated: Bool
    private var manager: CLLocationManager?
    private var startDate: Date?
    private var simTimer: Timer?

    init(simulated: Bool) {
        self.simulated = simulated
        super.init()
        if !simulated {
            let m = CLLocationManager()
            m.desiredAccuracy = kCLLocationAccuracyBest
            m.activityType = .fitness
            m.allowsBackgroundLocationUpdates = false
            manager = m
            manager?.delegate = self
        }
    }

    var distanceMeters: Double { GeoMath.pathDistance(fixes) }

    func requestAuthorization() {
        guard !simulated else { authorized = true; return }
        manager?.requestWhenInUseAuthorization()
    }

    func start() {
        fixes.removeAll()
        startDate = Date()
        if simulated {
            authorized = true
            var i = 0
            // ~0.0001° ≈ 11 m per tick → believable jog pace
            simTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                i += 1
                self.fixes.append(LocationFix(t: TimeInterval(i), lat: 37.3349 + Double(i) * 0.0001,
                                              lon: -122.0090, elevation: 10, horizontalAccuracy: 5))
            }
            return
        }
        // Keep recording the route during a call / pocket (field-testing §05).
        // The "location" background mode + usage string are in Info.plist.
        manager?.allowsBackgroundLocationUpdates = true
        manager?.showsBackgroundLocationIndicator = true
        manager?.startUpdatingLocation()
    }

    func stop() {
        simTimer?.invalidate(); simTimer = nil
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
