import SwiftUI

struct WatchCourtOnboardingView: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var draft = CourtSetupDraft.restore("Watch")
    @State private var error = ""
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        Form {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            if draft.step == 0 {
                ForEach([CourtRole.coach, .player]) { role in
                    Button {
                        draft.role = role; advance()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(role.welcome, systemImage: role == .coach ? "person.2.fill" : "figure.tennis")
                            Text(role.detail).font(.footnote)
                        }
                    }.accessibilityLabel(role.welcome).accessibilityHint(role.detail)
                        .accessibilityIdentifier("watchSetup" + role.rawValue)
                }
                Text("Already have a library? Open Court Story on your paired iPhone to sync it. Restore your own Apple backup on iPhone before starting a new library.")
                Button("Refresh from iPhone") { store.send(.requestSnapshot) }
            } else if draft.step == 1 {
                TextField("Name", text: $draft.player.name).accessibilityIdentifier("watchSetupName")
                TextField("Preferred name, optional", text: $draft.player.preferredName)
                CourtSportChoiceFields(selection: $draft.sport)
                Text("Add more sports or switch Coach and Player later in Sport and Player.")
            } else if draft.step == 2 {
                Picker("Tracking mode", selection: $draft.settings.trackingMode) {
                    ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("watchSetupMode")
                Text(draft.settings.trackingMode.description)
                Picker("Theme", selection: $draft.settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                NavigationLink("Optional Access Preferences") {
                    Form { CourtAccessFields(sport: draft.sport.sport, access: $draft.access) }
                        .navigationTitle("Access Preferences")
                }.accessibilityValue(draft.access.summary)
                if draft.role == .coach {
                    NavigationLink("Optional Coaching Profile") {
                        Form { CourtCoachCredentialsFields(credentials: $draft.coaching) }.navigationTitle("Coaching Profile")
                    }
                }
            } else {
                Text("\(draft.completedPlayer().displayName), \(draft.role.rawValue), \(draft.sport.name). \(draft.settings.trackingMode.rawValue) mode.")
                Text("Health access is optional and requested when you start your own workout. Your measurements are never recorded as an athlete's.")
                if store.snapshot.libraryID == nil || store.snapshot.courtProtocolVersion < 2 {
                    Text("Open the updated Court Story app on your paired iPhone once to connect this library. Your setup choices stay here.")
                    Button("Check iPhone Connection") { store.send(.requestSnapshot) }
                }
            }
            if !error.isEmpty { Text(error).accessibilityFocused($errorFocused).accessibilityIdentifier("watchSetupError") }
            if draft.step > 0 {
                Button(draft.step == 3 ? "Finish Setup" : "Continue") { continueSetup() }
                    .accessibilityIdentifier("watchSetupContinue")
                Button("Back") { draft.step -= 1; error = "" }
                Button("Cancel Setup", role: .cancel) { draft.step = 0; error = "" }
                    .accessibilityHint("Returns to welcome without losing your unsaved choices.")
            }
        }
        .id(draft.step).navigationTitle("Court Story").pickerStyle(.navigationLink)
        .onAppear { headingFocused = true }
        .onChange(of: draft) { _, value in value.persist("Watch") }
        .onChange(of: draft.step) { _, _ in headingFocused = true }
    }

    private var title: String {
        switch draft.step {
        case 0: "Welcome to Court Story"
        case 1: "Your \(draft.role.rawValue.lowercased()) profile"
        case 2: "Make it yours"
        default: "Ready for your court story"
        }
    }
    private func advance() { error = ""; draft.step += 1 }
    private func continueSetup() {
        if draft.completedPlayer().name.isBlank || !draft.sport.isValid {
            error = "Enter your name and choose a sport. Custom sports need their own name."; errorFocused = true; return
        }
        if let message = draft.access.validationMessage { error = message; errorFocused = true; return }
        if draft.step < 3 { advance(); return }
        var settings = draft.settings; settings.applyModeDefaults()
        if store.saveCourtMutation(.onboarding(draft.completedPlayer(), settings)) {
            CourtSetupDraft.clear("Watch")
            store.page = .today
        } else { error = store.lastAnnouncement; errorFocused = true }
    }
}
