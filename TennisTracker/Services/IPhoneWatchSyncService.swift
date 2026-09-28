import Foundation
import WatchConnectivity

protocol TennisWatchSessionTransport: AnyObject {
    var delegate: WCSessionDelegate? { get set }
    var activationState: WCSessionActivationState { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func sendMessageData(_ data: Data, replyHandler: ((Data) -> Void)?, errorHandler: ((Error) -> Void)?)
}

extension WCSession: TennisWatchSessionTransport {}

@MainActor
final class IPhoneWatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = IPhoneWatchSyncService(session: WCSession.default, supported: WCSession.isSupported())

    @Published private(set) var connectionDescription = "Checking Apple Watch."
    @Published private(set) var syncMessage = "Waiting for the connection."
    @Published private(set) var lastSuccessfulSync = UserDefaults.standard.object(forKey: "lastWatchSyncReceipt") as? Date
    @Published private(set) var healthStatus: TennisWatchHealthStatus?

    var pairedDescription: String { supported && session.activationState == .activated ? (session.isPaired ? "Yes" : "No") : "Checking" }
    var installedDescription: String { supported && session.activationState == .activated ? (session.isWatchAppInstalled ? "Yes" : "No") : "Checking" }
    var liveDescription: String { session.isReachable ? "Available" : "Not currently reachable" }
    var backgroundDescription: String { supported && session.activationState == .activated && session.isPaired && session.isWatchAppInstalled ? "Available" : "Not available yet" }

    private weak var store: TennisStore?
    private let session: TennisWatchSessionTransport
    private let supported: Bool
    private var pendingSnapshot: Data?
    private let snapshotKey = "snapshotData"
    private let commandKey = "commandData"

    init(session: TennisWatchSessionTransport, supported: Bool = true) {
        self.session = session
        self.supported = supported
        super.init()
        if let data = UserDefaults.standard.data(forKey: "lastWatchHealthStatus") {
            healthStatus = try? JSONDecoder.tennisTracker.decode(TennisWatchHealthStatus.self, from: data)
        }
    }

    func configure(store: TennisStore) {
        self.store = store
        guard store.storageError == nil else { return }
        guard supported else {
            refreshConnectionState()
            return
        }
        session.delegate = self
        session.activate()
        sendSnapshot(store.data)
    }

    func sendSnapshot(_ data: AppData, including recordID: UUID? = nil) {
        if let store, store.storageError != nil { return }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "watchSyncLibraryID") != data.libraryID.uuidString {
            lastSuccessfulSync = nil
            healthStatus = nil
            defaults.removeObject(forKey: "lastWatchSyncReceipt")
            defaults.removeObject(forKey: "lastWatchHealthStatus")
            defaults.set(data.libraryID.uuidString, forKey: "watchSyncLibraryID")
        }
        guard let encoded = try? JSONEncoder.tennisTracker.encode(TennisWatchSnapshot(data: data, including: recordID)) else { return }
        pendingSnapshot = encoded
        flushSnapshot()
    }

    private func refreshConnectionState() {
        guard supported else {
            connectionDescription = "Apple Watch is unavailable on this device."
            return
        }
        guard session.activationState == .activated else {
            connectionDescription = "Connecting to Apple Watch."
            return
        }
        guard session.isPaired else {
            connectionDescription = "No Apple Watch is paired."
            return
        }
        guard session.isWatchAppInstalled else {
            connectionDescription = "Apple Watch paired. Court Story is not installed on the Watch."
            return
        }
        connectionDescription = session.isReachable
            ? "Apple Watch paired. Court Story installed. Live connection available."
            : "Apple Watch paired. Court Story installed. Live connection not currently reachable. Updates can still be queued for background delivery."
    }

    private func flushSnapshot() {
        refreshConnectionState()
        guard supported, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, let encoded = pendingSnapshot else { return }
        do {
            // Application context persists the latest snapshot even when the Watch app is asleep.
            try session.updateApplicationContext([snapshotKey: encoded])
            pendingSnapshot = nil
            syncMessage = "Latest data queued for Apple Watch."
            if session.isReachable {
                session.sendMessageData(encoded, replyHandler: nil, errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        self?.syncMessage = "Latest data queued for background delivery."
                    }
                })
            }
        } catch {
            syncMessage = "Sync could not be queued. Please try Refresh Apple Watch Sync."
        }
    }

    private func connectionDidChange() {
        if let store {
            sendSnapshot(store.data)
        } else {
            flushSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receiveHealthStatus(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil {
                self.refreshConnectionState()
                self.syncMessage = "Apple Watch connection could not start."
            } else {
                self.connectionDidChange()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.connectionDidChange() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.connectionDidChange() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshConnectionState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        handleCommandData(messageData)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveHealthStatus(userInfo)
        guard let data = userInfo["commandData"] as? Data else { return }
        handleCommandData(data)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveHealthStatus(applicationContext)
        guard let data = applicationContext["commandData"] as? Data else { return }
        handleCommandData(data)
    }

    nonisolated private func handleCommandData(_ data: Data) {
        guard let envelope = try? JSONDecoder.tennisTracker.decode(TennisWatchCommandEnvelope.self, from: data) else { return }
        Task { @MainActor [weak self] in
            guard let self, let store = self.store, store.storageError == nil,
                  envelope.isAllowed(in: store.data.libraryID) else { return }
            let command = envelope.command
            store.applyWatchCommand(command)
            if case .snapshotReceived = command {
                let now = Date()
                self.lastSuccessfulSync = now
                UserDefaults.standard.set(now, forKey: "lastWatchSyncReceipt")
                self.syncMessage = "Apple Watch confirmed receipt of tennis data."
            }
        }
    }

    nonisolated private func receiveHealthStatus(_ context: [String: Any]) {
        guard let data = context["healthStatusData"] as? Data,
              let libraryID = context["libraryID"] as? String,
              let status = try? JSONDecoder.tennisTracker.decode(TennisWatchHealthStatus.self, from: data) else { return }
        Task { @MainActor [weak self] in
            guard let self, let store = self.store, store.data.libraryID.uuidString == libraryID,
                  self.healthStatus == nil || status.reportedAt > self.healthStatus!.reportedAt else { return }
            self.healthStatus = status
            UserDefaults.standard.set(data, forKey: "lastWatchHealthStatus")
        }
    }
}
