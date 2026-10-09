import XCTest
import UIKit
import AVFoundation
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
        // Compare the persisted representation: the library's existing ISO-8601 format stores whole seconds.
        XCTAssertEqual(try JSONEncoder.tennisTracker.encode(destination.data.court.media),
                       try JSONEncoder.tennisTracker.encode(store.data.court.media))
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

    func testRealVideoImportMomentValidationAndPackageRoundTrip() async throws {
        let (store, coach, athlete, _) = try fixture()
        let url = folder.appendingPathComponent("fictional-clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<3 {
            for _ in 0..<200 {
                if input.isReadyForMoreMediaData { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            if let address = CVPixelBufferGetBaseAddress(pixel) { memset(address, Int32(index * 80), CVPixelBufferGetBytesPerRow(pixel) * 32) }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        var prepared = try await CourtMediaVault.prepare(url, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
        XCTAssertEqual(prepared.record.kind, .video)
        XCTAssertGreaterThan(try XCTUnwrap(prepared.record.durationSeconds), 1)
        prepared.record.moments = [CourtMediaMoment(seconds: 1, description: "Fictional test frame", observation: "Changed colour", nextAction: "Review the next frame")]
        XCTAssertTrue(store.saveMedia(prepared.record, importing: prepared.bytes))
        let saved = try XCTUnwrap(store.data.court.media.first)
        var invalid = saved; invalid.moments[0].seconds = 500
        XCTAssertFalse(store.saveMedia(invalid))
        XCTAssertEqual(store.data.court.media.first?.moments.first?.seconds, 1)
        let payload = try store.fullBackup()
        XCTAssertEqual(payload.media[saved.relativeFilename], prepared.bytes)
        let clip = AVURLAsset(url: try store.mediaURL(for: saved))
        let playable = try await clip.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    func testUnsupportedAndOversizeImportsDoNotCreateRecords() async throws {
        let (store, coach, athlete, _) = try fixture()
        let corrupt = folder.appendingPathComponent("not-a-video.mov")
        try Data("Not a video".utf8).write(to: corrupt)
        do {
            _ = try await CourtMediaVault.prepare(corrupt, athleteID: athlete.id, coachID: coach.id, sport: .tennis)
            XCTFail("Unsupported data was accepted")
        } catch { }
        let large = folder.appendingPathComponent("oversize.png")
        try Data(count: CourtMediaVault.maximumFileBytes + 1).write(to: large)
        XCTAssertThrowsError(try CourtMediaVault.checkedSize(large))
        XCTAssertTrue(store.data.court.media.isEmpty)
    }
}
