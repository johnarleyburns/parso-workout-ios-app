import Foundation

/// Localizes DB++ exercise names without changing the canonical stored name or
/// search key. DB++ supplies translated catalog names at their recorded review
/// status; the sidecar retains app-specific names, with English fallback.
public struct ExerciseNameLocalizer: Sendable {
    public static let launchLocales = ["en", "en-GB", "de", "es", "fr", "nl", "pt-BR", "zh-Hans", "zh-Hant"]

    public static let shared = ExerciseNameLocalizer()

    private let aliases: [String: [String: [String]]]
    private let names: [String: [String: String]]

    public init(data: Data? = nil) {
        let sidecar = (try? JSONDecoder().decode([String: [String: String]].self,
            from: data ?? Self.sidecarData())) ?? [:]
        guard data == nil else { names = sidecar; aliases = [:]; return }
        var merged = sidecar
        var searchAliases: [String: [String: [String]]] = [:]
        for exercise in TrainingEngineBridge.localizedExerciseNames {
            let keys = Set([exercise.canonical] + exercise.englishAliases + [exercise.englishName]).sorted()
            for name in keys {
                let key = name.normalizedExerciseName
                for (locale, translation) in exercise.translations {
                    // App-specific curated translations take precedence over
                    // the generic catalog spelling for the same canonical name.
                    if merged[key]?[locale] == nil {
                        merged[key, default: [:]][locale] = translation.preferred
                    }
                    searchAliases[key, default: [:]][locale] =
                        translation.aliases
                }
            }
        }
        names = merged
        aliases = searchAliases
    }

    public func localizedName(for canonicalName: String, locale: Locale = .current) -> String {
        let key = canonicalName.normalizedExerciseName
        guard let translations = names[key] else { return canonicalName }
        return Self.lookupKeys(for: locale).lazy.compactMap { translations[$0] }.first ?? canonicalName
    }

    /// Search includes the requested translation and the canonical English
    /// aliases, without changing the stored exercise identity.
    public func searchTerms(for canonicalName: String, locale: Locale = .current) -> [String] {
        let key = canonicalName.normalizedExerciseName
        let locales = Self.lookupKeys(for: locale)
        return [localizedName(for: canonicalName, locale: locale)]
            + locales.flatMap { aliases[key]?[$0] ?? [] }
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
        keys.append("en")
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

public extension String {
    /// Presentation only: canonical names remain unchanged in persistence,
    /// matching, exports and coaching identities.
    var localizedExerciseName: String {
        ExerciseNameLocalizer.shared.localizedName(for: self)
    }
}
