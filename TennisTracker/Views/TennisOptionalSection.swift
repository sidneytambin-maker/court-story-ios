import SwiftUI

/// Collapsing optional fields never resets their draft values.
struct TennisOptionalSection<Content: View>: View {
    let title: String
    let mode: TrackingMode
    let identifier: String
    let content: Content
    @State private var expanded: Bool

    init(_ title: String, mode: TrackingMode, identifier: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.mode = mode
        self.identifier = identifier
        self.content = content()
        _expanded = State(initialValue: mode != .basic)
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) { content } label: {
                Text(title).font(.body.weight(.medium))
            }
            .accessibilityIdentifier(identifier)
        }
        .onChange(of: mode) { _, value in expanded = value != .basic }
    }
}
