import SwiftData
import SwiftUI

@main
struct CalorieTrackerApp: App {
    @State private var environment = AppEnvironment.makeForCurrentProcess()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.profileStore)
                .environment(\.mealScanner, environment.mealScanner)
                .environment(\.foodSearch, environment.foodSearch)
                .environment(\.launchOptions, environment.launchOptions)
        }
        .modelContainer(environment.modelContainer)
    }
}
