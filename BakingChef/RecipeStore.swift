import Foundation

/// Bundled recipes (Recipes/*.json in the app) plus own ones (Documents/Recipes: imported,
/// created or edited in the app). An own recipe with the same `id` replaces the bundled one.
struct RecipeStore {
    struct Contents {
        var recipes: [Recipe]
        /// IDs of the own recipes (imported, created or edited).
        var customIDs: Set<String>
        /// IDs of the recipes that ship with the app.
        var bundledIDs: Set<String>
    }

    private var importDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recipes", isDirectory: true)
    }

    func loadAll() -> Contents {
        var byID: [String: Recipe] = [:]
        let bundledFiles = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Recipes") ?? []
        let bundled = bundledFiles.flatMap(load)
        for recipe in bundled { byID[recipe.id] = recipe }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: importDirectory, includingPropertiesForKeys: nil)) ?? []
        let imported = files.filter { $0.pathExtension == "json" }.flatMap(load)
        for recipe in imported { byID[recipe.id] = recipe }

        let sorted = byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return Contents(recipes: sorted, customIDs: Set(imported.map(\.id)), bundledIDs: Set(bundled.map(\.id)))
    }

    func save(_ recipe: Recipe) throws {
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        try RecipeParser.encode(recipe).write(to: fileURL(for: recipe.id), options: .atomic)
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: String) -> URL {
        importDirectory.appendingPathComponent(Recipe.slug(id)).appendingPathExtension("json")
    }

    private func load(_ url: URL) -> [Recipe] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? RecipeParser.decode(data)) ?? []
    }
}
