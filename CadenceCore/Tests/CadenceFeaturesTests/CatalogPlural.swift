import Foundation

/// Whether `swift test` compiles `Localizable.xcstrings` depends on the
/// toolchain: some copy it raw, so plural keys render their English source form
/// ("1 days"); others (and Xcode) compile it and pick the `one` variation. Tests accept
/// either rendering and separately pin the catalog's English plural text.
enum CatalogPlural {
    /// The catalog's English `one`/`other` text for `key`, with `%lld` filled.
    static func english(_ key: String, _ count: Int) -> String? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadenceFeatures/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any],
              let entry = strings[key] as? [String: Any],
              let en = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any],
              let plural = (en["variations"] as? [String: Any])?["plural"] as? [String: Any],
              let form = plural[count == 1 ? "one" : "other"] as? [String: Any],
              let value = (form["stringUnit"] as? [String: Any])?["value"] as? String
        else { return nil }
        return value.replacingOccurrences(of: "%lld", with: String(count))
    }

    /// Both renderings a plural key can produce for `count`.
    static func renderings(_ key: String, _ count: Int) -> Set<String> {
        var out: Set<String> = [key.replacingOccurrences(of: "%lld", with: String(count))]
        if let english = english(key, count) { out.insert(english) }
        return out
    }
}
