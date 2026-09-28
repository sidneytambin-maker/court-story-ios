import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject private var store: TennisStore
    @Binding var settings: AppSettings
    @State private var status = ""

    var body: some View {
        TennisForm {
            Section("Notification sounds") {
                NavigationLink { TennisSoundChoices(selection: savedSoundSelection) } label: {
                    Label("Tennis Sounds", systemImage: "speaker.wave.2")
                }
                .accessibilityValue(settings.sounds.selected.title)
                .accessibilityIdentifier("tennisSoundChoices")
                .accessibilityHint("Five short tennis sounds. Double tap a choice to select and preview it. Your choice also syncs to the Watch app.")
                Picker("Reminder sound", selection: $settings.sounds.reminders) {
                    ForEach(TennisReminderSound.allCases) { Text($0.rawValue).tag($0) }
                }
                .accessibilityIdentifier("reminderSoundMode")
                .accessibilityHint("iPhone reminders use this setting. Mirrored Apple Watch notification sounds are controlled by watchOS, not by the in-app sound preference.")
            }
            Section("In-app sounds") {
                Toggle("Save confirmations", isOn: $settings.sounds.savesEnabled)
                    .accessibilityIdentifier("saveSoundsToggle")
                    .accessibilityHint("Only deliberate activity saves, never each point or a background sync.")
                Toggle("Activity completed", isOn: $settings.sounds.completionsEnabled)
                    .accessibilityIdentifier("completionSoundsToggle")
                Toggle("Achievements", isOn: $settings.sounds.milestonesEnabled)
                    .accessibilityIdentifier("milestoneSoundsToggle")
                    .accessibilityHint("Plays once for newly earned activity badges after a deliberate save or completion. No sound on launch or background sync.")
            }
            Section("Reminders") {
                Toggle("Match reminders", isOn: $settings.matchRemindersEnabled)
                Toggle("Match result follow-ups", isOn: $settings.matchResultRemindersEnabled)
                Toggle("Training reminders", isOn: $settings.trainingRemindersEnabled)
                Toggle("Tournament reminders", isOn: $settings.tournamentRemindersEnabled)
                Toggle("Post-session reflection", isOn: $settings.postSessionRemindersEnabled)
                Toggle("Weekly summary", isOn: $settings.weeklySummaryEnabled)
                OrderedChoicePicker(title: "Reminder lead time", selection: $settings.reminderLeadMinutes, values: [15, 30, 60, 120, 1440]) { $0.durationText }
                OrderedChoicePicker(title: "Reflection delay", selection: $settings.postSessionDelayMinutes, values: [60, 120, 240]) { $0.durationText }
                Button("Allow iPhone notifications") {
                    Task {
                        let granted = await TennisNotificationService.shared.requestAuthorization()
                        store.updateSettings(settings)
                        status = granted ? "Notifications are allowed." : "Notifications were not allowed."
                        store.announce(status)
                    }
                }
            }
            if !status.isEmpty { Text(status) }
            Section("Sound credits") {
                Text("Five independent CC0 recordings, edited for Court Story.")
                Link("Bounce: Joseph SARDIN / LaSonotheque", destination: URL(string: "https://lasonotheque.org/balle-de-tennis-rebonds-s0584.html")!)
                Link("Racket strike: jacklilley", destination: URL(string: "https://freesound.org/people/jacklilley/sounds/338122/")!)
                Link("Racket swoosh: MIKEJONESBONES", destination: URL(string: "https://freesound.org/people/MIKEJONESBONES/sounds/511825/")!)
                Link("Ball can: tomschuetz", destination: URL(string: "https://freesound.org/people/tomschuetz/sounds/649763/")!)
                Link("Court applause: muse88", destination: URL(string: "https://freesound.org/people/muse88/sounds/490341/")!)
            }
        }
        .tennisThemedList()
        .navigationTitle("Notifications & Sounds")
        .onChange(of: settings) { _, _ in store.updateSettings(settings) }
    }

    private var savedSoundSelection: Binding<TennisSound> {
        Binding(get: { settings.sounds.selected }, set: { sound in
            // The parent form's onChange is inactive while its sound screen is open.
            settings.sounds.selected = sound
            store.updateSettings(settings)
        })
    }
}

struct TennisSoundChoices: View {
    @Binding var selection: TennisSound
    @State private var previewFailed = false
    var body: some View {
        TennisList {
            ForEach(TennisSound.allCases) { sound in
                Button {
                    selectAndPreview(sound)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill").font(.title2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sound.title).font(.headline)
                            if sound == .bounce { Text("Default").font(.caption) }
                        }
                        Spacer(minLength: 4)
                        if selection == sound { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(sound.title + (sound == .bounce ? ", default" : ""))
                .accessibilityValue(selection == sound ? "Selected" : "Not selected")
                .accessibilityHint("Selects and plays a preview. Respects silent mode and your volume. Double tap again to hear it again.")
                .accessibilityIdentifier("tennisSound." + sound.rawValue)
                .accessibilityAction(.default) { selectAndPreview(sound) }
            }
            if previewFailed { Text("Sound preview unavailable.").accessibilityIdentifier("soundPreviewFailed") }
        }
        .tennisThemedList()
        .navigationTitle("Tennis Sounds")
        .onDisappear { TennisSoundPlayer.shared.stop() }
    }

    private func selectAndPreview(_ sound: TennisSound) {
        selection = sound
        previewFailed = !TennisSoundPlayer.shared.preview(sound)
    }
}
