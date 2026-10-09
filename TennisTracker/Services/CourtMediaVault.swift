import Foundation
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

enum CourtMediaError: LocalizedError {
    case invalidFile, tooLarge, longVideo, unavailable, changed, capacity, cannotSave
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Choose a supported photo or a playable video clip. Nothing was added."
        case .tooLarge: return "Choose a file smaller than 20 MB. Trim or reduce the original before adding it."
        case .longVideo: return "Choose a video no longer than two minutes. Trim the original before adding it."
        case .unavailable: return "The original media file is missing or unavailable on this iPhone. Its notes are still here. Restore the original from your private backup."
        case .changed: return "This item changed while you were editing. Reopen it to keep the newer changes."
        case .capacity: return "The private media library has reached its 500 MB limit. Export a private backup before removing items."
        case .cannotSave: return "The media could not be saved. Your original records have not changed."
        }
    }
}

struct CourtMediaImport: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            CourtMediaImport(url: try CourtMediaVault.stage(received.file))
        }
        FileRepresentation(importedContentType: .movie) { received in
            CourtMediaImport(url: try CourtMediaVault.stage(received.file))
        }
    }
}

struct CourtPreparedMedia {
    var record: CourtMediaRecord
    var bytes: Data
}

enum CourtMediaVault {
    static let maximumFileBytes = 20_000_000
    static let maximumLibraryBytes = 500_000_000
    static let maximumVideoSeconds: Double = 120

    static func stage(_ source: URL) throws -> URL {
        _ = try checkedSize(source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CourtStoryMediaImports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static func discardStaged(_ url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CourtStoryMediaImports", isDirectory: true).standardizedFileURL
        guard url.standardizedFileURL.deletingLastPathComponent() == folder else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func checkedSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0 else { throw CourtMediaError.invalidFile }
        guard size <= maximumFileBytes else { throw CourtMediaError.tooLarge }
        return size
    }

    static func checksum(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    static func prepare(_ url: URL, athleteID: UUID, coachID: UUID, sport: CourtSportSelection) async throws -> CourtPreparedMedia {
        _ = try checkedSize(url)
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= maximumFileBytes else { throw CourtMediaError.tooLarge }
        let kind: CourtMediaKind
        let duration: Double?
        let fileExtension: String
        if let image = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(image) > 0,
           let typeID = CGImageSourceGetType(image), let type = UTType(typeID as String), type.conforms(to: .image) {
            kind = .photo; duration = nil; fileExtension = type.preferredFilenameExtension ?? "img"
        } else {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw CourtMediaError.invalidFile }
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0 else { throw CourtMediaError.invalidFile }
            guard seconds <= maximumVideoSeconds else { throw CourtMediaError.longVideo }
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) else { throw CourtMediaError.invalidFile }
            kind = .video; duration = seconds; fileExtension = type.preferredFilenameExtension ?? "mov"
        }
        var record = CourtMediaRecord(athleteID: athleteID, coachID: coachID, sport: sport, kind: kind, relativeFilename: "")
        record.relativeFilename = record.id.uuidString.lowercased() + "." + fileExtension
        record.durationSeconds = duration
        record.contentSHA256 = checksum(bytes)
        return CourtPreparedMedia(record: record, bytes: bytes)
    }

    static func verifiedBytes(for record: CourtMediaRecord, in folder: URL) throws -> Data {
        guard record.validationMessage == nil else { throw CourtMediaError.invalidFile }
        let url = folder.appendingPathComponent(record.relativeFilename)
        do { _ = try checkedSize(url) } catch { throw CourtMediaError.unavailable }
        let bytes = try Data(contentsOf: url)
        if let expected = record.contentSHA256, checksum(bytes) != expected { throw CourtMediaError.unavailable }
        return bytes
    }
}
