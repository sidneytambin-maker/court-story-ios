import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var draft = CourtSetupDraft.restore("iPhone")
    @State private var message = ""
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        NavigationStack {
            TennisForm {
                Section {
                    Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    if draft.step == 0 { Text("Your sport. Your progress. Your story.") }
                }
                if draft.step == 0 {
                    Section {
                        ForEach([CourtRole.coach, .player]) { role in
                            Button {
                                draft.role = role; advance()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(role.welcome, systemImage: role == .coach ? "person.2.fill" : "figure.tennis").font(.headline)
                                    Text(role.detail).font(.body)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                            .accessibilityLabel(role.welcome)
                            .accessibilityHint(role.detail)
                            .accessibilityIdentifier(role == .player ? "setupProfileButton" : "setupCoachButton")
                        }
                        NavigationLink("Restore My Private Backup") { PrivateBackupView() }
                            .accessibilityHint("Restore only your own Apple backup. No other person's library is included.")
                            .accessibilityIdentifier("restorePrivateBackupLink")
                        NavigationLink("Privacy Policy") { TennisPrivacyPolicyView() }
                            .accessibilityIdentifier("onboardingPrivacyPolicyLink")
                    }
                } else if draft.step == 1 {
                    Section("Your profile") {
                        TextField("Name", text: $draft.player.name).textContentType(.name).accessibilityIdentifier("playerNameField")
                        TextField("Preferred name, optional", text: $draft.player.preferredName).textContentType(.nickname).accessibilityIdentifier("preferredNameField")
                        TextField("Club or organisation, optional", text: $draft.player.club).accessibilityIdentifier("clubField")
                        CourtSportChoiceFields(selection: $draft.sport)
                    }
                    Section {
                        Text("You can add more sports and switch between Coach and Player later in Settings. Each sport keeps its own preferences and records.")
                    }
                } else if draft.step == 2 {
                    Section("Recording detail") {
                        Picker("Tracking mode", selection: $draft.settings.trackingMode) {
                            ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("trackingModePicker")
                        Text(draft.settings.trackingMode.description)
                        Picker("Theme", selection: $draft.settings.theme) { ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) } }
                        NavigationLink("Optional access preferences") {
                            Form { CourtAccessFields(sport: draft.sport.sport, access: $draft.access) }.navigationTitle("Access preferences")
                        }.accessibilityValue(draft.access.summary)
                        if draft.role == .coach {
                            NavigationLink("Optional coaching profile") {
                                Form { CourtCoachCredentialsFields(credentials: $draft.coaching) }.navigationTitle("Coaching profile")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("\(draft.completedPlayer().displayName), \(draft.role.rawValue), \(draft.sport.name). \(draft.settings.trackingMode.rawValue) mode.")
                        Text("Your library starts empty. Add people, places and more sports in Settings whenever you are ready.")
                        Text("Your paired Apple Watch can record activities too. Health access and notifications are optional and requested only when you choose to use them.")
                    }
                }
                if !message.isEmpty {
                    Section { Text(message).foregroundStyle(.red).accessibilityFocused($errorFocused).accessibilityIdentifier("onboardingError") }
                }
                if draft.step > 0 {
                    Section {
                        HStack {
                            Button("Back") { message = ""; draft.step -= 1; focusHeading() }.accessibilityIdentifier("onboardingBackButton")
                            Spacer()
                            Button(draft.step == 3 ? "Finish setup" : "Continue") { continueTapped() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier(draft.step == 3 ? "onboardingFinishButton" : "onboardingContinueButton")
                        }
                        Button("Cancel setup", role: .cancel) { draft.step = 0; message = ""; focusHeading() }
                            .accessibilityHint("Returns to the welcome screen. Your unsaved setup choices are retained.")
                    }
                }
            }
            .id(draft.step)
            .navigationTitle("Court Story")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focusHeading() }
            .onChange(of: draft) { _, value in value.persist("iPhone") }
        }
        .tint(draft.settings.theme.accentColor)
    }

    private var title: String {
        switch draft.step {
        case 0: return "Welcome to Court Story"
        case 1: return "Your \(draft.role.rawValue.lowercased()) profile"
        case 2: return "Make it yours"
        default: return "Ready for your court story"
        }
    }
    private func advance() { draft.step += 1; message = ""; focusHeading() }
    private func continueTapped() {
        if draft.step == 1 && (draft.completedPlayer().name.isBlank || !draft.sport.isValid) {
            message = "Enter your name and choose a sport. Custom sports need their own name."; errorFocused = true; return
        }
        if let error = draft.access.validationMessage { message = error; errorFocused = true; return }
        if draft.step < 3 { advance(); return }
        var settings = draft.settings; settings.applyModeDefaults()
        if store.completeOnboarding(player: draft.completedPlayer(), settings: settings) { CourtSetupDraft.clear("iPhone") }
        else { message = store.lastAnnouncement; errorFocused = true }
    }
    private func focusHeading() {
        headingFocused = false
        DispatchQueue.main.async { headingFocused = true }
    }
}
