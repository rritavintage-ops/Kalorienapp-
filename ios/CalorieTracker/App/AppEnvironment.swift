import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Launch arguments used by the UI tests to get a hermetic, deterministic app.
struct LaunchOptions: Equatable {
    /// In-memory database, isolated defaults, mock scanner and mock food search.
    var isUITesting = false
    /// Start with a completed profile instead of onboarding.
    var skipsOnboarding = false
    /// Insert a few example meals for today and the previous days.
    var seedsSampleData = false

    init(isUITesting: Bool = false, skipsOnboarding: Bool = false, seedsSampleData: Bool = false) {
        self.isUITesting = isUITesting
        self.skipsOnboarding = skipsOnboarding
        self.seedsSampleData = seedsSampleData
    }

    init(arguments: [String]) {
        isUITesting = arguments.contains("-ui-testing")
        skipsOnboarding = arguments.contains("-skip-onboarding")
        seedsSampleData = arguments.contains("-sample-data")
    }
}

/// Composition root: builds the long-lived dependencies once at launch.
final class AppEnvironment {
    let launchOptions: LaunchOptions
    let modelContainer: ModelContainer
    let profileStore: ProfileStore
    let mealScanner: any MealScanning
    let foodSearch: any FoodSearching

    private static let logger = Logger(subsystem: "CalorieTracker", category: "AppEnvironment")

    init(
        launchOptions: LaunchOptions,
        modelContainer: ModelContainer,
        profileStore: ProfileStore,
        mealScanner: any MealScanning,
        foodSearch: any FoodSearching
    ) {
        self.launchOptions = launchOptions
        self.modelContainer = modelContainer
        self.profileStore = profileStore
        self.mealScanner = mealScanner
        self.foodSearch = foodSearch
    }

    static func makeForCurrentProcess() -> AppEnvironment {
        make(launchOptions: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))
    }

    static func make(launchOptions: LaunchOptions) -> AppEnvironment {
        if launchOptions.isUITesting {
            let defaults = UserDefaults(suiteName: "CalorieTracker.UITests") ?? .standard
            defaults.removePersistentDomain(forName: "CalorieTracker.UITests")
            let profileStore = ProfileStore(defaults: defaults)
            if launchOptions.skipsOnboarding {
                profileStore.save(.default)
            }
            let container = makeContainer(inMemory: true)
            if launchOptions.seedsSampleData {
                let context = ModelContext(container)
                SampleData.insert(into: context)
                try? context.save()
            }
            return AppEnvironment(
                launchOptions: launchOptions,
                modelContainer: container,
                profileStore: profileStore,
                mealScanner: MockMealScanner(),
                foodSearch: MockFoodSearch()
            )
        }

        return AppEnvironment(
            launchOptions: launchOptions,
            modelContainer: makeContainer(inMemory: false),
            profileStore: ProfileStore(defaults: .standard),
            mealScanner: RemoteMealScanService.fromBundle() ?? UnavailableMealScanner(),
            foodSearch: OpenFoodFactsService()
        )
    }

    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([FoodEntry.self])
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never crash on launch: fall back to an in-memory store so the app stays usable.
            logger.error("Failed to open the persistent store: \(error.localizedDescription, privacy: .public)")
            do {
                return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            } catch {
                fatalError("Unable to create even an in-memory model container: \(error)")
            }
        }
    }
}

// MARK: - Environment values

private struct MealScannerKey: EnvironmentKey {
    static let defaultValue: any MealScanning = UnavailableMealScanner()
}

private struct FoodSearchKey: EnvironmentKey {
    static let defaultValue: any FoodSearching = MockFoodSearch()
}

private struct LaunchOptionsKey: EnvironmentKey {
    static let defaultValue = LaunchOptions()
}

extension EnvironmentValues {
    var mealScanner: any MealScanning {
        get { self[MealScannerKey.self] }
        set { self[MealScannerKey.self] = newValue }
    }

    var foodSearch: any FoodSearching {
        get { self[FoodSearchKey.self] }
        set { self[FoodSearchKey.self] = newValue }
    }

    var launchOptions: LaunchOptions {
        get { self[LaunchOptionsKey.self] }
        set { self[LaunchOptionsKey.self] = newValue }
    }
}
