import Foundation

/// Keys used for iPhone ⇄ Watch messages (WatchConnectivity).
enum SyncKeys {
    static let session = "session"
    static let action = "action"
    static let sessionID = "sessionID"
    static let timestamp = "ts"
}

enum SyncCodec {
    static func encode(_ session: BakeSession?) -> Data {
        session.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    }

    static func decodeSession(_ data: Data) -> BakeSession? {
        data.isEmpty ? nil : try? JSONDecoder().decode(BakeSession.self, from: data)
    }

    static func message(_ action: SessionAction, sessionID: UUID) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(action) else { return nil }
        return [SyncKeys.action: data, SyncKeys.sessionID: sessionID.uuidString]
    }

    static func decodeMessage(_ message: [String: Any]) -> (UUID, SessionAction)? {
        guard let data = message[SyncKeys.action] as? Data,
              let idString = message[SyncKeys.sessionID] as? String,
              let id = UUID(uuidString: idString),
              let action = try? JSONDecoder().decode(SessionAction.self, from: data) else { return nil }
        return (id, action)
    }
}
