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

/// One Health heart-rate reading with its provenance, for the legacy fallback.
public struct HealthHeartSample: Equatable, Sendable {
    public let date: Date
    public let bpm: Double
    public let isAppleWatch: Bool
    public init(date: Date, bpm: Double, isAppleWatch: Bool) {
        self.date = date; self.bpm = bpm; self.isAppleWatch = isAppleWatch
    }
}

/// What a repair would change, shown before the user confirms. Nothing is
/// modified until the same repair is re-run with `confirmed: true`.
public struct HeartRateRepairPreview: Equatable, Sendable {
    public let sourceName: String
    public let sessionStart: Date
    public let sessionEnd: Date
    public let beforeClassifiedMinutes: Int
    public let afterClassifiedMinutes: Int
    public let sampleCount: Int
    /// True when no associated Health workout exists and the samples were found
    /// by the session window alone.
    public let isLegacyFallback: Bool
    /// True when the proposal covers no more of the workout than what is saved;
    /// applying it needs explicit replacement consent.
    public let isLowerQuality: Bool
    /// The exact data previewed. Confirming applies this, never a fresh query.
    public let proposal: HeartRateRepairProposal
}

/// Immutable record of exactly what the user previewed.
public struct HeartRateRepairProposal: Equatable, Sendable {
    public let sessionID: UUID
    /// `WorkoutSession.updatedAt` when previewed; apply requires it to be unchanged.
    public let sessionRevision: Date
    /// Opaque Health workout association (nil for the legacy Watch-sample fallback).
    public let associationToken: String?
    public let sourceName: String
    public let isLegacyFallback: Bool
    /// Normalized observations (seconds since session start, BPM) that will be stored.
    public let observations: [HRSamplePoint]
    public let summary: CardioMinuteSummary
    public let beforeSummary: CardioMinuteSummary?
}

public enum HealthRepairError: Error, Equatable, Sendable { case authorization, query }

/// HealthKit query abstraction so repair is testable without a store.
public protocol HealthHeartRateSource: Sendable {
    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate]
    /// Absolute-time HR samples associated with the workout, bounded to its interval.
    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)]
    /// Window-bounded readings with provenance, used only by the legacy fallback.
    func heartRateSamples(from: Date, to: Date) async throws -> [HealthHeartSample]
}

public extension HealthHeartRateSource {
    func heartRateSamples(from: Date, to: Date) async throws -> [HealthHeartSample] { [] }
}

public enum HeartRateRepairOutcome: Equatable, Sendable {
    case noMatch
    /// Proposed change; the original is untouched until the user confirms.
    case preview(HeartRateRepairPreview)
    case needsSelection([HealthWorkoutCandidate])
    case noHeartRateSamples
    case accessError(HealthRepairError)
    /// Repaired data is not demonstrably better; nothing changed until the user confirms.
    case needsReplacementConfirmation(existingCovered: TimeInterval, repairedCovered: TimeInterval)
    case repaired(classifiedMinutes: Int, totalMinutes: Int)
    /// The session changed after the preview; a new preview is required.
    case staleProposal
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
                           confirmed: Bool = true,
                           allowLegacyFallback: Bool = false,
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
            let stored = session.healthKitWorkoutUUID?.uuidString
            let found: [HealthWorkoutCandidate]
            if let stored, let exact = list.first(where: { $0.token == stored }) {
                found = [exact]
            } else {
                found = matches(session, list)
            }
            if found.isEmpty {
                guard allowLegacyFallback else { return .noMatch }
                return await legacyFallback(session: session, source: source, profile: profile,
                                            confirmed: confirmed, now: now, save: save)
            }
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
        let proposal = makeProposal(session: session, points: points, summary: summary,
                                    token: candidate.token, sourceName: candidate.sourceName, legacy: false)
        if !confirmed { return .preview(makePreview(session: session, proposal: proposal)) }
        return apply(proposal, to: session, confirmReplacement: confirmReplacement, now: now, save: save)
    }

    private static func makeProposal(session: WorkoutSession, points: [HRSamplePoint], summary: CardioMinuteSummary,
                                     token: String?, sourceName: String, legacy: Bool) -> HeartRateRepairProposal {
        HeartRateRepairProposal(sessionID: session.id, sessionRevision: session.updatedAt, associationToken: token,
                                sourceName: sourceName, isLegacyFallback: legacy, observations: points,
                                summary: summary, beforeSummary: session.intensitySummary)
    }

    private static func makePreview(session: WorkoutSession, proposal: HeartRateRepairProposal) -> HeartRateRepairPreview {
        let existing = session.intensitySummary?.classifiedDuration ?? 0
        return HeartRateRepairPreview(
            sourceName: proposal.sourceName, sessionStart: session.date, sessionEnd: session.endedAt ?? session.date,
            beforeClassifiedMinutes: Int((existing / 60).rounded()),
            afterClassifiedMinutes: Int((proposal.summary.classifiedDuration / 60).rounded()),
            sampleCount: proposal.observations.count, isLegacyFallback: proposal.isLegacyFallback,
            isLowerQuality: !session.hrSamplePoints.isEmpty && proposal.summary.classifiedDuration <= existing,
            proposal: proposal)
    }

    /// Older builds discarded the Health association. Accept only Apple Watch
    /// readings strictly inside the known session window, and only after the
    /// user confirms the previewed change; never replaces better coverage.
    @MainActor
    private static func legacyFallback(session: WorkoutSession, source: some HealthHeartRateSource,
                                       profile: CardioIntensityProfile, confirmed: Bool,
                                       now: Date, save: () throws -> Void) async -> HeartRateRepairOutcome {
        guard let end = session.endedAt else { return .noMatch }
        let raw: [HealthHeartSample]
        do { raw = try await source.heartRateSamples(from: session.date, to: end) }
        catch let error as HealthRepairError { return .accessError(error) }
        catch { return .accessError(.query) }
        let duration = end.timeIntervalSince(session.date)
        let points = HRSampleNormalizer.normalize(
            raw.filter { $0.isAppleWatch && $0.date > session.date && $0.date < end }
                .map { HRSamplePoint(t: $0.date.timeIntervalSince(session.date), bpm: $0.bpm) },
            duration: duration)
        guard !points.isEmpty else { return .noMatch }
        let summary = CardioMinuteAccumulator.summarize(duration: duration, samples: points, profile: profile)
        guard summary.classifiedDuration > (session.intensitySummary?.classifiedDuration ?? 0) else {
            return .needsReplacementConfirmation(existingCovered: session.intensitySummary?.classifiedDuration ?? 0,
                                                 repairedCovered: summary.classifiedDuration)
        }
        guard confirmed else {
            return .preview(makePreview(session: session, proposal: makeProposal(
                session: session, points: points, summary: summary, token: nil,
                sourceName: "Apple Watch", legacy: true)))
        }
        return apply(makeProposal(session: session, points: points, summary: summary, token: nil,
                                  sourceName: "Apple Watch", legacy: true),
                     to: session, confirmReplacement: true, now: now, save: save)
    }

    /// Everything a repair or undo can touch, captured so a failed save restores it exactly.
    private struct Snapshot {
        let samplesData: String, summaryData: String, coverageData: String, backupData: String
        let manualOverride: Bool, updatedAt: Date
        @MainActor init(_ s: WorkoutSession) {
            samplesData = s.hrSamplesData; summaryData = s.intensitySummaryData
            coverageData = s.hrCoverageData; backupData = s.hrBackupData
            manualOverride = s.hasManualCardioMinutesOverride; updatedAt = s.updatedAt
        }
        @MainActor func restore(to s: WorkoutSession) {
            s.hrSamplesData = samplesData; s.intensitySummaryData = summaryData
            s.hrCoverageData = coverageData; s.hrBackupData = backupData
            s.hasManualCardioMinutesOverride = manualOverride; s.updatedAt = updatedAt
        }
    }

    /// Applies exactly the previewed proposal. Rejects it if the session changed
    /// since the preview; on save failure every touched field is restored.
    @MainActor
    public static func apply(_ proposal: HeartRateRepairProposal, to session: WorkoutSession,
                             confirmReplacement: Bool = false, now: Date = Date(),
                             save: () throws -> Void = {}) -> HeartRateRepairOutcome {
        guard proposal.sessionID == session.id, proposal.sessionRevision == session.updatedAt else {
            return .staleProposal
        }
        let existing = session.intensitySummary?.classifiedDuration ?? 0
        if !confirmReplacement, !session.hrSamplePoints.isEmpty, proposal.summary.classifiedDuration <= existing {
            return .needsReplacementConfirmation(existingCovered: existing,
                                                 repairedCovered: proposal.summary.classifiedDuration)
        }
        let duration = (session.endedAt ?? session.date).timeIntervalSince(session.date)
        let snapshot = Snapshot(session)
        let backup = HeartRateBackup(samples: session.hrSamplePoints, summary: session.intensitySummary,
                                     coverage: session.hrCoverage)
        session.hrSamplePoints = proposal.observations
        session.hrCoverage = HeartRateCoverage.measure(proposal.observations, source: .repairedHealthKit, at: now)
        session.intensitySummary = proposal.summary
        session.hasManualCardioMinutesOverride = false
        session.hrBackup = backup
        session.updatedAt = max(now, snapshot.updatedAt.addingTimeInterval(0.001))
        do { try save() } catch {
            snapshot.restore(to: session)
            return .accessError(.query)
        }
        return .repaired(classifiedMinutes: Int((proposal.summary.classifiedDuration / 60).rounded()),
                         totalMinutes: Int((duration / 60).rounded()))
    }

    /// Reverts the most recent repair. Returns false when there is nothing to restore
    /// or the save failed (in which case the repaired state and its backup are kept).
    @MainActor
    @discardableResult
    public static func restorePrevious(_ session: WorkoutSession, save: () throws -> Void = {}) -> Bool {
        guard let backup = session.hrBackup else { return false }
        let snapshot = Snapshot(session)
        session.hrSamplePoints = backup.samples
        session.intensitySummary = backup.summary
        session.hrCoverage = backup.coverage
        session.hrBackup = nil
        session.updatedAt = max(Date(), snapshot.updatedAt.addingTimeInterval(0.001))
        do { try save() } catch {
            snapshot.restore(to: session)
            return false
        }
        return true
    }
}
