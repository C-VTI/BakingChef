import Foundation
import WatchConnectivity

/// iPhone side of the Watch sync: sends the current session, receives actions.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ session: BakeSession?) {
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        guard wc.activationState == .activated, wc.isPaired, wc.isWatchAppInstalled else { return }
        try? wc.updateApplicationContext([
            SyncKeys.session: SyncCodec.encode(session),
            SyncKeys.timestamp: Date().timeIntervalSince1970,
        ])
    }

    private func handle(_ message: [String: Any]) {
        guard let decoded = SyncCodec.decodeMessage(message) else { return }
        Task { @MainActor in AppModel.shared.handleRemote(decoded.1, sessionID: decoded.0) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in AppModel.shared.pushToWatch() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
