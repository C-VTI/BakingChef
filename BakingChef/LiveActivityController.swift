import ActivityKit
import Foundation

extension BakeActivityAttributes.ContentState {
    init(session: BakeSession, now: Date = .now) {
        let detail: String
        if session.isPaused {
            detail = "Pausiert"
        } else if let i = session.nextIndex {
            detail = "Schritt \(i + 1)/\(session.steps.count)"
        } else {
            detail = "Im Ofen"
        }
        self.init(title: session.nextTitle,
                  detail: detail,
                  dueAt: session.nextDue,
                  updatedAt: now,
                  pausedAt: session.pausedAt,
                  finishAt: session.finishAt)
    }
}

/// Starts, updates and ends the lock-screen / Dynamic Island countdown.
@MainActor
final class LiveActivityController {
    func sync(_ session: BakeSession?) {
        let activities = Activity<BakeActivityAttributes>.activities

        guard let session, !session.isFinished(at: .now) else {
            for activity in activities { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }

        let id = session.id.uuidString
        for activity in activities where activity.attributes.sessionID != id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        let content = ActivityContent(state: BakeActivityAttributes.ContentState(session: session),
                                      staleDate: nil)
        if let current = activities.first(where: { $0.attributes.sessionID == id && $0.activityState == .active }) {
            Task { await current.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // iOS ends Live Activities after ~8 h; a new one is started the next time the app is opened.
            _ = try? Activity.request(
                attributes: BakeActivityAttributes(sessionID: id, recipeName: session.recipe.name),
                content: content,
                pushType: nil)
        }
    }
}
