import Foundation

/// The vendored free-exercise-db++ document (Unlicense — see `CREDITS.md`).
///
/// DB++ is an evidence-audited annotation layer over `yuhonas/free-exercise-db`:
/// every upstream record is preserved verbatim under `source`, and DB++ adds
/// movement classification, direct/indirect/stabilizer muscle roles, volume
/// eligibility, and per-pattern literature references with PMIDs and DOIs.
///
/// Decoded once, lazily, from `Bundle.module`. There is no runtime network path
/// (NFR-3) — `scripts/check-no-network.sh` enforces it.
public enum ExerciseDatabase {

    // MARK: Document

    public struct Document: Decodable, Sendable {
        public let metadata: Metadata
        public let exercises: [String: Record]
    }

    public struct Metadata: Decodable, Sendable {
        public let schemaVersion: String
        public let converterVersion: String
        public let generatedAt: String
        public let upstream: Upstream
        public let setCredits: SetCredits
        public let setCreditEvidence: SetCreditEvidence
        public let evidence: Evidence
        public let muscleOntology: [String]
        public let sourceExerciseCount: Int
        public let outputExerciseCount: Int
        public let completeness: String
    }

    public struct Upstream: Decodable, Sendable {
        public let project: String
        public let sourceUrl: String
        public let sha256: String?
    }

    /// The one set-credit convention DB++ publishes. These are analytical credits
    /// for volume accounting, not a claim that fatigue or hypertrophy is linear.
    public struct SetCredits: Decodable, Sendable {
        public let direct: Double
        public let indirect: Double
        public let stabilizer: Double

        public init(direct: Double, indirect: Double, stabilizer: Double) {
            self.direct = direct
            self.indirect = indirect
            self.stabilizer = stabilizer
        }
    }

    public struct SetCreditEvidence: Decodable, Sendable {
        public let status: String
        public let interpretation: String
        public let references: [String]
    }

    public struct Evidence: Decodable, Sendable {
        public let references: [String: Reference]
        public let patterns: [String: PatternEvidence]
    }

    public struct Reference: Decodable, Sendable {
        public let title: String
        public let type: String
        public let pmid: String?
        public let doi: String?
        public let url: String
    }

    public struct PatternEvidence: Decodable, Sendable {
        public let status: String
        public let summary: String
        public let references: [String]
    }

    // MARK: Record

    public struct Record: Decodable, Sendable {
        public let exerciseId: String
        public let classification: Classification
        public let annotation: Annotation
        public let source: Source
    }

    public struct Classification: Decodable, Sendable {
        public let trainingTypes: [String]
        public let modalities: [String]
        public let sportContexts: [String]
        public let competitionMovements: [String]
    }

    public struct Annotation: Decodable, Sendable {
        public let patterns: [String]
        public let direct: [String]
        public let indirect: [String]
        public let stabilizers: [String]
        public let volumeEligible: Bool
        public let confidence: String
        public let reviewReasons: [String]
        public let evidenceRefs: [String]
    }

    /// The upstream free-exercise-db record, preserved verbatim by DB++.
    public struct Source: Decodable, Sendable {
        public let id: String
        public let name: String
        public let force: String?
        public let level: String?
        public let mechanic: String?
        public let equipment: String?
        public let primaryMuscles: [String]
        public let secondaryMuscles: [String]
        public let instructions: [String]
        public let category: String
        public let images: [String]
    }

    // MARK: Bundled data

    /// The decoded document, or `nil` if the resource is missing or corrupt —
    /// callers degrade to the curated catalog rather than trapping.
    public static let document: Document? = {
        guard let url = Bundle.module.url(forResource: "free-exercise-db-plusplus",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Document.self, from: data)
        else { return nil }
        return decoded
    }()

    /// Every record, ordered by `exerciseId`. `exercises` is a JSON *object*, so
    /// decoding loses file order; sorting by id restores the determinism the
    /// catalog merge and every fixture depend on.
    public static let records: [Record] = {
        guard let document else { return [] }
        return document.exercises.values.sorted { $0.exerciseId < $1.exerciseId }
    }()

    public static let recordsByID: [String: Record] = {
        Dictionary(records.map { ($0.exerciseId, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    /// Lookup by lowercased upstream name, for attaching annotations to our
    /// curated entries.
    public static let recordsByName: [String: Record] = {
        Dictionary(records.map { ($0.source.name.lowercased(), $0) },
                   uniquingKeysWith: { a, _ in a })
    }()

    /// Set credits read from the document rather than hard-coded, so a data
    /// refresh that changed the model cannot silently disagree with our
    /// arithmetic. Falls back to the published 1.0 / 0.5 / 0.0.
    public static var setCredits: SetCredits {
        metadata?.setCredits ?? SetCredits(direct: 1, indirect: 0.5, stabilizer: 0)
    }

    public static var metadata: Metadata? { document?.metadata }

    /// The 20 canonical muscle strings DB++ annotates against.
    public static var muscleOntology: [String] { metadata?.muscleOntology ?? [] }
}
