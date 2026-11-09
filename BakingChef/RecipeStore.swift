import Foundation

/// Bundled recipes (Recipes/*.json in the app) plus imported ones (Documents/Recipes).
/// An imported recipe with the same `id` replaces the bundled one.
struct RecipeStore {
    private var importDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recipes", isDirectory: true)
    }

    func loadAll() -> (recipes: [Recipe], importedIDs: Set<String>) {
        var byID: [String: Recipe] = [:]
        let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Recipes") ?? []
        for recipe in bundled.flatMap(load) { byID[recipe.id] = recipe }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: importDirectory, includingPropertiesForKeys: nil)) ?? []
        let imported = files.filter { $0.pathExtension == "json" }.flatMap(load)
        for recipe in imported { byID[recipe.id] = recipe }

        let sorted = byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return (sorted, Set(imported.map(\.id)))
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
