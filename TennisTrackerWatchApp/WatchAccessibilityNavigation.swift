import SwiftUI

enum WatchAccessibilityNavigation {
    static var testingEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-watch-accessibility-navigation")
        #else
        false
        #endif
    }
}

struct WatchPageSelector: View {
    @EnvironmentObject private var store: WatchTennisStore
    @State private var showingPages = false
    @State private var previewFailed = false
    var body: some View {
        Button { showingPages = true } label: {
            Image(systemName: "square.grid.2x2")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(TennisSportStyle.ink)
        }
        .accessibilityLabel("Menu")
        .accessibilityIdentifier("watchScreenMenu")
        .accessibilityHint("Opens app screens, achievements, sound preview and privacy policy. You can also choose a screen using Actions.")
        .sheet(isPresented: $showingPages) {
            NavigationStack {
                List {
                    ForEach(TennisWatchPage.allCases) { page in
                        Button(page.rawValue) { store.page = page; showingPages = false }
                    }
                    NavigationLink("Achievements") { TennisAchievementsView(achievements: store.snapshot.achievements) }
                        .accessibilityIdentifier("watchMenuAchievements")
                    Button("Preview Tennis Sound") { previewFailed = !TennisSoundPlayer.shared.preview(store.snapshot.settings.sounds.selected) }
                        .accessibilityValue(store.snapshot.settings.sounds.selected.title)
                        .accessibilityHint("Previews the sound chosen in iPhone Settings, Notifications and Sounds. Respects silent mode and volume.")
                        .accessibilityIdentifier("watchPreviewTennisSound")
                    if previewFailed { Text("Sound preview unavailable.").accessibilityIdentifier("watchSoundPreviewFailed") }
                    NavigationLink("Privacy Policy") { TennisPrivacyPolicyView() }
                        .accessibilityIdentifier("watchPrivacyPolicyLink")
                }.navigationTitle("Menu")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPages = false } } }
            }
        }
        .accessibilityValue("Current screen: \(store.page.rawValue)")
        .accessibilityActions {
            ForEach(TennisWatchPage.allCases) { page in Button(page.rawValue) { store.page = page } }
        }
    }
}
