import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var store: TennisStore
    @State private var step = 0
    @State private var player: PlayerProfile = {
        var value = PlayerProfile()
        value.sightLevel = .notKnown
        value.bCategory = "Not known"
        value.playerMode = .standardTennis
        return value
    }()
    @State private var settings = AppSettings()
    @State private var setup = TennisSetup()
    @State private var people: [PlayerProfile] = []
    @State private var notificationMessage = ""
    @State private var requestingNotifications = false
    @State private var validationMessage = ""
    @AccessibilityFocusState private var focusedHeading: Bool
    @AccessibilityFocusState private var focusedValidation: Bool

    var body: some View {
        NavigationStack {
            TennisForm {
                Section {
                    Text(title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedHeading)
                    Text(subtitle)
                }

                switch step {
                case 0:
                    welcomeStep
                case 1:
                    identityStep
                case 2:
                    tennisStep
                case 3:
                    preferencesStep
                case 4:
                    peopleAndPlacesStep
                case 5:
                    Section {
                        Text("Apple Watch is optional. Your paired Watch receives only your tennis library. You can track training, finish activities and score matches on your wrist.")
                        Text("For this beta, install the companion from the Watch app on your iPhone after installing Court Story through TestFlight.")
                    }
                case 6:
                    notificationStep
                case 7:
                    Section {
                        Text("Health integration is optional. When you explicitly choose a Health workout on Apple Watch, Apple asks for permission to record the workout and read supported measurements such as heart rate and distance.")
                        Text("No Health permission is requested during setup. You can use tennis tracking without Health access.")
                    }
                default:
                    Section {
                        Text("Welcome, \(player.displayName). Your library starts with no matches, training sessions or tournaments.")
                        Text("Your profile and the people and places you chose are ready. You can add or change them later in Tennis Setup.")
                    }
                }

                if !validationMessage.isBlank {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Validation message")
                            .accessibilityValue(validationMessage)
                            .accessibilityFocused($focusedValidation)
                    }
                }

                Section {
                    HStack {
                        if step > 0 {
                            Button("Back") {
                                validationMessage = ""
                                step -= 1
                                focusHeading()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("onboardingBackButton")
                        }
                        Spacer()
                        Button(step == 8 ? "Finish setup" : (step == 4 ? "Continue or Skip" : step == 6 && notificationMessage.isEmpty ? "Not Now" : "Continue")) {
                            continueTapped()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(requestingNotifications)
                        .accessibilityIdentifier(step == 8 ? "onboardingFinishButton" : "onboardingContinueButton")
                    }
                }
            }
            .id(step)
            .navigationTitle("Setup")
            .onAppear {
                focusHeading()
            }
        }
        .tint(settings.theme.accentColor)
    }

    private var welcomeStep: some View {
        Section {
            Text("Court Story records matches, tournaments, training, and progress. Setup creates your first real player profile. No demo records will be added.")
            Button("Set up my player profile") {
                step = 1
                focusHeading()
            }
            .accessibilityIdentifier("setupProfileButton")
            NavigationLink("Restore My Private Backup") { PrivateBackupView() }
                .accessibilityHint("Optional. Only for moving your own existing records. New testers should set up a new player profile.")
                .accessibilityIdentifier("restorePrivateBackupLink")
            NavigationLink("Privacy Policy") { TennisPrivacyPolicyView() }
                .accessibilityIdentifier("onboardingPrivacyPolicyLink")
        }
    }

    private var identityStep: some View {
        Section("Player") {
            TextField("Player name", text: $player.name)
                .textContentType(.name)
                .accessibilityIdentifier("playerNameField")
            TextField("Preferred name", text: $player.preferredName)
                .textContentType(.nickname)
                .accessibilityIdentifier("preferredNameField")
            TextField("Club", text: $player.club)
                .accessibilityIdentifier("clubField")
        }
    }

    private var tennisStep: some View {
        Section("Tennis Type") {
            Picker("Player type", selection: $player.playerMode) {
                ForEach(PlayerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityIdentifier("playerModePicker")

                Picker("Sight classification", selection: $player.sightLevel) {
                    ForEach(SightLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .accessibilityIdentifier("sightLevelPicker")
                .accessibilityHint("Optional. Choose Not known to leave this unspecified.")
            Picker("Handedness", selection: $player.playingHand) {
                Text("Not known").tag("")
                Text("Right-handed").tag("Right-handed")
                Text("Left-handed").tag("Left-handed")
                Text("Both hands").tag("Both hands")
            }
            Picker("Usual bounce allowance", selection: $player.bounceAllowance) {
                Text("Use match rules").tag(Optional<Int>.none)
                ForEach(1...3, id: \.self) { value in Text("\(value)").tag(Optional(value)) }
            }

            Picker("Preferred match type", selection: $settings.defaultMatchType) {
                ForEach(MatchKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .accessibilityIdentifier("defaultMatchTypePicker")
            Picker("Default match format", selection: $player.defaultMatchFormat) {
                ForEach(MatchFormat.allCases) { format in Text(format.label).tag(format) }
            }.accessibilityIdentifier("onboardingMatchFormatPicker")
        }
    }

    private var peopleAndPlacesStep: some View {
        Group {
            Section("Coaches") {
                ForEach($setup.coaches) { $coach in TextField("Coach name", text: $coach.name) }
                Button("Add Coach", systemImage: "plus") { setup.coaches.append(TennisCoach()) }
            }
            Section("Players and Doubles Partners") {
                ForEach($people) { $person in
                    TextField("Player name", text: $person.name)
                    Toggle("Regular doubles partner", isOn: $person.isRegularPartner)
                        .accessibilityLabel("Regular doubles partner, \(person.name.isBlank ? "new player" : person.name)")
                }
                Button("Add Player", systemImage: "person.badge.plus") { addPerson(regularPartner: false) }
                Button("Add Doubles Partner", systemImage: "person.2.fill") { addPerson(regularPartner: true) }
            }
            Section("Venues") {
                ForEach($setup.venues) { $venue in TextField("Venue name", text: $venue.name) }
                Button("Add Venue", systemImage: "plus") { setup.venues.append(TennisVenue()) }
            }
            Section("Locations and Regular Tournaments") {
                ForEach($setup.locations) { $location in TextField("Location name", text: $location.name) }
                Button("Add Location", systemImage: "mappin.and.ellipse") { setup.locations.append(TennisLocation()) }
                ForEach($setup.tournamentTemplates) { $tournament in TextField("Regular tournament name", text: $tournament.name) }
                Button("Add Regular Tournament", systemImage: "trophy") { setup.tournamentTemplates.append(TennisTournamentTemplate()) }
                    .accessibilityHint("Adds a reusable tournament name. It does not create a tournament event or count toward achievements.")
            }
        }
    }

    private func addPerson(regularPartner: Bool) {
        var person = PlayerProfile()
        person.sightLevel = .notKnown
        person.bCategory = "Not known"
        person.playerMode = .standardTennis
        person.isRegularPartner = regularPartner
        people.append(person)
    }

    private var notificationStep: some View {
        Section {
            Text("Optional reminders can bring you back to a scheduled match, training session or tournament. Opening a reminder takes you to that activity. You can change reminders and sounds in Settings.")
            Button("Allow Notifications") {
                requestingNotifications = true
                Task {
                    let allowed = await TennisNotificationService.shared.requestAuthorization()
                    settings.matchRemindersEnabled = allowed
                    settings.trainingRemindersEnabled = allowed
                    settings.tournamentRemindersEnabled = allowed
                    notificationMessage = allowed ? "Scheduled activity reminders are enabled." : "Notifications are not enabled. You can continue without them."
                    requestingNotifications = false
                    store.announce(notificationMessage)
                }
            }.disabled(requestingNotifications)
            if !notificationMessage.isEmpty { Text(notificationMessage) }
        }
    }

    private var preferencesStep: some View {
        Section("Preferences") {
            Picker("Tracking mode", selection: $settings.trackingMode) {
                ForEach(TrackingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityIdentifier("trackingModePicker")
            Text(settings.trackingMode.description)

            NumberChoicePicker(title: "Season", value: $settings.defaultSeason, range: 2000...2100)
                .accessibilityIdentifier("seasonPicker")

            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .accessibilityIdentifier("themePicker")

            Picker("Score announcements", selection: $settings.scoreAnnouncementMode) {
                ForEach(ScoreAnnouncementMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityIdentifier("announceScoresPicker")
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
                .accessibilityIdentifier("hapticsToggle")
        }
    }

    private var title: String {
        switch step {
        case 0: return "Welcome to Court Story"
        case 1: return "Set Up Your Player"
        case 2: return "Choose Tennis Details"
        case 3: return "Choose Preferences"
        case 4: return "People and Places"
        case 5: return "Your Apple Watch"
        case 6: return "Activity Reminders"
        case 7: return "Optional Health Workouts"
        default: return "Ready for Tennis"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "A fresh, private tracker for your iPhone."
        case 1: return "Only the player name is required."
        case 2: return "These choices set sensible defaults for matches and scoring."
        case 3: return "You can change these later in Settings."
        case 4: return "Optional. Add your own people and venues, or skip this step."
        case 5: return "Use iPhone alone or with your paired Watch."
        case 6: return "Allow reminders now, or choose Not Now."
        case 7: return "You decide whether to use Health."
        default: return "Your own tennis, with no demo records."
        }
    }

    private func continueTapped() {
        validationMessage = ""
        if step == 0 {
            step = 1
            focusHeading()
            return
        }
        if step == 1 && player.name.isBlank && player.preferredName.isBlank {
            validationMessage = "Enter a player name or preferred name before continuing."
            focusedValidation = true
            UIAccessibility.post(notification: .announcement, argument: validationMessage)
            return
        }
        if step < 8 {
            step += 1
            focusHeading()
            return
        }
        finish()
    }

    private func finish() {
        if player.name.isBlank {
            player.name = player.preferredName
        }
        if player.preferredName.isBlank {
            player.preferredName = player.name
        }
        player.trackingMode = settings.trackingMode
        player.preferredMatchType = settings.defaultMatchType.rawValue
        player.bCategory = player.sightLevel.label
        settings.applyModeDefaults()
        settings.announceScores = settings.scoreAnnouncementMode != .off
        setup.coaches.removeAll { $0.name.isBlank }
        setup.venues.removeAll { $0.name.isBlank }
        setup.locations.removeAll { $0.name.isBlank }
        setup.tournamentTemplates.removeAll { $0.name.isBlank }
        if !store.completeOnboarding(player: player, settings: settings, setup: setup, additionalPlayers: people.filter { !$0.name.isBlank }) {
            validationMessage = store.lastAnnouncement
            focusedValidation = true
        }
    }

    private func focusHeading() {
        focusedHeading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedHeading = true
        }
    }
}
