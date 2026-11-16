import Foundation

/// A text from a recipe file in one or more languages.
///
/// JSON accepts either a plain string (used for every language) or an object keyed by
/// language code, e.g. `{ "en": "Mix ingredients", "de": "Zutaten mischen" }`.
struct LocalizedText: Codable, Hashable, ExpressibleByStringLiteral {
    /// Language code → text. A plain string is stored under `""` (any language).
    var values: [String: String]

    init(_ text: String) { values = ["": text] }
    init(_ values: [String: String]) { self.values = values }
    init(stringLiteral value: String) { self.init(value) }

    /// Language the app is currently running in ("en", "de", …).
    static var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).language.languageCode?.identifier ?? code
    }

    /// Text in the app's language, falling back to a plain string, English, then any language.
    var text: String { text(for: Self.currentLanguage) }

    func text(for language: String) -> String {
        if let t = values[language] { return t }
        // "de-CH" in the file also matches "de".
        if let t = values.first(where: { $0.key.lowercased().hasPrefix(language.lowercased() + "-") })?.value {
            return t
        }
        return values[""] ?? values["en"] ?? values.sorted { $0.key < $1.key }.first?.value ?? ""
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let plain = try? c.decode(String.self) {
            values = ["": plain]
        } else {
            values = try c.decode([String: String].self)
            guard !values.isEmpty else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Empty text")
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if values.count == 1, let plain = values[""] {
            try c.encode(plain)
        } else {
            try c.encode(values)
        }
    }
}
