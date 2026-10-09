import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let courtStoryBackup = UTType(exportedAs: "app.courtstory.private-backup", conformingTo: .package)
}

struct CourtBackupPayload {
    var library: AppData
    var media: [String: Data]
    var legacyRecordsOnly = false

    func validate() throws {
        try TennisBackup.validate(library)
        let expected = Set(library.court.media.map(\.relativeFilename))
        guard (legacyRecordsOnly && media.isEmpty) || Set(media.keys) == expected else { throw TennisBackupError.invalidFile }
        var total = 0
        for record in library.court.media {
            guard let bytes = media[record.relativeFilename] else {
                if legacyRecordsOnly { continue }
                throw CourtMediaError.unavailable
            }
            guard !bytes.isEmpty, bytes.count <= CourtMediaVault.maximumFileBytes else { throw CourtMediaError.tooLarge }
            if let expected = record.contentSHA256, CourtMediaVault.checksum(bytes) != expected { throw CourtMediaError.unavailable }
            total += bytes.count
            guard total <= CourtMediaVault.maximumLibraryBytes else { throw CourtMediaError.capacity }
        }
    }

    func fileWrapper() throws -> FileWrapper {
        try validate()
        guard !legacyRecordsOnly else { throw TennisBackupError.invalidFile }
        return FileWrapper(directoryWithFileWrappers: [
            "library.json": FileWrapper(regularFileWithContents: try JSONEncoder.tennisTracker.encode(library)),
            "Media": FileWrapper(directoryWithFileWrappers: media.mapValues { FileWrapper(regularFileWithContents: $0) })
        ])
    }

    static func read(_ url: URL) throws -> CourtBackupPayload {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw TennisBackupError.invalidFile }
        if values.isDirectory != true {
            guard let size = values.fileSize, size <= 20_000_000 else { throw TennisBackupError.invalidFile }
            return CourtBackupPayload(library: try TennisBackup.decode(Data(contentsOf: url)), media: [:], legacyRecordsOnly: true)
        }
        // Bound and inspect each expected file before loading any package media into memory.
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        guard Set(entries.map(\.lastPathComponent)) == ["library.json", "Media"] else { throw TennisBackupError.invalidFile }
        let libraryURL = url.appendingPathComponent("library.json")
        _ = try CourtMediaVault.checkedSize(libraryURL)
        let library = try TennisBackup.decode(Data(contentsOf: libraryURL))
        let folder = url.appendingPathComponent("Media", isDirectory: true)
        let folderValues = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard folderValues.isDirectory == true, folderValues.isSymbolicLink != true else { throw TennisBackupError.invalidFile }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        guard Set(files.map(\.lastPathComponent)) == Set(library.court.media.map(\.relativeFilename)) else { throw TennisBackupError.invalidFile }
        var total = 0
        for file in files {
            total += try CourtMediaVault.checkedSize(file)
            guard total <= CourtMediaVault.maximumLibraryBytes else { throw CourtMediaError.capacity }
        }
        var media: [String: Data] = [:]
        for record in library.court.media { media[record.relativeFilename] = try CourtMediaVault.verifiedBytes(for: record, in: folder) }
        let payload = CourtBackupPayload(library: library, media: media)
        try payload.validate()
        return payload
    }
}

struct CourtBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.courtStoryBackup] }
    var wrapper: FileWrapper
    init(payload: CourtBackupPayload) throws { wrapper = try payload.fileWrapper() }
    init() { wrapper = FileWrapper(directoryWithFileWrappers: [:]) }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}
