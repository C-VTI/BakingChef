import Observation
import SwiftUI
import WatchConnectivity

@main
struct BakingChefWatchApp: App {
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView().environment(model)
        }
    }
}

/// Watch state: mirrors the session of the iPhone and sends actions back.
@MainActor
@Observable
final class WatchModel {
    static let shared = WatchModel()
    private(set) var session: BakeSession?
    @ObservationIgnored private let connector = WatchConnector()

    private init() { connector.activate() }

    func receive(_ session: BakeSession?) { self.session = session }

    func send(_ action: SessionAction) {
        guard var s = session else { return }
        s.apply(action)          // update immediately, the iPhone confirms afterwards
        session = s
        connector.send(action, sessionID: s.id)
    }
}

final class WatchConnector: NSObject, WCSessionDelegate {
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ action: SessionAction, sessionID: UUID) {
        guard let message = SyncCodec.message(action, sessionID: sessionID) else { return }
        let wc = WCSession.default
        if wc.isReachable {
            wc.sendMessage(message, replyHandler: nil) { _ in wc.transferUserInfo(message) }
        } else {
            wc.transferUserInfo(message)   // delivered as soon as the iPhone is reachable
        }
    }

    private func deliver(_ context: [String: Any]) {
        guard let data = context[SyncKeys.session] as? Data else { return }
        let session = SyncCodec.decodeSession(data)
        Task { @MainActor in WatchModel.shared.receive(session) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        deliver(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }
}
