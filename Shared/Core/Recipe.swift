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
                debugDescription: "Dauer „\(text)“ ungültig – erwartet z. B. \"01:30\"")
        }
        return minutes
    }
}

// MARK: - Model

struct Ingredient: Codable, Hashable {
    var name: String
    var amount: Double
    /// Optional upper bound for ranges like "400–450 g".
    var amountMax: Double?
    var unit: String

    init(name: String, amount: Double, amountMax: Double? = nil, unit: String = "g") {
        self.name = name
        self.amount = amount
        self.amountMax = amountMax
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey { case name, amount, amountMax, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        amount = try c.decode(Double.self, forKey: .amount)
        amountMax = try c.decodeIfPresent(Double.self, forKey: .amountMax)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "g"
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

/// An extra notification some time before a step is due, e.g. "Ofen vorheizen".
struct StepReminder: Codable, Hashable {
    var minutesBefore: Int
    var text: String

    init(minutesBefore: Int, text: String) {
        self.minutesBefore = minutesBefore
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case before, text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutesBefore = try DurationCoding.decode(c, .before) ?? 0
        text = try c.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(DurationCoding.string(minutesBefore), forKey: .before)
        try c.encode(text, forKey: .text)
    }
}

struct RecipeStep: Codable, Hashable {
    var title: String
    var note: String?
    var ingredients: [Ingredient]
    /// Expected time to do the step itself (mixing, folding, …). Only used for the forecast.
    var workMinutes: Int
    /// Waiting time after this step is checked off until the next step (or until done).
    var waitMinutes: Int
    var reminder: StepReminder?

    init(title: String, note: String? = nil, ingredients: [Ingredient] = [],
         workMinutes: Int = 0, waitMinutes: Int = 0, reminder: StepReminder? = nil) {
        self.title = title
        self.note = note
        self.ingredients = ingredients
        self.workMinutes = workMinutes
        self.waitMinutes = waitMinutes
        self.reminder = reminder
    }

    enum CodingKeys: String, CodingKey { case title, note, ingredients, work, wait, reminder }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        workMinutes = try DurationCoding.decode(c, .work) ?? 0
        waitMinutes = try DurationCoding.decode(c, .wait) ?? 0
        reminder = try c.decodeIfPresent(StepReminder.self, forKey: .reminder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
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
    var name: String
    var summary: String?
    var steps: [RecipeStep]

    init(id: String? = nil, name: String, summary: String? = nil, steps: [RecipeStep]) {
        self.id = id ?? Recipe.slug(name)
        self.name = name
        self.summary = summary
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, name, summary = "description", steps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        let rawID = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        id = rawID.isEmpty ? Recipe.slug(name) : rawID
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        steps = try c.decode([RecipeStep].self, forKey: .steps)
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps, in: c, debugDescription: "Rezept „\(name)“ hat keine Schritte")
        }
    }

    /// Expected total duration: work + waiting time of all steps.
    var totalMinutes: Int { offsetMinutes(of: steps.count) }
    /// Recipes without any waiting time (e.g. "Anstellgut auffrischen") have no timetable.
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(recipe)
    }

    /// Human readable (German) description of a decoding error.
    static func describe(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            let p = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return p.hasPrefix(".") ? String(p.dropFirst()) : (p.isEmpty ? "(Wurzel)" : p)
        }
        guard let e = error as? DecodingError else {
            return (error as NSError).domain == NSCocoaErrorDomain
                ? "Die Datei ist kein gültiges JSON." : error.localizedDescription
        }
        switch e {
        case .keyNotFound(let key, let ctx):
            return "Feld „\(key.stringValue)“ fehlt bei \(path(ctx.codingPath))."
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "Falscher Wert bei \(path(ctx.codingPath)). \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            return "\(ctx.debugDescription) (\(path(ctx.codingPath)))"
        @unknown default:
            return error.localizedDescription
        }
    }
}
