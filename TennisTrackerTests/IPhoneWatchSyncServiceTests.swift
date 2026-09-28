import XCTest
import WatchConnectivity
@testable import TennisTracker

@MainActor
final class IPhoneWatchSyncServiceTests: XCTestCase {
    func testSnapshotWaitsForActivationAndSendsAfterCallback() async throws {
        let transport = WatchTransportStub()
        let service = IPhoneWatchSyncService(session: transport)
        service.sendSnapshot(AppData())
        XCTAssertTrue(transport.contexts.isEmpty)

        transport.activationState = .activated
        let delivered = expectation(description: "Queued snapshot sent after activation")
        transport.onContext = { delivered.fulfill() }
        service.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(transport.contexts.count, 1)
    }

    func testUnreachableWatchStillReceivesBackgroundContext() {
        let transport = WatchTransportStub()
        transport.activationState = .activated
        let service = IPhoneWatchSyncService(session: transport)
        service.sendSnapshot(AppData())
        XCTAssertEqual(transport.contexts.count, 1)
        XCTAssertEqual(transport.liveMessages.count, 0)
        XCTAssertTrue(service.connectionDescription.contains("Live connection not currently reachable"))
        XCTAssertTrue(service.connectionDescription.contains("Court Story installed"))
        XCTAssertTrue(service.syncMessage.contains("queued"))
    }

    func testFailedContextRemainsPendingForRetry() {
        let transport = WatchTransportStub()
        transport.activationState = .activated
        transport.rejectContext = true
        let service = IPhoneWatchSyncService(session: transport)
        service.sendSnapshot(AppData())
        XCTAssertTrue(service.syncMessage.contains("could not be queued"))
        transport.rejectContext = false
        service.sendSnapshot(AppData())
        XCTAssertEqual(transport.contexts.count, 1)
    }

    func testLatestSnapshotReplacesEarlierPendingSnapshot() async throws {
        let transport = WatchTransportStub()
        let service = IPhoneWatchSyncService(session: transport)
        service.sendSnapshot(AppData())
        var latest = AppData()
        latest.players = [PlayerProfile()]
        service.sendSnapshot(latest)
        transport.activationState = .activated
        let delivered = expectation(description: "Latest snapshot sent")
        transport.onContext = { delivered.fulfill() }
        service.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        await fulfillment(of: [delivered], timeout: 2)
        let encoded = try XCTUnwrap(transport.contexts.last?["snapshotData"] as? Data)
        let snapshot = try JSONDecoder.tennisTracker.decode(TennisWatchSnapshot.self, from: encoded)
        XCTAssertEqual(snapshot.players.map(\.id), latest.players.map(\.id))
    }
}

private final class WatchTransportStub: TennisWatchSessionTransport {
    weak var delegate: WCSessionDelegate?
    var activationState: WCSessionActivationState = .notActivated
    var isPaired = true
    var isWatchAppInstalled = true
    var isReachable = false
    var rejectContext = false
    var contexts: [[String: Any]] = []
    var liveMessages: [Data] = []
    var onContext: (() -> Void)?
    func activate() {}
    func updateApplicationContext(_ context: [String: Any]) throws {
        if rejectContext { throw NSError(domain: "SyncTest", code: 1) }
        contexts.append(context)
        onContext?()
    }
    func sendMessageData(_ data: Data, replyHandler: ((Data) -> Void)?, errorHandler: ((Error) -> Void)?) {
        liveMessages.append(data)
    }
}
