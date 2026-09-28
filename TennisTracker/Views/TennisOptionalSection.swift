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
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title).font(.body.weight(.medium))
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides optional details without clearing them." : "Shows optional details.")
            .accessibilityIdentifier(identifier)
            // Keep the header identifier off the container so children retain their own identities.
            if expanded { content }
        }
        .onChange(of: mode) { _, value in expanded = value != .basic }
    }
}
