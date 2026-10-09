import SwiftUI
import UniformTypeIdentifiers

private struct CourtReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .commaSeparatedText] }
    var text: String
    init(text: String = "") { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents, let text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct CourtProgressReportView: View {
    @EnvironmentObject private var store: TennisStore
    let athleteID: UUID
    let sport: CourtSportSelection
    @State private var days = 30
    @State private var includeGoal = false
    @State private var includeNotes = false
    @State private var includeObservations = false
    @State private var exporting = false
    @State private var exportType = UTType.plainText
    @State private var document = CourtReportDocument()
    @State private var message = ""
    private var report: CourtProgressReport? {
        CourtProgressReport.make(athleteID: athleteID, sport: sport, data: store.data,
            from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast, through: Date(),
            includeGoal: includeGoal, includeDevelopmentNotes: includeNotes, includeObservations: includeObservations)
    }
    var body: some View {
        TennisList {
            if CourtFeature.coachExport.isAvailable(in: store.data.settings.trackingMode), let report {
                Section {
                    CourtCaptureIdentity(athlete: report.athlete, sport: sport, coached: true)
                    Picker("Report period", selection: $days) {
                        Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90); Text("Last year").tag(365)
                    }
                    Toggle("Include player goal", isOn: $includeGoal)
                    Toggle("Include private development notes", isOn: $includeNotes)
                    Toggle("Include private observations", isOn: $includeObservations)
                }
                Section("Report preview") {
                    ForEach(report.rows) { row in SummaryRow(title: row.title, value: row.value) }
                    Text("Recorded activity only. Health data, access preferences and media are excluded. Share only with the player's permission.")
                    if report.includesPrivateNotes { Text("This preview includes the private details you selected. Check them before exporting.").font(.headline) }
                }
                Section {
                    Button("Export report", systemImage: "square.and.arrow.up") { document = CourtReportDocument(text: report.text); exportType = .plainText; exporting = true }
                        .accessibilityHint("Exports exactly this preview. Choose a private destination or recipient.")
                    Button("Export spreadsheet data", systemImage: "tablecells") { document = CourtReportDocument(text: report.csv); exportType = .commaSeparatedText; exporting = true }
                }
                if !message.isEmpty { Text(message) }
            } else { Text("Progress reports are available in Power mode. Your records are retained.") }
        }.navigationTitle("Progress report").tennisThemedList()
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: "Court-Story-Progress") { result in
            switch result {
            case .success: message = "Progress report exported."
            case .failure(let error): message = error.localizedDescription
            }
            store.announce(message)
        }
    }
}
