import SwiftUI

// Keep the changing navigation dismissal environment out of an editor's destinations.
struct WatchSaveAndDismissButton: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: () -> Bool

    var body: some View {
        Button(title) {
            if save() { dismiss() }
        }
    }
}
