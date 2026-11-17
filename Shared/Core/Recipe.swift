import Foundation

// MARK: - Durations ("HH:MM" in JSON)

enum DurationCoding {
    /// "04:00" → 240, "00:30" → 30
    static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h >= 0, (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    static func string(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Accepts "HH:MM" or a plain number of minutes.
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Int? {
        guard c.contains(key) else { return nil }
        if try c.decodeNil(forKey: key) { return nil }
        if let minutes = try? c.decode(Int.self, forKey: key) { return minutes }
        let text = try c.decode(String.self, forKey: key)
        guard let minutes = parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: c,
                debugDescription: String(localized: "Invalid duration “\(text)” – expected e.g. \"01:30\""))
        }
        return minutes
    }
}

// MARK: - Model

struct Ingredient: Codable, Hashable {
    var nameText: LocalizedText
    var amount: Double
    /// Optional upper bound for ranges like "400–450 g".
    var amountMax: Double?
    var unitText: LocalizedText

    var name: String { nameText.text }
    var unit: String { unitText.text }

    init(name: LocalizedText, amount: Double, amountMax: Double? = nil, unit: LocalizedText = "g") {
        nameText = name
        self.amount = amount
        self.amountMax = amountMax
        unitText = unit
    }

    enum CodingKeys: String, CodingKey { case name, amount, amountMax, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameText = try c.decode(LocalizedText.self, forKey: .name)
        amount = try c.decode(Double.self, forKey: .amount)
        amountMax = try c.decodeIfPresent(Double.self, forKey: .amountMax)
        unitText = try c.decodeIfPresent(LocalizedText.self, forKey: .unit) ?? "g"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nameText, forKey: .name)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(amountMax, forKey: .amountMax)
        try c.encode(unitText, forKey: .unit)
    }

    /// "60 g" or "600–675 g"
    func amountText(multiplier m: Double) -> String {
        let unitPart = unit.isEmpty ? "" : " \(unit)"
        if let max = amountMax {
            return "\(Format.amount(amount * m))–\(Format.amount(max * m))\(unitPart)"
        }
        return "\(Format.amount(amount * m))\(unitPart)"
    }

    /// "60 g Starter"
    func text(multiplier m: Double) -> String { "\(amountText(multiplier: m)) \(name)" }
}

/// An extra notification some time before a step is due, e.g. "Preheat the oven".
struct StepReminder: Codable, Hashable {
    var minutesBefore: Int
    var localizedText: LocalizedText

    var text: String { localizedText.text }

    init(minutesBefore: Int, text: LocalizedText) {
        self.minutesBefore = minutesBefore
        localizedText = text
    }

    enum CodingKeys: String, CodingKey { case before, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutesBefore = try DurationCoding.decode(c, .before) ?? 0
        localizedText = try c.decode(LocalizedText.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(DurationCoding.string(minutesBefore), forKey: .before)
        try c.encode(localizedText, forKey: .text)
    }
}

struct RecipeStep: Codable, Hashable {
    var titleText: LocalizedText
    var noteText: LocalizedText?
    var ingredients: [Ingredient]
    /// Expected time to do the step itself (mixing, folding, …). Only used for the forecast.
    var workMinutes: Int
    /// Waiting time after this step is checked off until the next step (or until done).
    var waitMinutes: Int
    var reminder: StepReminder?

    var title: String { titleText.text }
    var note: String? { noteText?.text }

    init(title: LocalizedText, note: LocalizedText? = nil, ingredients: [Ingredient] = [],
         workMinutes: Int = 0, waitMinutes: Int = 0, reminder: StepReminder? = nil) {
        titleText = title
        noteText = note
        self.ingredients = ingredients
        self.workMinutes = workMinutes
        self.waitMinutes = waitMinutes
        self.reminder = reminder
    }

    enum CodingKeys: String, CodingKey { case title, note, ingredients, work, wait, reminder }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleText = try c.decode(LocalizedText.self, forKey: .title)
        noteText = try c.decodeIfPresent(LocalizedText.self, forKey: .note)
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        workMinutes = try DurationCoding.decode(c, .work) ?? 0
        waitMinutes = try DurationCoding.decode(c, .wait) ?? 0
        reminder = try c.decodeIfPresent(StepReminder.self, forKey: .reminder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(titleText, forKey: .title)
        try c.encodeIfPresent(noteText, forKey: .note)
        if !ingredients.isEmpty { try c.encode(ingredients, forKey: .ingredients) }
        if workMinutes > 0 { try c.encode(DurationCoding.string(workMinutes), forKey: .work) }
        if waitMinutes > 0 { try c.encode(DurationCoding.string(waitMinutes), forKey: .wait) }
        try c.encodeIfPresent(reminder, forKey: .reminder)
    }

    func ingredientsText(multiplier m: Double) -> String {
        ingredients.map { $0.text(multiplier: m) }.joined(separator: ", ")
    }
}

struct Recipe: Codable, Hashable, Identifiable {
    var id: String
    var nameText: LocalizedText
    var summaryText: LocalizedText?
    var steps: [RecipeStep]

    var name: String { nameText.text }
    var summary: String? { summaryText?.text }

    init(id: String? = nil, name: LocalizedText, summary: LocalizedText? = nil, steps: [RecipeStep]) {
        self.id = id ?? Recipe.slug(name.text(for: "en"))
        nameText = name
        summaryText = summary
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, name, summary = "description", steps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameText = try c.decode(LocalizedText.self, forKey: .name)
        let rawID = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        // The ID must not depend on the device language.
        id = rawID.isEmpty ? Recipe.slug(nameText.text(for: "en")) : rawID
        summaryText = try c.decodeIfPresent(LocalizedText.self, forKey: .summary)
        steps = try c.decode([RecipeStep].self, forKey: .steps)
        guard !steps.isEmpty else {
            let name = nameText.text
            throw DecodingError.dataCorruptedError(
                forKey: .steps, in: c,
                debugDescription: String(localized: "Recipe “\(name)” has no steps"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nameText, forKey: .name)
        try c.encodeIfPresent(summaryText, forKey: .summary)
        try c.encode(steps, forKey: .steps)
    }

    /// Expected total duration: work + waiting time of all steps.
    var totalMinutes: Int { offsetMinutes(of: steps.count) }
    /// Recipes without any waiting time (e.g. "Feed the starter") have no timetable.
    var isScheduled: Bool { steps.contains { $0.waitMinutes > 0 } }

    /// Expected minutes from the start until step `index` begins (`steps.count` = done).
    func offsetMinutes(of index: Int) -> Int {
        steps.prefix(index).reduce(0) { $0 + $1.workMinutes + $1.waitMinutes }
    }

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let mapped = folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return mapped.split(separator: "-").joined(separator: "-")
    }
}

// MARK: - Parsing JSON files

enum RecipeParser {
    private struct Wrapper: Decodable { var recipes: [Recipe] }

    /// Accepts a single recipe object, an array of recipes, or `{ "recipes": [...] }`.
    static func decode(_ data: Data) throws -> [Recipe] {
        let decoder = JSONDecoder()
        let top = try JSONSerialization.jsonObject(with: data)
        if top is [Any] { return try decoder.decode([Recipe].self, from: data) }
        if let dict = top as? [String: Any], dict["recipes"] != nil {
            return try decoder.decode(Wrapper.self, from: data).recipes
        }
        return [try decoder.decode(Recipe.self, from: data)]
    }

    static func encode(_ recipe: Recipe) throws -> Data {
        try encoder.encode(recipe)
    }

    /// Several recipes as `{ "recipes": [...] }` (one file, readable by `decode`).
    static func encode(_ recipes: [Recipe]) throws -> Data {
        try encoder.encode(["recipes": recipes])
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Human readable, localized description of a decoding error.
    static func describe(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            let p = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return p.hasPrefix(".") ? String(p.dropFirst()) : (p.isEmpty ? String(localized: "(root)") : p)
        }
        guard let e = error as? DecodingError else {
            return (error as NSError).domain == NSCocoaErrorDomain
                ? String(localized: "The file is not valid JSON.") : error.localizedDescription
        }
        switch e {
        case .keyNotFound(let key, let ctx):
            return String(localized: "Field “\(key.stringValue)” is missing at \(path(ctx.codingPath)).")
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return String(localized: "Wrong value at \(path(ctx.codingPath)). \(ctx.debugDescription)")
        case .dataCorrupted(let ctx):
            return "\(ctx.debugDescription) (\(path(ctx.codingPath)))"
        @unknown default:
            return error.localizedDescription
        }
    }
}
