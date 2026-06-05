import Foundation
import Observation
import CadenceCore

/// Drives a live iPhone-recorded cardio workout (FR-2.2–2.4): elapsed time,
/// GPS distance/pace, live HR + zone, and a calorie estimate. Pulls from the
/// injected `LocationTracker` and `HeartRateMonitor` (real or simulated).
@Observable
final class CardioRecorder {
    private let location: LocationTracker
    private let hrm: HeartRateMonitor
    let maxHR: Double

    private(set) var type: CardioType = .run
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: Int = 0
    private(set) var startDate = Date()
    private(set) var hrSamples: [HRSamplePoint] = []

    init(location: LocationTracker, hrm: HeartRateMonitor, maxHR: Double = 190) {
        self.location = location
        self.hrm = hrm
        self.maxHR = maxHR
    }

    // MARK: Control

    func start(type: CardioType) {
        self.type = type
        elapsed = 0
        hrSamples = []
        startDate = Date()
        isRecording = true
        isPaused = false
        if type.usesGPS { location.start() }
    }

    func tick() {
        guard isRecording, !isPaused else { return }
        elapsed += 1
        if let bpm = hrm.currentBPM, bpm > 0 {
            hrSamples.append(HRSamplePoint(t: TimeInterval(elapsed), bpm: bpm))
        }
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func connectStrap() {
        hrm.startScanning()
        if let first = hrm.discovered.first { hrm.connect(first.id) }
    }

    /// Ends recording and returns a summary ready to persist (FR-2.5).
    func end() -> CardioWorkoutSummary {
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

    var currentBPM: Double? { hrm.currentBPM }
    var distanceMeters: Double { type.usesGPS ? location.distanceMeters : 0 }
    var pace: Double? { CardioMath.paceSecPerKm(distanceMeters: distanceMeters, seconds: TimeInterval(elapsed)) }
    var avgHR: Double? {
        let v = hrSamples.map(\.bpm).filter { $0 > 0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    var zone: Int { CardioMath.hrZone(bpm: currentBPM ?? 0, maxHR: maxHR) }
    var calories: Double {
        CardioMath.estimateCalories(type: type, seconds: TimeInterval(elapsed), avgHR: avgHR)
    }
    var strapConnected: Bool {
        if case .connected = hrm.state { return true }
        return false
    }
}
