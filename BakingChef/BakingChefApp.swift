import SwiftUI

@main
struct BakingChefApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.requestNotificationPermission() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appBecameActive() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be set before launch finishes so notification actions ("Erledigt") are delivered.
        NotificationManager.shared.configure()
        return true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Recipe] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let session = model.session {
                    SessionView(session: session)
                } else {
                    RecipeListView()
                }
            }
            // Registered at the root so it stays valid while the root content switches.
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        }
        // Starting (or ending) a session swaps the root view; pop the recipe detail
        // so the user lands directly on the running session.
        .onChange(of: model.session?.id) { _, _ in path.removeAll() }
    }
}
