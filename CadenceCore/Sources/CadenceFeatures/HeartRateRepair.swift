import Foundation
import CadenceCore

/// A candidate Apple Health workout, stripped to what matching and selection need.
/// `token` is opaque to this layer; it is never persisted or logged.
public struct HealthWorkoutCandidate: Equatable, Sendable, Identifiable {
    public let token: String
    public let start: Date
    public let end: Date
    public let isStrength: Bool
    public let sourceName: String
    public let isFromThisApp: Bool
    public var id: String { token }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public init(token: String, start: Date, end: Date, isStrength: Bool, sourceName: String, isFromThisApp: Bool) {
        self.token = token; self.start = start; self.end = end
        self.isStrength = isStrength; self.sourceName = sourceName; self.isFromThisApp = isFromThisApp
    }
}

public enum HealthRepairError: Error, Equatable, Sendable { case authorization, query }

/// HealthKit query abstraction so repair is testable without a store.
public protocol HealthHeartRateSource: Sendable {
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate]
    /// Absolute-time HR samples associated with the workout, bounded to its interval.
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)]
}

public enum HeartRateRepairOutcome: Equatable, Sendable {
    case noMatch
    case needsSelection([HealthWorkoutCandidate])
    case noHeartRateSamples
    case accessError(HealthRepairError)
    /// Repaired data is not demonstrably better; nothing changed until the user confirms.
    case needsReplacementConfirmation(existingCovered: TimeInterval, repairedCovered: TimeInterval)
    case repaired(classifiedMinutes: Int, totalMinutes: Int)
}

public enum HeartRateRepair {
    /// Tolerance used only to find candidate workouts, never to accept samples.
    public static let matchTolerance: TimeInterval = 10 * 60
    /// Candidate duration must be within this fraction of the session duration.
    public static let durationTolerance = 0.25

    /// Sparse, absent, or materially unclassified coverage of a completed session.
    public static func isRepairable(_ session: WorkoutSession) -> Bool {
        guard session.endedAt != nil, session.duration > 0 else { return false }
        return HeartRateCoverageState.evaluate(summary: session.intensitySummary,
                                               sampleCount: session.hrSamplePoints.count) != .complete
    }

    public static func matches(_ session: WorkoutSession, _ list: [HealthWorkoutCandidate]) -> [HealthWorkoutCandidate] {
        guard let end = session.endedAt else { return [] }
        let start = session.date
        let strength = list.filter { $0.isStrength && $0.end > start && $0.start < end }
        let sessionDuration = end.timeIntervalSince(start)
        let credible = strength.filter {
            abs($0.start.timeIntervalSince(start)) <= matchTolerance
                && abs($0.duration - sessionDuration) <= max(matchTolerance, sessionDuration * durationTolerance)
        }
        let own = credible.filter(\.isFromThisApp)
        return own.count == 1 ? own : credible
    }

    @MainActor
    public static func run(session: WorkoutSession, source: some HealthHeartRateSource,
                           profile: CardioIntensityProfile,
                           chosen: HealthWorkoutCandidate? = nil,
                           confirmReplacement: Bool = false,
                           now: Date = Date(),
                           save: () throws -> Void = {}) async -> HeartRateRepairOutcome {
        guard let end = session.endedAt else { return .noMatch }
        let candidate: HealthWorkoutCandidate
        if let chosen {
            candidate = chosen
        } else {
            let list: [HealthWorkoutCandidate]
            do {
                list = try await source.workouts(from: session.date.addingTimeInterval(-matchTolerance),
                                                 to: end.addingTimeInterval(matchTolerance))
            } catch let error as HealthRepairError { return .accessError(error) }
            catch { return .accessError(.query) }
            let found = matches(session, list)
            if found.isEmpty { return .noMatch }
            if found.count > 1 { return .needsSelection(found) }
            candidate = found[0]
        }
        let raw: [(date: Date, bpm: Double)]
        do { raw = try await source.heartRate(for: candidate) }
        catch let error as HealthRepairError { return .accessError(error) }
        catch { return .accessError(.query) }
        let duration = end.timeIntervalSince(session.date)
        let points = HRSampleNormalizer.normalize(
            raw.filter { $0.date >= candidate.start && $0.date <= candidate.end }
                .map { HRSamplePoint(t: $0.date.timeIntervalSince(session.date), bpm: $0.bpm) },
            duration: duration)
        guard !points.isEmpty else { return .noHeartRateSamples }

        let summary = CardioMinuteAccumulator.summarize(duration: duration, samples: points, profile: profile)
        let existing = session.intensitySummary?.classifiedDuration ?? 0
        if !confirmReplacement, !session.hrSamplePoints.isEmpty, summary.classifiedDuration <= existing {
            return .needsReplacementConfirmation(existingCovered: existing, repairedCovered: summary.classifiedDuration)
        }
        // Validated and recomputed; apply atomically (restore on save failure).
        let backup = HeartRateBackup(samples: session.hrSamplePoints, summary: session.intensitySummary,
                                     coverage: session.hrCoverage)
        session.recordHeartRate(points, profile: profile, source: .repairedHealthKit, at: now)
        session.hrBackup = backup
        do { try save() } catch {
            restore(backup, to: session)
            session.hrBackup = nil
            return .accessError(.query)
        }
        return .repaired(classifiedMinutes: Int((summary.classifiedDuration / 60).rounded()),
                         totalMinutes: Int((duration / 60).rounded()))
    }

    private static func restore(_ backup: HeartRateBackup, to session: WorkoutSession) {
        session.hrSamplePoints = backup.samples
        session.intensitySummary = backup.summary
        session.hrCoverage = backup.coverage
    }

    /// Reverts the most recent repair. Returns false when there is nothing to restore.
    @discardableResult
    public static func restorePrevious(_ session: WorkoutSession, save: () throws -> Void = {}) -> Bool {
        guard let backup = session.hrBackup else { return false }
        restore(backup, to: session)
        session.hrBackup = nil
        session.updatedAt = Date()
        do { try save() } catch { return false }
        return true
    }
}
