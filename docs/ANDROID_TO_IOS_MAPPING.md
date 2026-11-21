# Android → iOS mapping

Reference project: [philipplackner/CalorieTracker](https://github.com/philipplackner/CalorieTracker)
(Kotlin, Jetpack Compose, Hilt, Room, Retrofit/Moshi, multi-module clean architecture).

The iOS app keeps the same functional core (onboarding → personal calorie goal → per-meal food
diary with macros → food search) and adds the AI photo scanner, a History tab and a Profile tab.
No Android library was ported; every piece uses the native Apple equivalent.

## Module mapping

| Android module | Responsibility | iOS equivalent |
| --- | --- | --- |
| `app` (`MainActivity`, `navigation/Route`) | Entry point, NavHost, onboarding vs. tracker start destination | `ios/CalorieTracker/App/` — `CalorieTrackerApp` (`@main`), `RootView` (onboarding vs. tabs), `MainTabView` (Home / History / Profile) |
| `core` (domain models, `Preferences`, `FilterOutDigits`) | `Gender`, `ActivityLevel`, `GoalType`, `UserInfo`, SharedPreferences | `CalorieCore` package: `UserProfile.swift`, `NumberInput.swift`; app: `Data/ProfileStore.swift` (UserDefaults, JSON-encoded) |
| `core-ui` (`Color`, `Dimensions`) | Theme, spacing | `ios/CalorieTracker/Design/` — `Theme`, `CalorieRing`, `MacroProgressBar`, card styles |
| `onboarding/onboarding_domain` (`ValidateNutrients`) | Validate macro split sums to 100 % | `CalorieCore/MacroRatios.swift` (`MacroRatioValidator`) |
| `onboarding/onboarding_presentation` (Welcome, Gender, Age, Height, Weight, Activity, Goal, NutrientGoal screens + ViewModels) | Step-by-step questionnaire | `Features/Onboarding/` — one `OnboardingView` driven by an `OnboardingStep` enum (same 8 steps + a summary step) |
| `tracker/tracker_domain` (`TrackedFood`, `TrackableFood`, `MealType`, use cases) | Business rules: track food, calculate meal nutrients, BMR/goal | `CalorieCore`: `MealType`, `FoodDraft`, `NutritionFacts`, `NutritionCalculator`, `DailySummary`, `HistoryAggregator` |
| `tracker/tracker_data` (Room `TrackerDatabase`/`TrackerDao`, Retrofit `OpenFoodApi`, mappers) | Persistence + OpenFoodFacts API | SwiftData `FoodEntry` model (`Data/FoodEntry.swift`), `Services/FoodSearchService.swift` (`URLSession`), `CalorieCore/OpenFoodFacts.swift` (DTOs, mapping, plausibility filter) |
| `tracker/tracker_presentation` (TrackerOverview, Search, components) | Daily overview with nutrient header, expandable meals, search & track | `Features/Home/` (dashboard + ring), `Features/Diary/` (`DayLogView`, meal sections, entry editor), `Features/Search/` |
| — (new) | AI photo scanner | `Features/Scanner/` (camera, photo library, review/edit) + `Services/MealScanService.swift` + `backend/` (Cloudflare Worker → Claude vision) |
| — (new) | History | `Features/History/` (weekly chart with Swift Charts, logged days, day detail) |
| — (new) | Profile | `Features/Profile/` (edit body data, activity, goal, macro split, custom goal, reset) |

## Technology mapping

| Android | iOS |
| --- | --- |
| Jetpack Compose | SwiftUI |
| ViewModel + `mutableStateOf` | `@Observable` models + `@State` |
| Hilt DI | SwiftUI `Environment` values (`mealScanner`, `foodSearch`) and an `AppEnvironment` composition root |
| Room (`TrackedFoodEntity`, `Flow` queries) | SwiftData (`@Model FoodEntry`, `@Query` with `#Predicate` on a day range) |
| SharedPreferences | `UserDefaults` (`ProfileStore`) |
| Retrofit + Moshi | `URLSession` + `Codable` |
| Coil (`AsyncImage` of product thumbnails) | SwiftUI `AsyncImage` |
| Compose Navigation (string routes) | `NavigationStack`, `TabView`, sheets |
| Snackbar `UiEvent`s | Inline error states / alerts |
| JUnit + Truth + MockK, Compose UI tests | XCTest (package tests, app unit tests on the simulator, XCUITest end-to-end tests) |

## Data model mapping

| Android `TrackedFood` / `TrackedFoodEntity` | iOS `FoodEntry` (SwiftData) |
| --- | --- |
| `name` | `name` |
| `carbs`, `protein`, `fat`, `calories` (ints for the portion) | `carbsPer100g`, `proteinPer100g`, `fatPer100g`, `caloriesPer100g` (densities) + `grams`; portion values are computed, so editing the amount rescales them |
| `amount` (grams) | `grams` |
| `mealType` (`"breakfast"`…) | `mealTypeRaw` (`MealType` raw value, same strings) |
| `dayOfMonth` / `month` / `year` | `date` (`Date`; day queries use `[startOfDay, nextDay)`) |
| `imageUrl` | `imageURLString` (search results) / `photoData` (scanner thumbnail, external storage) |
| `id: Int?` | `id: UUID` |
| — | `source` (`scan`, `search`, `manual`), `portionDescription`, `createdAt` |

`UserInfo` (gender, age, weight, height, activity level, goal type, carb/protein/fat ratios) → `UserProfile`
(same fields plus an optional `customCalorieGoal`).

## Calculations (ported 1:1, covered by `CalorieCoreTests`)

* **BMR (Harris–Benedict, as in `CalculateMealNutrients.bmr`)**
  * male: `66.47 + 13.75·kg + 5·cm − 6.75·age`
  * female: `665.09 + 9.56·kg + 1.84·cm − 4.67·age`
* **Daily goal**: `round(BMR × activity factor + goal adjustment)` with factors low 1.2 / medium 1.3 / high 1.4 and
  adjustments lose −500 / keep 0 / gain +500 kcal.
* **Macro goals**: `goal × carbRatio / 4`, `goal × proteinRatio / 4`, `goal × fatRatio / 9` (grams, rounded).
* **Tracking a portion** (`TrackFood`): `per100g / 100 × grams`.
* **Meal totals** (`CalculateMealNutrients`): sum per meal type and per day.
* **Macro split validation** (`ValidateNutrients`): three integers that must add up to 100.

## Intentional differences

1. **Minimum goal**: the calculated goal is floored at 1,200 kcal so the "lose weight" adjustment never produces an
   unsafe target. A user-entered custom goal is still respected.
2. **Bug fix**: Android's `Product.toTrackableFood()` maps `fatPer100g` from `proteins100g`. The iOS mapper uses
   `fat_100g`.
3. **Search filter**: Android keeps only products whose label kcal lies within ±1 % of `4·carbs + 4·protein + 9·fat`,
   which discards most real products (fibre, polyols, rounding on labels). iOS keeps the plausibility idea with a
   ±25 % / 20 kcal tolerance and also accepts kJ-only products (converted with 4.184 kJ/kcal).
4. **Day navigation**: Android's overview has previous/next-day arrows. iOS keeps Home on today and moves past days
   into the History tab (tap a day to view, edit or add entries).
5. **Precision**: nutrients are stored as `Double` densities instead of rounded integers, so repeated edits don't
   accumulate rounding errors. Values are rounded only for display.
