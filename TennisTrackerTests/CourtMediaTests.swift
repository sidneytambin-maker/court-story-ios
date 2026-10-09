import XCTest
import UIKit
@testable import TennisTracker

@MainActor
final class CourtMediaTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("CourtMediaTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func fixture() throws -> (TennisStore, PlayerProfile, PlayerProfile, URL) {
        let store = TennisStore(storeURL: folder.appendingPathComponent(UUID().uuidString + ".json"))
        var coach = PlayerProfile(); coach.name = "Demo Coach"; coach.court.sports[0].role = .coach
        var settings = AppSettings(); settings.trackingMode = .power
        XCTAssertTrue(store.completeOnboarding(player: coach, settings: settings))
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"; athlete.court.coachOwnerID = coach.id
        XCTAssertTrue(store.saveCourtProfile(athlete))
        let url = folder.appendingPathComponent(UUID().uuidString + ".png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return (store, coach, athlete, url)
    }

    func testPhotoImportPrivatePackageRestoreAndDeletePreserveOriginal() async throws {
        let (store, coach, athlete, url) = try fixture()
        let prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertEqual(prepared.record.kind, .photo)
        XCTAssertNil(prepared.record.durationSeconds)
        XCTAssertEqual(prepared.record.contentSHA256, CourtMediaVault.checksum(prepared.bytes))
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        let saved = try XCTUnwrap(store.data.court.media.first)
        XCTAssertEqual(try Data(contentsOf: store.mediaURL(for: saved)), prepared.bytes)
        let backup = try store.fullBackup()
        let packageURL = folder.appendingPathComponent("complete.courtstorybackup", isDirectory: true)
        try backup.fileWrapper().write(to: packageURL, options: .atomic, originalContentsURL: nil)
        let decoded = try CourtBackupPayload.read(packageURL)
        let destination = TennisStore(storeURL: folder.appendingPathComponent("restored.json"))
        try destination.restoreFullBackup(decoded)
        XCTAssertNotEqual(destination.data.libraryID, store.data.libraryID)
        XCTAssertEqual(destination.data.court.media, store.data.court.media)
        XCTAssertEqual(try Data(contentsOf: destination.mediaURL(for: saved)), prepared.bytes)
        XCTAssertThrowsError(try destination.restoreFullBackup(decoded))
        XCTAssertTrue(store.removeCoachingRecord(saved.id))
        XCTAssertTrue(store.data.court.deletedIDs.contains(saved.id))
        XCTAssertThrowsError(try store.mediaURL(for: saved))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(destination.data.court.media.count, 1)
    }

    func testMediaRejectsWrongAthleteLinkStaleEditRetargetAndDuplicateFilename() async throws {
        let (store, coach, athlete, url) = try fixture()
        let prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        var wrong = prepared.record; wrong.athleteID = coach.id
        XCTAssertFalse(store.saveMedia(wrong, importing: prepared.bytes))
        XCTAssertTrue(store.data.court.media.isEmpty)
        var ownMatch = MatchRecord(playerID: coach.id); ownMatch.status = .scheduled
        store.upsertMatch(ownMatch)
        wrong = prepared.record; wrong.activityID = ownMatch.id
        XCTAssertFalse(store.saveMedia(wrong, importing: prepared.bytes))
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        var saved = try XCTUnwrap(store.data.court.media.first)
        let stale = saved
        saved.description = "A useful view of the serve."
        XCTAssertTrue(store.saveMedia(saved))
        XCTAssertFalse(store.saveMedia(stale))
        saved = try XCTUnwrap(store.data.court.media.first)
        saved.athleteID = coach.id
        XCTAssertFalse(store.saveMedia(saved))
        var duplicate = prepared.record; duplicate.id = UUID()
        XCTAssertFalse(store.saveMedia(duplicate, importing: prepared.bytes))
        XCTAssertEqual(store.data.court.media.count, 1)
    }

    func testCorruptMissingAndUnexpectedPackageFilesAreNotSilentlyBackedUpOrRestored() async throws {
        let (store, coach, athlete, url) = try fixture()
        let prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        let saved = try XCTUnwrap(store.data.court.media.first)
        var backup = try store.fullBackup()
        backup.media[saved.relativeFilename] = Data("changed".utf8)
        XCTAssertThrowsError(try backup.validate())
        backup = try store.fullBackup(); backup.media["unexpected.jpg"] = prepared.bytes
        XCTAssertThrowsError(try backup.validate())
        let location = try store.mediaURL(for: saved)
        try Data("changed".utf8).write(to: location, options: .atomic)
        XCTAssertThrowsError(try store.mediaURL(for: saved))
        XCTAssertThrowsError(try store.fullBackup())
        try FileManager.default.removeItem(at: location)
        XCTAssertThrowsError(try store.fullBackup())
        XCTAssertEqual(store.data.court.media.count, 1)
    }

    func testModeAndArchiveRetainMediaButPreventNewImports() async throws {
        let (store, coach, athlete, url) = try fixture()
        let prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        var settings = store.data.settings; settings.trackingMode = .basic; store.updateSettings(settings)
        var record = try XCTUnwrap(store.data.court.media.first); record.description = "Hidden-mode edit"
        XCTAssertFalse(store.saveMedia(record))
        XCTAssertEqual(store.data.court.media.count, 1)
        settings.trackingMode = .standard; store.updateSettings(settings)
        XCTAssertTrue(store.archiveCourtPlayer(athlete.id, archived: true))
        let second = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertFalse(store.saveMedia(second.record, importing: second.bytes))
        XCTAssertNoThrow(try store.fullBackup())
        XCTAssertTrue(store.saveMedia(record))
    }

    func testUnsafeReferencesAndOutOfClipMomentsAreRejected() {
        var record = CourtMediaRecord(athleteID: UUID(), coachID: UUID(), sport: .tennis, kind: .video, relativeFilename: "clip.mov")
        record.durationSeconds = 20
        record.moments = [CourtMediaMoment(seconds: 21)]
        XCTAssertNotNil(record.validationMessage)
        record.moments = [CourtMediaMoment(seconds: .nan)]
        XCTAssertNotNil(record.validationMessage)
        record.moments = [CourtMediaMoment(seconds: 10)]
        XCTAssertNil(record.validationMessage)
        for path in ["../clip.mov", "folder/clip.mov", "folder\\clip.mov"] { record.relativeFilename = path; XCTAssertNotNil(record.validationMessage) }
        record.relativeFilename = "clip.mov"; record.kind = .photo
        XCTAssertNotNil(record.validationMessage)
    }

    func testLegacyRecordsOnlyRestoreMakesMissingOriginalsExplicit() async throws {
        let (store, coach, athlete, url) = try fixture()
        let prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        let legacyURL = folder.appendingPathComponent("older.json")
        try store.backupData().write(to: legacyURL)
        let payload = try CourtBackupPayload.read(legacyURL)
        XCTAssertTrue(payload.legacyRecordsOnly)
        let restored = TennisStore(storeURL: folder.appendingPathComponent("old-restored.json"))
        try restored.restoreFullBackup(payload)
        XCTAssertEqual(restored.data.court.media.count, 1)
        XCTAssertThrowsError(try restored.mediaURL(for: prepared.record))
        XCTAssertThrowsError(try restored.fullBackup())
    }
}
