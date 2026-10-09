import SwiftUI

#if DEBUG && targetEnvironment(simulator)
@MainActor
enum WatchNavigationDiagnostics {
    private static var counts: [String: Int] = [:]

    static func trace(_ name: String, changes: () -> Void) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-watch") else { return }
        let count = counts[name, default: 0]
        counts[name] = count + 1
        // Bound diagnostic output even if a SwiftUI update cycle never settles.
        if count < 20 {
            print("Watch navigation update: \(name), \(count)")
            changes()
        }
    }
}
#endif
