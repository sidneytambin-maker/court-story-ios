import SwiftUI

struct TennisTrackerRootView: View {
    @EnvironmentObject private var store: TennisStore
    @StateObject private var router = AppRouter()
    @State private var showConnect = false
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
                    if store.courtRole == .coach {
                        CourtCoachDashboard().tabItem { Label("Dashboard", systemImage: "chart.bar") }.tag("dashboard")
                        NavigationStack { CourtRosterView() }.tabItem { Label("Players", systemImage: "person.2") }.tag("players")
                        NavigationStack { CourtRecordHub() }.tabItem { Label("Record", systemImage: "plus.circle") }.tag("record")
                        NavigationStack { CourtProgressView() }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag("progress")
                    } else {
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
                    }

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag("settings")
                }
                .accessibilityIdentifier("mainTabView")
                .onChange(of: store.courtRole) { _, _ in router.selectedTab = "dashboard" }
                .toolbarBackground(store.data.settings.theme.palette.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
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
        #if DEBUG && targetEnvironment(simulator)
        .onAppear {
            if CourtConnectInvitationTestSupport.enabled,
               let index=ProcessInfo.processInfo.arguments.firstIndex(of:"-ui-testing-connect-link"),
               ProcessInfo.processInfo.arguments.indices.contains(index+1),
               let url=URL(string:ProcessInfo.processInfo.arguments[index+1]),
               CourtConnect.shared.receive(url), !store.needsOnboarding { showConnect=true }
        }
        #endif
        .onOpenURL { url in
            if CourtConnect.shared.receive(url) { if !store.needsOnboarding { showConnect=true } }
            else { router.open(url) }
        }
        .onChange(of:store.needsOnboarding) { _, needed in if !needed && !CourtConnect.shared.pendingCode.isEmpty { showConnect=true } }
        .task(id:scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if !store.needsOnboarding && CourtConnect.shared.isSignedIn { do { try await CourtConnect.shared.sync(store.data) } catch { CourtConnect.shared.status="Sync will retry. " + error.localizedDescription } }
                do { try await Task.sleep(for:.seconds(30)) } catch { return }
            }
        }
        .environmentObject(router)
        .onAppear { if UserDefaults.standard.bool(forKey:"CourtConnectOpenPending") && !store.needsOnboarding { UserDefaults.standard.removeObject(forKey:"CourtConnectOpenPending"); showConnect=true } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CourtConnectOpen"))) { _ in if !store.needsOnboarding { UserDefaults.standard.removeObject(forKey:"CourtConnectOpenPending"); showConnect=true } }
        .sheet(isPresented: $showConnect) { NavigationStack { CourtConnectView().toolbar { Button("Done") { showConnect = false } } }.environmentObject(store) }
        .sheet(item: $router.activityRoute) { route in TennisNotificationDestination(route: route).environmentObject(store) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { TennisSoundPlayer.shared.stop() }
            else if !store.needsOnboarding { router.openPendingIntentRoute(); CourtConnect.shared.changed(store.data) }
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
