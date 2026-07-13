import Foundation
import Observation
import CadenceCore

/// Drives a live iPhone-recorded cardio workout (FR-2.2–2.4): elapsed time,
/// GPS distance/pace, live HR + zone, and a calorie estimate. Pulls from the
/// injected `LocationTracking` and `HeartRateMonitoring` services (real or fake).
///
/// Moved into CadenceFeatures (test-pyramid Phase 2). It now depends on the
/// CadenceCore service *protocols* rather than the app's concrete adapters, so it
/// is exercisable headlessly with fakes.
@Observable
public final class CardioRecorder {
    private let location: LocationTracking
    private let hrm: HeartRateMonitoring
    public let maxHR: Double

    public private(set) var type: CardioType = .run
    public private(set) var isRecording = false
    public private(set) var isPaused = false
    public private(set) var elapsed: Int = 0
    public private(set) var startDate = Date()
    public private(set) var hrSamples: [HRSamplePoint] = []

    public init(location: LocationTracking, hrm: HeartRateMonitoring, maxHR: Double = 190) {
        self.location = location
        self.hrm = hrm
        self.maxHR = maxHR
    }

    // MARK: Control

    public func start(type: CardioType) {
        self.type = type
        elapsed = 0
        hrSamples = []
        startDate = Date()
        isRecording = true
        isPaused = false
        if type.usesGPS { location.start() }
    }

    public func tick() {
        guard isRecording, !isPaused else { return }
        elapsed += 1
        if let bpm = hrm.currentBPM, bpm > 0 {
            hrSamples.append(HRSamplePoint(t: TimeInterval(elapsed), bpm: bpm))
        }
    }

    public func pause() { isPaused = true }
    public func resume() { isPaused = false }

    public func connectStrap() {
        hrm.startScanning()
        if let first = hrm.discovered.first { hrm.connect(first.id) }
    }

    /// Ends recording and returns a summary ready to persist (FR-2.5).
    public func end() -> CardioWorkoutSummary {
        isRecording = false
        if type.usesGPS { location.stop() }
        let summary = CardioWorkoutSummary(
            id: UUID(), type: type, start: startDate, end: Date(),
            distanceMeters: type.usesGPS ? location.distanceMeters : nil,
            activeEnergyKcal: calories,
            hrSamples: hrSamples,
            route: type.usesGPS ? location.fixes : [])
        return summary
    }

    // MARK: Derived metrics

    public var currentBPM: Double? { hrm.currentBPM }
    public var distanceMeters: Double { type.usesGPS ? location.distanceMeters : 0 }
    public var pace: Double? { CardioMath.paceSecPerKm(distanceMeters: distanceMeters, seconds: TimeInterval(elapsed)) }
    public var avgHR: Double? {
        let v = hrSamples.map(\.bpm).filter { $0 > 0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    public var zone: Int { CardioMath.hrZone(bpm: currentBPM ?? 0, maxHR: maxHR) }
    public var calories: Double {
        CardioMath.estimateCalories(type: type, seconds: TimeInterval(elapsed), avgHR: avgHR)
    }
    public var strapConnected: Bool {
        if case .connected = hrm.state { return true }
        return false
    }
}
