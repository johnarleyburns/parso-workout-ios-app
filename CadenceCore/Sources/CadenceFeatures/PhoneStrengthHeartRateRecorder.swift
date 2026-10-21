import Foundation
import SwiftData
import OSLog
import CadenceCore

/// Where a phone-owned strength workout's heart-rate observation came from.
public enum HeartRateObservationSource: String, Codable, Sendable {
    case watchHealthKit, watchBLE, phoneBLE

    var coverageSource: HeartRateSource {
        switch self {
        case .watchHealthKit: return .watchHealthKit
        case .watchBLE: return .watchBLE
        case .phoneBLE: return .phone
        }
    }
}

/// One real physiological measurement. `observedAt` is the measurement's own end
/// time (never the receipt time); relay heartbeats/retries must reuse the
/// original `observedAt` and so deduplicate instead of manufacturing coverage.
public struct HeartRateObservation: Equatable, Sendable {
    public var source: HeartRateObservationSource
    public var observedAt: Date
    public var bpm: Double
    public var requestID: UUID?
    public var sampleID: String?
    public init(source: HeartRateObservationSource, observedAt: Date, bpm: Double,
                requestID: UUID? = nil, sampleID: String? = nil) {
        self.source = source; self.observedAt = observedAt; self.bpm = bpm
        self.requestID = requestID; self.sampleID = sampleID
    }
}

public enum HeartRateRecordOutcome: Equatable, Sendable {
    case accepted
    case duplicate
    case rejected(Reason)
    public enum Reason: String, Sendable {
        case invalidBPM, invalidTimestamp, beforeSession, afterSession
    }
}

/// Session-owned collector for phone-owned strength heart rate. It is keyed to
/// one `WorkoutSession` and is deliberately independent of any SwiftUI view:
/// observations are captured at the transport event and written to the session
/// (`hrSamplesData`), so minimize/reopen, view recreation and process recovery
/// cannot erase them. Re-adopting a session re-reads the persisted series, so
/// nothing is double counted.
///
/// Storage bound: at most `maximumStoredSamples` points. Past that, adjacent
/// pairs are merged keeping the higher BPM of each pair, which at most doubles
/// the spacing (preserving extrema and coverage shape) and is deterministic.
@MainActor
public final class PhoneStrengthHeartRateRecorder {
    public static let minimumBPM = 20.0
    public static let maximumBPM = 250.0
    public static let maximumStoredSamples = 4000
    /// Accepted observations buffered before a write to the store.
    public static let flushBatchSize = 6
    /// Tolerance for clock skew around the session boundaries.
    public static let boundaryTolerance: TimeInterval = 5

    private static let log = Logger(subsystem: "guru.parso.cadence", category: "PhoneHeartRate")

    public let sessionID: UUID
    private let session: WorkoutSession
    private let save: () throws -> Void
    private var samples: [HRSamplePoint]
    private var knownIDs = Set<String>()
    private var unflushed = 0
    public private(set) var source: HeartRateObservationSource?
    /// True when a write failed and data is held in memory awaiting retry.
    public private(set) var persistencePending = false
    /// Sample count at the last successful finalize; repeated finish/recovery
    /// calls with nothing new are no-ops (idempotent).
    private var finalizedCount: Int?

    public init(session: WorkoutSession, save: (() throws -> Void)? = nil) {
        self.session = session
        self.sessionID = session.id
        self.save = save ?? { try session.modelContext?.save() }
        self.samples = session.hrSamplePoints.sorted { $0.t < $1.t }
    }

    /// Read-only live snapshot, ordered by time.
    public var snapshot: [HRSamplePoint] { samples }

    @discardableResult
    public func record(_ obs: HeartRateObservation, now: Date = Date()) -> HeartRateRecordOutcome {
        guard obs.bpm.isFinite, obs.bpm >= Self.minimumBPM, obs.bpm <= Self.maximumBPM else {
            return .rejected(.invalidBPM)
        }
        guard obs.observedAt.timeIntervalSince1970.isFinite else { return .rejected(.invalidTimestamp) }
        let t = (obs.observedAt.timeIntervalSince(session.date) * 1000).rounded() / 1000
        guard t >= -Self.boundaryTolerance else { return .rejected(.beforeSession) }
        let ceiling = (session.endedAt ?? now).timeIntervalSince(session.date) + Self.boundaryTolerance
        guard t <= ceiling else { return .rejected(.afterSession) }
        let clampedT = max(0, t)

        if let id = obs.sampleID {
            guard knownIDs.insert(id).inserted else {
                Self.log.debug("observation deduplicated (identity)")
                return .duplicate
            }
        }
        if samples.contains(where: { abs($0.t - clampedT) < 0.0005 }) {
            Self.log.debug("observation deduplicated (timestamp)")
            return .duplicate
        }
        finalizedCount = nil
        samples.append(HRSamplePoint(t: clampedT, bpm: obs.bpm.rounded()))
        samples.sort { $0.t < $1.t }
        if samples.count > Self.maximumStoredSamples { downsample() }
        source = obs.source
        unflushed += 1
        Self.log.debug("observation accepted, count \(self.samples.count, privacy: .public)")
        if unflushed >= Self.flushBatchSize || persistencePending { _ = flush() }
        return .accepted
    }

    /// Writes the series to the session and saves. Returns false (keeping the
    /// data in memory and flagged pending) when the store write fails.
    @discardableResult
    public func flush() -> Bool {
        let previous = session.hrSamplesData
        session.hrSamplePoints = samples
        do {
            try save()
            unflushed = 0
            persistencePending = false
            Self.log.debug("persisted, count \(self.samples.count, privacy: .public)")
            return true
        } catch {
            session.hrSamplesData = previous
            persistencePending = true
            Self.log.error("persistence failed, held pending")
            return false
        }
    }

    /// Mandatory final flush. On success stores the guideline split from the
    /// persisted series. Returns false if persistence is pending, in which case
    /// the caller must not present a final zero-cardio result.
    @discardableResult
    public func finalize(profile: CardioIntensityProfile, at date: Date = Date()) -> Bool {
        guard flush() else { return false }
        guard !samples.isEmpty else { return true }
        if finalizedCount == samples.count { return true }
        // A user-confirmed manual cardio override stays authoritative: the
        // measured series is kept, but the override is not silently erased.
        let manual = session.isManualCardioMinutesOverride
        let explicit = session.hasManualCardioMinutesOverride
        let manualSummary = session.intensitySummary
        session.recordHeartRate(samples, profile: profile,
                                source: source?.coverageSource ?? .phone, at: date)
        if manual {
            session.hasManualCardioMinutesOverride = explicit
            session.intensitySummary = manualSummary
        }
        do { try save() } catch { persistencePending = true; return false }
        finalizedCount = samples.count
        let gap = zip(samples, samples.dropFirst()).map { $1.t - $0.t }.max() ?? 0
        Self.log.debug("finalized, maximum gap \(Int(gap), privacy: .public)s")
        return true
    }

    private func downsample() {
        var out: [HRSamplePoint] = []
        out.reserveCapacity(samples.count / 2 + 1)
        var i = 0
        while i < samples.count {
            if i + 1 < samples.count {
                let a = samples[i], b = samples[i + 1]
                out.append(a.bpm >= b.bpm ? a : b)
            } else {
                out.append(samples[i])
            }
            i += 2
        }
        samples = out
    }
}
