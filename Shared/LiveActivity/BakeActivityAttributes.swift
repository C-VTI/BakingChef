import ActivityKit
import Foundation

/// Data shown in the Live Activity (lock screen + Dynamic Island).
struct BakeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var dueAt: Date
        var updatedAt: Date
        var pausedAt: Date?
        var finishAt: Date
    }

    var sessionID: String
    var recipeName: String
}
