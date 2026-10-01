import Foundation

/// Localizes DB++ exercise names without changing the canonical stored name or
/// search key. The sidecar is deliberately additive: a new DB++ exercise falls
/// back to its canonical English label until a translation is reviewed.
public struct ExerciseNameLocalizer: Sendable {
    public static let launchLocales = ["en", "en-GB", "de", "es", "fr", "nl", "pt-BR", "zh-Hans", "zh-Hant"]

    private let names: [String: [String: String]]

    public init(data: Data? = nil) {
        let data = data ?? Self.sidecarData()
        names = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }

    public func localizedName(for canonicalName: String, locale: Locale = .current) -> String {
        let key = canonicalName.normalizedExerciseName
        guard let translations = names[key] else { return canonicalName }
        return Self.lookupKeys(for: locale).lazy.compactMap { translations[$0] }.first ?? canonicalName
    }

    /// Sidecar keys use BCP-47 tags ("pt-BR", "zh-Hant"), while `Locale.identifier`
    /// is ICU-style ("pt_BR", "zh-Hant_TW"), so try script and region forms too.
    static func lookupKeys(for locale: Locale) -> [String] {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let language = locale.language.languageCode?.identifier
            ?? identifier.split(separator: "-").first.map(String.init) ?? identifier
        var keys = [identifier]
        if let script = locale.language.script?.identifier { keys.append("\(language)-\(script)") }
        if let region = locale.region?.identifier { keys.append("\(language)-\(region)") }
        if language == "zh", locale.language.script == nil {
            // zh-TW / zh-HK default to Traditional, other Chinese regions to Simplified.
            let region = locale.region?.identifier
            keys.append(region == "TW" || region == "HK" || region == "MO" ? "zh-Hant" : "zh-Hans")
        }
        keys.append(language)
        return keys
    }

    public var localizedExerciseCount: Int { names.count }

    private static func sidecarData() -> Data {
        guard let url = Bundle.module.url(forResource: "exercise-names.i18n", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }
}

private extension String {
    var normalizedExerciseName: String {
        lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
