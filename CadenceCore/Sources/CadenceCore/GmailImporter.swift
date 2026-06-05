import Foundation

// MARK: - Parsed value types (FR-6.1)

/// A session parsed from the legacy Gmail-draft strength log.
public struct ParsedSession: Equatable, Sendable {
    public var title: String
    public var date: Date?
    public var exercises: [ParsedExercise]
    public init(title: String, date: Date?, exercises: [ParsedExercise]) {
        self.title = title; self.date = date; self.exercises = exercises
    }
}

public struct ParsedExercise: Equatable, Sendable {
    public var name: String
    public var category: ExerciseCategory?
    /// One entry per set, in order (weight in the unit declared, see `unit`).
    public var sets: [ParsedSet]
    public init(name: String, category: ExerciseCategory? = nil, sets: [ParsedSet]) {
        self.name = name; self.category = category; self.sets = sets
    }
}

public struct ParsedSet: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int
    public init(weightKg: Double, reps: Int) { self.weightKg = weightKg; self.reps = reps }
}

/// A line the parser could not interpret (UC-7 alternate 2a).
public struct ParseIssue: Equatable, Sendable {
    public var lineNumber: Int
    public var text: String
    public var reason: String
    public init(lineNumber: Int, text: String, reason: String) {
        self.lineNumber = lineNumber; self.text = text; self.reason = reason
    }
}

public struct ImportResult: Equatable, Sendable {
    public var sessions: [ParsedSession]
    public var issues: [ParseIssue]
    public init(sessions: [ParsedSession], issues: [ParseIssue]) {
        self.sessions = sessions; self.issues = issues
    }
    public var totalSets: Int {
        sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
    }
}

/// Parses a hand-kept strength log of the form Cadence's author used in a Gmail
/// draft. The grammar is intentionally forgiving (FR-6.1, UC-7):
///
///   # Push Day            2024-01-15       ← header: title + optional date
///   Bench Press 100kg 3x5                  ← N sets × R reps
///   Overhead Press 60 5,5,4                ← explicit per-set reps
///   Incline DB Press 30kg 8x3   PR         ← trailing PR/last-time markers ignored
///
/// Headers may also be a bare date line or a "Category:" line. Weight defaults
/// to kg; a `lb`/`lbs` suffix converts. PR/last-time markers are recomputed on
/// import, so they're parsed-and-ignored, never trusted.
public enum GmailImporter {

    public static func parse(_ text: String,
                             defaultUnit: MeasurementUnitPreference = .kilograms,
                             referenceDate: Date = Date()) -> ImportResult {
        var sessions: [ParsedSession] = []
        var issues: [ParseIssue] = []
        var current: ParsedSession?

        func flush() {
            if let c = current, !c.exercises.isEmpty { sessions.append(c) }
            current = nil
        }

        let lines = text.components(separatedBy: .newlines)
        for (idx, raw) in lines.enumerated() {
            let lineNumber = idx + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Header? (# prefix, "Category:" prefix, or a pure date line)
            if let header = parseHeader(line, referenceDate: referenceDate) {
                flush()
                current = ParsedSession(title: header.title, date: header.date, exercises: [])
                continue
            }

            // Exercise line.
            switch parseExerciseLine(line, defaultUnit: defaultUnit) {
            case .success(let ex):
                if current == nil {
                    current = ParsedSession(title: "Imported Workout", date: nil, exercises: [])
                }
                current?.exercises.append(ex)
            case .failure(let reason):
                issues.append(ParseIssue(lineNumber: lineNumber, text: line, reason: reason))
            }
        }
        flush()
        return ImportResult(sessions: sessions, issues: issues)
    }

    // MARK: Header parsing

    struct Header { var title: String; var date: Date? }

    static func parseHeader(_ line: String, referenceDate: Date) -> Header? {
        var working = line
        var isExplicitHeader = false

        if working.hasPrefix("#") {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespaces)
            isExplicitHeader = true
        } else if let colon = working.range(of: ":"), working[..<colon.lowerBound]
            .lowercased().contains("category") {
            working = String(working[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            isExplicitHeader = true
        }

        // Pull a trailing/embedded date out, if present.
        let (date, remainder) = extractDate(from: working, referenceDate: referenceDate)
        let title = remainder.trimmingCharacters(in: .whitespaces)

        // A bare date line counts as a header too.
        if !isExplicitHeader {
            if date != nil && title.isEmpty {
                return Header(title: "Imported Workout", date: date)
            }
            return nil
        }
        return Header(title: title.isEmpty ? "Imported Workout" : title, date: date)
    }

    /// Finds the first ISO-ish or US date in the string; returns it plus the
    /// string with the date removed.
    static func extractDate(from s: String, referenceDate: Date) -> (Date?, String) {
        let patterns = [
            "\\d{4}-\\d{1,2}-\\d{1,2}",   // 2024-01-15
            "\\d{1,2}/\\d{1,2}/\\d{2,4}"  // 1/15/24 or 01/15/2024
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            if let m = re.firstMatch(in: s, range: range), let r = Range(m.range, in: s) {
                let token = String(s[r])
                if let d = parseDateToken(token) {
                    var remainder = s
                    remainder.removeSubrange(r)
                    return (d, remainder)
                }
            }
        }
        return (nil, s)
    }

    static func parseDateToken(_ token: String) -> Date? {
        let formats = ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy"]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        for f in formats {
            fmt.dateFormat = f
            if let d = fmt.date(from: token) { return d }
        }
        return nil
    }

    // MARK: Exercise-line parsing

    enum LineParse { case success(ParsedExercise); case failure(String) }

    static func parseExerciseLine(_ line: String, defaultUnit: MeasurementUnitPreference) -> LineParse {
        // Strip PR / last-time markers (case-insensitive), they're noise. Use
        // word boundaries so "PR" never eats the "Pr" inside "Press".
        var working = line
        let markerPatterns = ["\\(pr\\)", "\\bpr\\b", "\\blast[- ]time\\b", "★", "\\*"]
        for pattern in markerPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(working.startIndex..., in: working)
                working = re.stringByReplacingMatches(in: working, range: range, withTemplate: " ")
            }
        }
        working = working.trimmingCharacters(in: .whitespaces)
        guard !working.isEmpty else { return .failure("empty after marker strip") }

        let tokens = working.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else {
            return .failure("expected '<name> <weight> <sets×reps>'")
        }

        // The last token is the rep/set spec; the token before it (or attached)
        // is the weight. The name is everything before the weight.
        // Find the weight token: the last token that looks like a number(+unit).
        var weightIndex: Int?
        for i in stride(from: tokens.count - 1, through: 0, by: -1) {
            if parseWeight(tokens[i], defaultUnit: defaultUnit) != nil {
                // ensure there's at least one token after it for reps OR the
                // weight token itself bundles reps (handled below)
                weightIndex = i
                break
            }
        }
        guard let wi = weightIndex, wi >= 1 else {
            return .failure("could not find a weight value")
        }

        guard let weightKg = parseWeight(tokens[wi], defaultUnit: defaultUnit) else {
            return .failure("invalid weight")
        }

        let repSpecTokens = tokens[(wi + 1)...]
        guard !repSpecTokens.isEmpty else { return .failure("missing sets×reps") }
        let repSpec = repSpecTokens.joined(separator: " ")
        guard let reps = parseSetsReps(repSpec) else {
            return .failure("could not parse sets×reps from '\(repSpec)'")
        }

        let name = tokens[0..<wi].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure("missing exercise name") }

        let sets = reps.map { ParsedSet(weightKg: weightKg, reps: $0) }
        return .success(ParsedExercise(name: name, category: nil, sets: sets))
    }

    /// Parses "100", "100kg", "225lb", "225lbs" into canonical kg.
    static func parseWeight(_ token: String, defaultUnit: MeasurementUnitPreference) -> Double? {
        let lower = token.lowercased()
        var unit = defaultUnit
        var numberPart = lower
        if lower.hasSuffix("kg") { unit = .kilograms; numberPart = String(lower.dropLast(2)) }
        else if lower.hasSuffix("lbs") { unit = .pounds; numberPart = String(lower.dropLast(3)) }
        else if lower.hasSuffix("lb") { unit = .pounds; numberPart = String(lower.dropLast(2)) }
        guard let value = Double(numberPart), value >= 0 else { return nil }
        return WorkoutMath.canonical(value, from: unit)
    }

    /// Parses a sets×reps spec into an array of per-set rep counts.
    ///   "3x5"   → [5, 5, 5]
    ///   "5x1"   → [1]            (5 sets of 1)
    ///   "5,5,4" → [5, 5, 4]
    ///   "8"     → [8]            (single set)
    static func parseSetsReps(_ spec: String) -> [Int]? {
        let s = spec.replacingOccurrences(of: " ", with: "")
                    .lowercased()
        if s.contains(",") {
            let parts = s.split(separator: ",").map { Int($0) }
            guard !parts.contains(nil), let reps = (parts as? [Int]), reps.allSatisfy({ $0 > 0 }) else { return nil }
            return reps
        }
        if s.contains("x") {
            let parts = s.split(separator: "x")
            guard parts.count == 2, let sets = Int(parts[0]), let reps = Int(parts[1]),
                  sets > 0, reps > 0 else { return nil }
            return Array(repeating: reps, count: sets)
        }
        if let single = Int(s), single > 0 { return [single] }
        return nil
    }
}
