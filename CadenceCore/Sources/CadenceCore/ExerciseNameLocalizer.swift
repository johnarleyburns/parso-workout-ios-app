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
        let language = locale.identifier
        let languageCode = locale.language.languageCode.map(\.identifier)
            ?? language.split(separator: "-").first.map(String.init)
            ?? language
        return names[key]?[language]
            ?? names[key]?[languageCode]
            ?? canonicalName
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
