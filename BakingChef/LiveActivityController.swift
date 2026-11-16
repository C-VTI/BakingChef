import ActivityKit
import Foundation
import UIKit

extension BakeActivityAttributes.ContentState {
    init(session: BakeSession, now: Date = .now) {
        let detail: String
        if session.isPaused {
            detail = String(localized: "In the fridge")
        } else if let i = session.nextIndex {
            detail = String(localized: "Step \(i + 1)/\(session.steps.count)")
        } else {
            detail = String(localized: "In the oven")
        }
        self.init(title: session.nextTitle,
                  detail: detail,
                  dueAt: session.nextDue,
                  updatedAt: now,
                  pausedAt: session.pausedAt,
                  finishAt: session.finish(at: now))
    }
}

/// Starts, updates and ends the lock-screen / Dynamic Island countdown.
///
/// Updates are applied strictly in order (one after the other) and are protected by a
/// background task, so changes made while the app only runs briefly in the background
/// (Watch, "Done" on a notification) still reach the lock screen.
@MainActor
final class LiveActivityController {
    private var queue: Task<Void, Never>?

    func sync(_ session: BakeSession?) {
        let previous = queue
        let app = UIApplication.shared
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = app.beginBackgroundTask(withName: "LiveActivityUpdate") {
            app.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        queue = Task { @MainActor in
            await previous?.value
            await Self.apply(session)
            if bgTask != .invalid { app.endBackgroundTask(bgTask) }
        }
    }

    /// Waits until all pending updates have been handed to the system.
    func flush() async {
        await queue?.value
    }

    private static func apply(_ session: BakeSession?) async {
        let activities = Activity<BakeActivityAttributes>.activities

        guard let session, !session.isFinished(at: .now) else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let id = session.id.uuidString
        for activity in activities where activity.attributes.sessionID != id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let state = BakeActivityAttributes.ContentState(session: session)
        // Once the step is due the widget is re-rendered as stale and counts the overdue time up.
        let content = ActivityContent(state: state,
                                      staleDate: session.isPaused ? nil : state.dueAt)
        if let current = activities.first(where: {
            $0.attributes.sessionID == id && ($0.activityState == .active || $0.activityState == .stale)
        }) {
            await current.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // iOS ends Live Activities after ~8 h; a new one is started the next time the app is opened.
            _ = try? Activity.request(
                attributes: BakeActivityAttributes(sessionID: id, recipeName: session.recipe.name),
                content: content,
                pushType: nil)
        }
    }
}
