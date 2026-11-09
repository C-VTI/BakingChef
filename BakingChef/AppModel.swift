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
    private(set) var importedIDs: Set<String> = []
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
        let (all, imported) = store.loadAll()
        recipes = all
        importedIDs = imported
    }

    func isImported(_ recipe: Recipe) -> Bool { importedIDs.contains(recipe.id) }

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
            if count == 0 { importError = "Keine Rezepte gefunden." }
        } catch let error as ImportError {
            importError = error.message
        } catch {
            importError = error.localizedDescription
        }
        reloadRecipes()
    }

    func deleteImported(_ recipe: Recipe) {
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

    func appBecameActive() { syncSideEffects() }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
