import SwiftUI

struct TennisChoiceList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        #if os(watchOS)
        // Keep short selection screens out of the Watch list's reentrant row-sizing path.
        ScrollView {
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        .buttonStyle(.bordered)
        #else
        TennisList { content }
        #endif
    }
}

struct TennisList<Content: View>: View {
    #if os(iOS)
    @EnvironmentObject private var store: TennisStore
    #endif
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        #if os(iOS)
        List { content.listRowBackground(store.data.settings.theme.palette.rowBackground) }.tennisThemedList()
        #else
        List { content }
        #endif
    }
}

struct TennisForm<Content: View>: View {
    #if os(iOS)
    @EnvironmentObject private var store: TennisStore
    #endif
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        #if os(iOS)
        Form { content.listRowBackground(store.data.settings.theme.palette.rowBackground) }.tennisThemedList()
        #else
        Form { content }
        #endif
    }
}
