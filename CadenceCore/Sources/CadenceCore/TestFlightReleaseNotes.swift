import Foundation

/// Builds the TestFlight "What to Test" text for one exact build. Pure and
/// Foundation-only so CI tooling and `swift test` share the same logic.
public struct TestFlightReleaseNotes: Sendable, Equatable {
    /// App Store Connect limits localized What to Test to 4000 characters.
    public static let characterLimit = 4000
    public static let maxTitleLength = 90
    public static let maxInstructionLength = 160

    public enum ChangeKind: String, Sendable, Equatable {
        case userFacing, infrastructure
    }

    public struct Change: Sendable, Equatable {
        public let issueNumber: Int
        public let title: String
        public let kind: ChangeKind
        /// Observable behavior to verify, taken from the merged change.
        /// Nil means none was documented; none is invented.
        public let testInstruction: String?

        public init(issueNumber: Int, title: String, kind: ChangeKind = .userFacing,
                    testInstruction: String? = nil) {
            self.issueNumber = issueNumber
            self.title = title
            self.kind = kind
            self.testInstruction = testInstruction
        }
    }

    public let marketingVersion: String
    public let buildNumber: Int
    /// Commit actually archived, never the current tip of `main`.
    public let commitSHA: String
    public let repository: String
    public let changes: [Change]

    public init(marketingVersion: String, buildNumber: Int, commitSHA: String,
                repository: String, changes: [Change]) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.commitSHA = commitSHA
        self.repository = repository
        self.changes = changes
    }

    /// One entry per issue number (first wins), ascending by number.
    public var uniqueChanges: [Change] {
        var seen = Set<Int>()
        return changes.filter { seen.insert($0.issueNumber).inserted }
            .sorted { $0.issueNumber < $1.issueNumber }
    }

    public var shortSHA: String { String(commitSHA.lowercased().prefix(12)) }

    public func render(limit: Int = TestFlightReleaseNotes.characterLimit) -> String {
        let changes = uniqueChanges
        let header = [
            "Cadence \(marketingVersion) (\(buildNumber))",
            "Source: \(shortSHA)",
            "GitHub: \(repository)"
        ]
        var included: [String] = []
        var tests: [String] = []
        if changes.isEmpty {
            included.append("- No new GitHub issues since the previous build.")
        }
        for change in changes {
            included.append("- #\(change.issueNumber) — \(Self.clip(change.title, Self.maxTitleLength))")
        }
        for change in changes where change.kind == .userFacing {
            if let text = change.testInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                tests.append("- #\(change.issueNumber): \(Self.clip(text, Self.maxInstructionLength))")
            }
        }
        let infra = changes.filter { $0.kind == .infrastructure }.map { "#\($0.issueNumber)" }
        if !infra.isEmpty {
            tests.append("- Infrastructure only (\(infra.joined(separator: ", "))): no user-visible testing needed.")
        }
        if tests.isEmpty, !changes.isEmpty, infra.count != changes.count {
            tests.append("- No specific steps documented; smoke-test the included changes.")
        }

        // Priority: header, issue numbers, then testing steps, dropped from the end.
        var out = header.joined(separator: "\n")
        var includedLines = included
        var testLines = tests
        func build() -> String {
            var text = out + "\n\nIncluded changes\n" + includedLines.joined(separator: "\n")
            if !testLines.isEmpty { text += "\n\nWhat to test\n" + testLines.joined(separator: "\n") }
            return text
        }
        while build().count > limit, !testLines.isEmpty { testLines.removeLast() }
        while build().count > limit, includedLines.count > 1 {
            includedLines.removeLast()
            let omitted = changes.count - includedLines.count + 1
            includedLines[includedLines.count - 1] = "- …and \(omitted) more (see GitHub)"
        }
        out = build()
        return String(out.prefix(limit))
    }

    static func clip(_ text: String, _ max: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > max else { return flat }
        return String(flat.prefix(max - 1)) + "…"
    }
}

/// Decides whether a retry/late job may write notes to a beta build.
public enum TestFlightNotesPublication: Equatable, Sendable {
    case publish
    case skipAlreadyCurrent
    case skipWrongBuild
    case skipNewerBuildExists

    public struct Target: Sendable, Equatable {
        public let appID: String
        public let platform: String
        public let version: String
        public let build: Int
        public let existingNotes: String?
        public init(appID: String, platform: String, version: String, build: Int,
                    existingNotes: String?) {
            self.appID = appID; self.platform = platform; self.version = version
            self.build = build; self.existingNotes = existingNotes
        }
    }

    public static func decide(target: Target, expectedAppID: String, expectedPlatform: String,
                              notes: TestFlightReleaseNotes, newestKnownBuild: Int)
        -> TestFlightNotesPublication {
        guard target.appID == expectedAppID, target.platform == expectedPlatform,
              target.version == notes.marketingVersion, target.build == notes.buildNumber
        else { return .skipWrongBuild }
        // Only ever touches the exact build, so newer builds are never
        // overwritten; this flag lets callers log the situation.
        if newestKnownBuild > notes.buildNumber, target.build != notes.buildNumber {
            return .skipNewerBuildExists
        }
        if target.existingNotes == notes.render() { return .skipAlreadyCurrent }
        return .publish
    }
}
