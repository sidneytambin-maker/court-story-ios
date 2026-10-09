import SwiftUI
import PhotosUI
import AVKit
import ImageIO

private struct CourtMediaDraft: Identifiable {
    var record: CourtMediaRecord
    var bytes: Data?
    var id: UUID { record.id }
}

struct CourtMediaLibraryView: View {
    @EnvironmentObject private var store: TennisStore
    let athleteID: UUID
    let sport: CourtSportSelection
    @State private var selection: PhotosPickerItem?
    @State private var importingFile = false
    @State private var loading = false
    @State private var message = ""
    @State private var draft: CourtMediaDraft?
    @State private var deleting: CourtMediaRecord?
    private var athlete: PlayerProfile? { store.data.players.first { $0.id == athleteID } }
    private var records: [CourtMediaRecord] {
        store.data.court.media.filter { $0.athleteID == athleteID && $0.sport == sport }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        TennisList {
            if CourtFeature.media.isAvailable(in: store.data.settings.trackingMode), let athlete {
                Section {
                    CourtCaptureIdentity(athlete: athlete.displayName, sport: sport, coached: true)
                    if !athlete.isArchived, athlete.court.coachOwnerID != nil {
                        PhotosPicker(selection: $selection, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                            Label("Add from Photos", systemImage: "photo.badge.plus")
                        }.disabled(loading).accessibilityIdentifier("addCoachingMediaPhotos")
                        Button("Add from Files", systemImage: "folder.badge.plus") { importingFile = true }.disabled(loading)
                            .accessibilityIdentifier("addCoachingMediaFiles")
                    }
                    if loading { ProgressView("Checking media") }
                    if !message.isEmpty { Text(message).accessibilityIdentifier("mediaStatus") }
                }
                if records.isEmpty { Text("No photos or clips for this player and sport.") }
                ForEach(records) { record in
                    Button { draft = CourtMediaDraft(record: record) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.description.fallback(record.kind == .photo ? "Photo" : "Video clip")).font(.headline)
                                Text(record.createdAt, style: .date).font(.caption)
                                if let seconds = record.durationSeconds { Text(TennisDurationFormatter.text(seconds: seconds)).font(.caption) }
                                if !record.moments.isEmpty { Text("\(record.moments.count) noted moments").font(.caption) }
                            }
                        } icon: { Image(systemName: record.kind == .photo ? "photo" : "video") }
                            .accessibilityElement(children: .combine)
                    }.accessibilityAction(named: "Edit media and notes") { draft = CourtMediaDraft(record: record) }
                        .accessibilityAction(named: "Delete media") { deleting = record }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = record } }
                }
            } else { Text("Media is available in Standard and Power modes. Your existing files and notes are retained.") }
        }.navigationTitle("Player media").tennisThemedList()
        .sheet(item: $draft) { CourtMediaEditor(record: $0.record, importedBytes: $0.bytes) }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            loading = true
            Task {
                do {
                    guard let result = try await item.loadTransferable(type: CourtMediaImport.self) else { throw CourtMediaError.invalidFile }
                    await prepare(result.url, staged: true)
                } catch { report(error.localizedDescription); loading = false }
                selection = nil
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image, .movie]) { result in
            switch result {
            case .success(let url):
                loading = true
                Task {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    await prepare(url, staged: false)
                }
            case .failure(let error): report(error.localizedDescription)
            }
        }
        .confirmationDialog("Delete media and its notes from Court Story? Your original in Photos or Files is not changed.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete media and notes", role: .destructive) { if let deleting { _ = store.removeCoachingRecord(deleting.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func prepare(_ url: URL, staged: Bool) async {
        defer { if staged { CourtMediaVault.discardStaged(url) }; loading = false }
        guard let athlete, !athlete.isArchived, let coachID = athlete.court.coachOwnerID else { report("Restore this player before adding media."); return }
        do {
            let prepared = try await CourtMediaVault.prepare(url, athleteID: athleteID, coachID: coachID, sport: sport)
            draft = CourtMediaDraft(record: prepared.record, bytes: prepared.bytes)
        } catch { report(error.localizedDescription) }
    }
    private func report(_ text: String) { message = text; store.announce(text) }
}

@MainActor private final class CourtClipPlayback: ObservableObject {
    let player = AVPlayer()
    @Published var seconds = 0.0
    @Published var playing = false
    private var observer: Any?
    func open(_ url: URL) {
        close()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.seconds = time.seconds.isFinite ? time.seconds : 0
                self.playing = self.player.rate > 0
            }
        }
    }
    func toggle() { if player.rate > 0 { player.pause(); playing = false } else { player.play(); playing = true } }
    func seek(_ value: Double) { guard value.isFinite else { return }; seconds = value; player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    func close() { player.pause(); playing = false; if let observer { player.removeTimeObserver(observer); self.observer = nil }; player.replaceCurrentItem(with: nil) }
}

struct CourtMediaEditor: View {
    @EnvironmentObject private var store: TennisStore
    @Environment(\.dismiss) private var dismiss
    @State var record: CourtMediaRecord
    var importedBytes: Data?
    @StateObject private var playback = CourtClipPlayback()
    @State private var fileURL: URL?
    @State private var previewImage: UIImage?
    @State private var error = ""
    @State private var fileWarning = ""
    @State private var confirmingShare = false
    @State private var sharing = false
    @State private var confirmingDelete = false
    @AccessibilityFocusState private var errorFocused: Bool
    private var athleteName: String { store.data.players.first { $0.id == record.athleteID }?.displayName ?? "Unavailable athlete" }
    private var saved: Bool { store.data.court.media.contains { $0.id == record.id } }

    var body: some View {
        NavigationStack {
            TennisForm {
                if CourtFeature.media.isAvailable(in: store.data.settings.trackingMode) {
                    Section {
                        CourtCaptureIdentity(athlete: athleteName, sport: record.sport, coached: true)
                        TextField("Media description", text: $record.description, axis: .vertical)
                            .accessibilityHint("Describe the useful context. Court Story does not analyse images or video.")
                            .accessibilityIdentifier("coachingMediaDescription")
                        DatePicker("Recorded date", selection: $record.createdAt, displayedComponents: [.date, .hourAndMinute])
                        Picker("Linked activity", selection: $record.activityID) {
                            Text("No linked activity").tag(Optional<UUID>.none)
                            if let activityID = record.activityID, store.data.deletedRecordIDs.contains(activityID) {
                                Text("Previously linked activity, deleted").tag(Optional(activityID))
                            }
                            ForEach(store.data.trainingSessions.filter { $0.playerID == record.athleteID && $0.court.sport == record.sport }.sorted { $0.date > $1.date }) {
                                Text("Training, \($0.date.fullTennisDate)").tag(Optional($0.id))
                            }
                            ForEach(store.data.matches.filter { $0.playerID == record.athleteID && $0.court.sport == record.sport }.sorted { $0.date > $1.date }) {
                                Text("Match, \($0.date.fullTennisDate)").tag(Optional($0.id))
                            }
                            ForEach(store.data.tournaments.filter { $0.playerID == record.athleteID && $0.court.sport == record.sport }.sorted { $0.date > $1.date }) {
                                Text("Tournament, \($0.name)").tag(Optional($0.id))
                            }
                        }
                    }
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit().frame(maxHeight: 300)
                            .accessibilityLabel(record.description.fallback("Photo. No description recorded."))
                    }
                    if record.kind == .video, fileURL != nil, let duration = record.durationSeconds, duration > 0 {
                        Section("Clip") {
                            VideoPlayer(player: playback.player).frame(height: 220).accessibilityHidden(true)
                            Button(playback.playing ? "Pause video" : "Play video", systemImage: playback.playing ? "pause.fill" : "play.fill") { playback.toggle() }
                                .accessibilityIdentifier("coachingVideoPlayback")
                            Slider(value: Binding(get: { min(max(playback.seconds, 0), duration) }, set: { playback.seek($0) }), in: 0...duration, step: 1) { Text("Video position") }
                                .accessibilityValue("\(TennisDurationFormatter.text(seconds: playback.seconds)) of \(TennisDurationFormatter.text(seconds: duration))")
                            TextField("Jump to second", value: Binding(get: { playback.seconds }, set: { playback.seek(min(max($0, 0), duration)) }), format: .number).keyboardType(.decimalPad)
                            Button("Note this moment", systemImage: "bookmark") {
                                playback.player.pause(); playback.playing = false
                                record.moments.append(CourtMediaMoment(seconds: min(max(playback.seconds, 0), duration)))
                            }.accessibilityIdentifier("addVideoMoment")
                        }
                    }
                    if !fileWarning.isEmpty { Text(fileWarning).accessibilityIdentifier("mediaFileWarning") }
                    ForEach($record.moments) { $moment in
                        Section("Moment at \(TennisDurationFormatter.text(seconds: moment.seconds))") {
                            TextField("Seconds into clip", value: $moment.seconds, format: .number).keyboardType(.decimalPad)
                            TextField("Moment description", text: $moment.description, axis: .vertical)
                            TextField("Observation", text: $moment.observation, axis: .vertical)
                            TextField("Next action", text: $moment.nextAction, axis: .vertical)
                            if fileURL != nil { Button("Play from this moment", systemImage: "play") { playback.seek(moment.seconds); if !playback.playing { playback.toggle() } } }
                            Button("Remove moment", role: .destructive) { record.moments.removeAll { $0.id == moment.id } }
                        }
                    }
                    if saved {
                        Section {
                            if fileURL != nil { Button("Share original media", systemImage: "square.and.arrow.up") { confirmingShare = true } }
                            Button("Delete media and notes", role: .destructive) { confirmingDelete = true }
                        }
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red).accessibilityFocused($errorFocused) }
                } else { Text("Media is available in Standard and Power modes. Your files and notes are retained.") }
            }.navigationTitle(record.kind == .photo ? "Photo and notes" : "Clip and moments")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveMedia(record, importing: importedBytes) { dismiss() }
                        else { error = record.validationMessage ?? store.lastAnnouncement; errorFocused = true }
                    }.disabled(!CourtFeature.media.isAvailable(in: store.data.settings.trackingMode)).accessibilityIdentifier("saveCoachingMedia")
                }
            }
            .task { await loadPreview() }
            .onDisappear { playback.close(); if let fileURL, importedBytes != nil { CourtMediaVault.discardStaged(fileURL) } }
            .confirmationDialog("Share this original file? It may include faces, voices, location metadata or private details. Coaching notes are not included. Share only with the player's permission.", isPresented: $confirmingShare, titleVisibility: .visible) {
                Button("Choose recipient or destination") { sharing = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $sharing) { if let fileURL { CourtMediaShareSheet(url: fileURL) } }
            .confirmationDialog("Delete this media and all its notes? The original in Photos or Files is not changed.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete media and notes", role: .destructive) { if store.removeCoachingRecord(record.id) { dismiss() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @MainActor private func loadPreview() async {
        guard CourtFeature.media.isAvailable(in: store.data.settings.trackingMode) else { return }
        do {
            let bytes: Data
            if let importedBytes {
                bytes = importedBytes
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CourtStoryMediaImports", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(record.relativeFilename)
                try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                fileURL = url
            } else { let url = try store.mediaURL(for: record); fileURL = url; bytes = try Data(contentsOf: url) }
            if record.kind == .photo, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                previewImage = UIImage(cgImage: image)
            }
            if record.kind == .video, let fileURL { playback.open(fileURL) }
        } catch { fileWarning = error.localizedDescription }
    }
}

private struct CourtMediaShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
