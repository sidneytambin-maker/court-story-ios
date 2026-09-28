import SwiftUI
import UniformTypeIdentifiers

struct TennisBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw TennisBackupError.invalidFile }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PrivateBackupView: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var document = TennisBackupDocument(data: Data())
    @State private var preview: AppData?
    @State private var message = ""

    var body: some View {
        TennisForm {
            Section {
                Text("A private backup contains your player details, tennis records, settings and saved workout summaries. It does not export Apple's Health database. Only restore a file that belongs to you.")
                if store.needsOnboarding {
                    Button("Choose My Private Backup") { importing = true }
                        .accessibilityIdentifier("choosePrivateBackup")
                } else {
                    Button("Export Private Backup") {
                        do {
                            document = TennisBackupDocument(data: try store.backupData())
                            exporting = true
                        } catch { report(error.localizedDescription) }
                    }.accessibilityIdentifier("exportPrivateBackup")
                    Text("Keep the backup somewhere private. Never send it to other testers or attach it to public feedback.")
                }
            }
            if let preview {
                Section("Backup Contents") {
                    Text("\(preview.players.count) players, \(preview.matches.count) matches, \(preview.trainingSessions.count) training sessions, \(preview.tournaments.count) tournaments, \(preview.setup.coaches.count) coaches and \(preview.setup.venues.count) venues.")
                    Text("Restore creates your library in this installation and sends it only to your paired Apple Watch. The original installation and backup file are not changed.")
                    Button("Restore My Backup") {
                        do { try store.restoreBackup(preview); dismiss() }
                        catch { report(error.localizedDescription) }
                    }.accessibilityIdentifier("confirmPrivateRestore")
                    Button("Cancel", role: .cancel) { self.preview = nil }
                }
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("backupStatus") }
        }
        .navigationTitle("Private Backup")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw TennisBackupError.invalidFile }
                preview = try TennisBackup.decode(Data(contentsOf: url))
                report("Backup checked. Review the contents, then choose Restore My Backup or Cancel.")
            } catch { preview = nil; report(error.localizedDescription) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Court-Story-Private-Backup") { result in
            switch result {
            case .success: report("Your private Court Story backup has been exported.")
            case .failure(let error): report(error.localizedDescription)
            }
        }
    }

    private func report(_ value: String) { message = value; store.announce(value) }
}
