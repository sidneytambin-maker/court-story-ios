import SwiftUI

struct TennisTrackerRootView: View {
    @EnvironmentObject private var store: TennisStore
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let error = store.storageError {
                NavigationStack {
                    TennisForm {
                        Text(error).accessibilityIdentifier("libraryRecoveryMessage")
                        Button("Try Again") { store.retryLoading() }
                    }.navigationTitle("Library Unavailable")
                }
            } else if store.needsOnboarding {
                OnboardingView()
            } else {
                TabView(selection: $router.selectedTab) {
                    DashboardView()
                        .tabItem {
                            Label("Dashboard", systemImage: "chart.bar")
                        }
                        .tag("dashboard")

                    MatchesView()
                        .tabItem {
                            Label("Matches", systemImage: "list.bullet.rectangle")
                        }
                        .tag("matches")

                    TournamentsView()
                        .tabItem {
                            Label("Tournaments", systemImage: "trophy")
                        }
                        .tag("tournaments")

                    TrainingView()
                        .tabItem {
                            Label("Training", systemImage: "figure.tennis")
                        }
                        .tag("training")

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag("settings")
                }
                .accessibilityIdentifier("mainTabView")
                .toolbarBackground(store.data.settings.theme.palette.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .onOpenURL { url in
                    router.open(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .tennisTrackerOpenURL)) { notification in
                    router.openPendingIntentRoute()
                }
                .onAppear {
                    router.openPendingIntentRoute()
                }
                #if DEBUG && targetEnvironment(simulator)
                .overlay(alignment: .bottomTrailing) {
                    if ProcessInfo.processInfo.arguments.contains("-test-notification-warm") {
                        Button("Open Test Reminder") {
                            if let route = TennisNotificationTestSupport.route(training: store.data.trainingSessions, matches: store.data.matches, tournaments: store.data.tournaments) {
                                TennisNotificationInbox.enqueue(route.url)
                                NotificationCenter.default.post(name: .tennisTrackerOpenURL, object: route.url)
                            }
                        }.accessibilityIdentifier("openTestReminder")
                    }
                }
                #endif
            }
        }
        .environmentObject(router)
        .sheet(item: $router.activityRoute) { route in TennisNotificationDestination(route: route).environmentObject(store) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { TennisSoundPlayer.shared.stop() }
            else if !store.needsOnboarding { router.openPendingIntentRoute() }
        }
        .tint(store.data.settings.theme.accentColor)
        .preferredColorScheme(store.data.settings.theme.preferredColorScheme)
    }
}

extension AppTheme {
    var accentColor: Color {
        palette.accent
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .tennis, .classic: return .light
        case .highContrast: return .dark
        default: return nil
        }
    }
}
