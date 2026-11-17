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

    // MARK: Editing

    /// Languages offered in the recipe editor (plus any other language found in a recipe).
    static let editorLanguages = ["en", "de"]

    /// Language codes used in this text (without the plain `""` entry).
    var languages: Set<String> { Set(values.keys.filter { !$0.isEmpty }) }

    /// True when `language` has its own text or the text is a plain string (all languages).
    /// False means the app shows the text of another language as fallback.
    func isTranslated(to language: String) -> Bool {
        values[language] != nil || values[""] != nil
            || values.keys.contains { $0.lowercased().hasPrefix(language.lowercased() + "-") }
    }

    /// Changes the text for one language only. A plain string stays the text of the other languages.
    mutating func setText(_ newValue: String, for language: String) {
        values[language] = newValue
    }

    /// True when the text is empty in every language.
    var isEmpty: Bool {
        values.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Cleans up after editing:
    /// - empty entries are removed (that language falls back to another one)
    /// - a plain string next to translations becomes the text of the languages without their own text
    /// - the same text in all `languages` becomes a plain string
    func normalized(for languages: [String]) -> LocalizedText {
        var v = values.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let plain = v[""], v.count > 1 {
            v[""] = nil
            for language in languages where v[language] == nil { v[language] = plain }
        }
        if v.count > 1, Set(v.values).count == 1, Set(languages).isSubset(of: v.keys) {
            v = ["": v.values.first!]
        }
        return LocalizedText(v)
    }

    // MARK: Coding

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
