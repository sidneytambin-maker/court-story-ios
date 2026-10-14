import SwiftUI

enum TennisPrivacyPolicy {
    static let updated = "14 October 2026"
    static let website = URL(string: "https://sidneytambin-maker.github.io/court-story-ios/privacy.html")!
    static let summary = "Your sporting library belongs to you. Local tracking works without an account. Optional Court Story Connect shares only the sporting information you approve with connected coaches."

    struct Topic: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    static let topics: [Topic] = [
        Topic(id: "connect", title: "Optional Court Story Connect", text: "Court Story works without an online account. Connect is optional. No email, password or account registration is required. Enabling Connect does not upload your library. After you approve uploads and a coach connection, permitted sporting records are stored in the Supabase service and made available to that coach. Each player and sport has independent permissions. Share all includes sporting history and future records, but excludes private records, Health measurements, raw workouts and media. Notes, reflections and goals have separate controls. Do not include Health details or other sensitive information in text you choose to share. Court Story does not sell data or use advertising or analytics."),
        Topic(id: "connect-notifications", title: "Connect identity and notifications", text: "Connect stores a randomly assigned private device identity, your chosen display name and sharing settings. It does not ask for your email or password. The connection credentials are stored securely on this device; clearing the app or moving to another device may require creating fresh coach connections. Optional push notifications use an installation identifier and provider token: Apple Push Notification service on iPhone and Firebase Cloud Messaging on Android. A sharing confirmation names your coach. Manage push, connection requests, sharing confirmations and feedback alerts in Settings at any time. Phone notification settings also apply. In-app confirmations remain available when push is off."),
        Topic(id: "connect-delete", title: "Managing and deleting online sharing", text: "Use Connect settings to pause or revoke each coach immediately on the server. Previously saved or exported copies cannot necessarily be erased remotely. Delete connections and shared cloud data removes your online device identity, records, connections, feedback and device registrations while preserving the independent local library. In-app notifications are retained for 90 days and audit events for 365 days; expired invitations are removed seven days after expiry. Record deletion removes its shared content and keeps only the identifiers needed to prevent old copies returning until you delete your connections and cloud data."),
        Topic(id: "library", title: "Your tennis library", text: "Court Story stores the profiles, people, places, activities, notes, goals and preferences you enter on your device. These records power your history, statistics and achievements. Only enter information about other people that you are entitled to keep. New testers receive an empty library, never another player's records."),
        Topic(id: "watch", title: "Your paired Apple Watch", text: "Your iPhone and paired Apple Watch exchange your tennis records and settings using Apple's WatchConnectivity service. The Watch shares a local summary with its complication extension. This is not a public feed or a developer-operated server. Lock-screen notifications and watch-face complications can display activity details; you control their visibility in Apple's settings."),
        Topic(id: "health", title: "Optional Apple Health access", text: "When you choose a Health workout on Apple Watch, Court Story requests permission to read and write tennis workouts and supported measurements: heart rate, active energy, walking or running distance, and steps. It uses these to track your workout and saves its duration, available measurements and Health workout identifier with the session. That summary can sync to your paired iPhone. Basic tennis logging works without Health access. Health information is not sold or used for advertising. You can change access in Apple's Health and privacy settings."),
        Topic(id: "calendar", title: "Calendar and reminders", text: "Calendar access is optional. When you ask to add an activity, its details are sent to your selected Apple Calendar. Calendar sharing and cloud synchronisation follow your Apple account and calendar settings. Local reminders use the tennis dates and preferences you choose; notification delivery is managed by Apple."),
        Topic(id: "backup", title: "Private backups and sharing", text: "Export Private Backup creates a readable JSON file containing your tennis library, including saved workout summaries, but not the Apple Health database. The file is not password-encrypted by Court Story. You choose its destination and who can access it. Files saved to a cloud provider follow that provider's privacy settings. Keep exports private and delete copies you no longer need. Device backups are managed separately by your operating system."),
        Topic(id: "delete", title: "Keeping and deleting records", text: "Records remain in your library until you edit or delete them. Changes sync to your paired Watch. Deletion identifiers are retained to prevent old synced records from returning. Deleting a tennis record does not delete a previously saved Apple Health workout, Calendar event or exported backup; manage those separately in Health, Calendar or Files. Removing the app can remove its local library, so export any records you want to keep first."),
        Topic(id: "beta", title: "TestFlight and feedback", text: "Apple processes TestFlight installation, usage, crash and feedback information under its TestFlight privacy terms. The developer can receive the beta feedback and diagnostic information Apple makes available to developers. Your whole tennis library is not automatically sent as feedback. Check screenshots and attachments for personal or Health details before sending them."),
        Topic(id: "contact", title: "Privacy questions", text: "For this beta, contact the developer using Send Beta Feedback on Court Story's page in TestFlight. Ask privacy questions without attaching your library or Health information. Changes to this policy will be dated and published in the app and on the policy website. The website is hosted by GitHub Pages; GitHub processes website requests under its own privacy statement.")
    ]
}

struct TennisPrivacyPolicyView: View {
    var body: some View {
        TennisList {
            Section {
                Text(TennisPrivacyPolicy.summary)
                    .accessibilityIdentifier("privacyPolicySummary")
                Text("Updated " + TennisPrivacyPolicy.updated)
            }
            ForEach(TennisPrivacyPolicy.topics) { topic in
                Section {
                    Text(topic.text)
                        .accessibilityIdentifier("privacyPolicyTopic." + topic.id)
                } header: {
                    Text(topic.title).accessibilityAddTraits(.isHeader)
                }
            }
            #if os(iOS)
            Section {
                Link("Privacy Policy Website", destination: TennisPrivacyPolicy.website)
                    .accessibilityHint("Opens the public policy in your browser. The policy above is also available offline.")
                Link("Apple TestFlight Privacy", destination: URL(string: "https://www.apple.com/legal/privacy/data/en/test-flight/")!)
                Link("GitHub Privacy Statement", destination: URL(string: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement")!)
            }
            #endif
        }
        .navigationTitle("Privacy Policy")
    }
}
