import SwiftUI
import SwiftData

@main
struct ChildGrowthTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Child.self, GrowthMeasurement.self])
    }
}

/// @AppStorage keys shared across views.
enum SettingsKeys {
    static let unitSystem = "unitSystem"
    static let useCorrectedAge = "useCorrectedAge"
}
