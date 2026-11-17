import Foundation
import Observation
import UserNotifications

/// Central state of the iPhone app. Every change to the session is persisted and
/// pushed to notifications, the Live Activity and the Watch.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var recipes: [Recipe] = []
    private(set) var customIDs: Set<String> = []
    private(set) var bundledIDs: Set<String> = []
    private(set) var session: BakeSession?
    var importError: String?

    @ObservationIgnored private let store = RecipeStore()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let connectivity = PhoneConnectivity()
    private static let sessionKey = "activeSession"

    private init() {
        reloadRecipes()
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey) {
            session = try? JSONDecoder().decode(BakeSession.self, from: data)
        }
        connectivity.activate()
    }

    // MARK: Recipes

    func reloadRecipes() {
        let contents = store.loadAll()
        recipes = contents.recipes
        customIDs = contents.customIDs
        bundledIDs = contents.bundledIDs
    }

    /// Imported, created or edited in the app (can be deleted / reset).
    func isCustom(_ recipe: Recipe) -> Bool { customIDs.contains(recipe.id) }
    /// Ships with the app (deleting the own version restores the original).
    func isBundled(_ recipe: Recipe) -> Bool { bundledIDs.contains(recipe.id) }

    func recipe(id: String) -> Recipe? { recipes.first { $0.id == id } }

    /// Saves a recipe from the editor. New recipes get a unique ID derived from the name.
    @discardableResult
    func save(_ recipe: Recipe, isNew: Bool) throws -> Recipe {
        var recipe = recipe
        if isNew {
            let base = Recipe.slug(recipe.nameText.text(for: "en"))
            let stem = base.isEmpty ? "recipe" : base
            var id = stem, n = 2
            let taken = Set(recipes.map(\.id)).union(bundledIDs)
            while taken.contains(id) { id = "\(stem)-\(n)"; n += 1 }
            recipe.id = id
        }
        try store.save(recipe)
        reloadRecipes()
        return recipe
    }

    func importRecipes(from result: Result<[URL], Error>) {
        do {
            var count = 0
            for url in try result.get() {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                do {
                    for recipe in try RecipeParser.decode(data) {
                        try store.save(recipe)
                        count += 1
                    }
                } catch {
                    throw ImportError(message: "\(url.lastPathComponent): \(RecipeParser.describe(error))")
                }
            }
            if count == 0 { importError = String(localized: "No recipes found.") }
        } catch let error as ImportError {
            importError = error.message
        } catch {
            importError = error.localizedDescription
        }
        reloadRecipes()
    }

    /// Deletes an own recipe; for an edited bundled recipe this restores the original.
    func deleteCustom(_ recipe: Recipe) {
        store.delete(id: recipe.id)
        reloadRecipes()
    }

    private struct ImportError: Error { var message: String }

    // MARK: Session

    func start(_ recipe: Recipe, multiplier: Double) {
        setSession(BakeSession(recipe: recipe, multiplier: multiplier))
    }

    func endSession() { setSession(nil) }

    func apply(_ action: SessionAction) {
        mutate { $0.apply(action) }
    }

    func mutate(_ change: (inout BakeSession) -> Void) {
        guard var s = session else { return }
        change(&s)
        setSession(s)
    }

    /// Action coming from the Watch or a notification; ignored if it belongs to an old session.
    func handleRemote(_ action: SessionAction, sessionID: UUID) {
        guard session?.id == sessionID else { return }
        apply(action)
    }

    private func setSession(_ newValue: BakeSession?) {
        session = newValue
        if let newValue, let data = try? JSONEncoder().encode(newValue) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
        syncSideEffects()
    }

    private func syncSideEffects() {
        NotificationManager.shared.reschedule(for: session)
        liveActivity.sync(session)
        connectivity.send(session)
    }

    func pushToWatch() { connectivity.send(session) }

    /// Waits until the Live Activity has received the latest state (call before the app gets suspended).
    func flushLiveActivity() async { await liveActivity.flush() }

    func appBecameActive() { syncSideEffects() }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
