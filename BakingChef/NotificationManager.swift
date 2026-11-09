import Foundation
import UserNotifications

/// Schedules local notifications for a session (no server / push needed).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let stepCategory = "STEP_DUE"
    private static let completeAction = "COMPLETE_STEP"
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "Erledigt ✓", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.stepCategory, actions: [complete], intentIdentifiers: [])
        ])
    }

    func reschedule(for session: BakeSession?) {
        center.removeAllPendingNotificationRequests()
        guard let session else {
            center.removeAllDeliveredNotifications()
            return
        }
        // Clear notifications of steps that are already checked off.
        let doneIDs = session.steps.indices
            .filter { session.steps[$0].isDone }
            .flatMap { session.notificationIDs(forStep: $0) }
        center.removeDeliveredNotifications(withIdentifiers: doneIDs)

        for planned in session.notificationPlan(now: .now) {
            let interval = planned.date.timeIntervalSinceNow
            guard interval > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.threadIdentifier = session.id.uuidString
            if let step = planned.stepIndex {
                content.categoryIdentifier = Self.stepCategory
                content.userInfo = [SyncKeys.sessionID: session.id.uuidString, "step": step]
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger))
        }
    }

    // Show banners also while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // "Erledigt ✓" pressed on a notification (works without opening the app).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard response.actionIdentifier == Self.completeAction,
              let idString = info[SyncKeys.sessionID] as? String,
              let id = UUID(uuidString: idString),
              let step = info["step"] as? Int else {
            completionHandler()
            return
        }
        Task { @MainActor in
            AppModel.shared.handleRemote(.complete(step: step), sessionID: id)
            completionHandler()
        }
    }
}
