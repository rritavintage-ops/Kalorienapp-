# Calorie Tracker for iPhone

A native iOS calorie tracker built with **Swift, SwiftUI and SwiftData**. It is a port of
[philipplackner/CalorieTracker](https://github.com/philipplackner/CalorieTracker) (Android, Jetpack Compose), with an
added **AI food scanner**: take a photo of your meal and get the foods, portion sizes, calories, protein, carbs and fat
for review before saving.

* **Home**: daily goal, eaten, remaining, an animated calorie ring, macro bars, today's meals (breakfast, lunch,
  dinner, snacks) and a large central camera button.
* **AI scanner**: camera (`UIImagePickerController`) or photo library (`PhotosPicker`) → secure backend → Claude
  vision → editable results. Every item's name, portion (grams, ½×/2× shortcuts) and nutrients can be corrected.
* **Food diary**: entries are saved persistently and can be edited (rescaling nutrients with the amount) or deleted
  (swipe, context menu or editor).
* **Food search**: Open Food Facts database search (as in the Android app) plus manual entry.
* **History**: last-7-days chart with goal line and average, plus every logged day (tap to view, edit or add).
* **Profile**: body data, activity level, goal, macro split, optional custom calorie goal, reset.
* **Onboarding**: gender, age, height, weight, activity, goal and macro split → personal goal (Harris–Benedict, as in
  the Android app).

See [docs/ANDROID_TO_IOS_MAPPING.md](docs/ANDROID_TO_IOS_MAPPING.md) for how every Android module maps to the iOS
code, plus the intentional differences.

## Repository layout

```
ios/
  CalorieTracker.xcodeproj        Xcode project (shared scheme "CalorieTracker")
  CalorieTracker/                 App sources (Xcode 16 synchronized folder)
    App/                          Entry point, composition root, tabs
    Data/                         SwiftData model (FoodEntry), ProfileStore, sample data
    Design/                       Theme, calorie ring, cards, number field
    Features/                     Onboarding, Home, Diary, Scanner, Search, History, Profile
    Services/                     Scan backend client, Open Food Facts client, image processing
    Resources/                    Assets (app icon, accent color), privacy manifest
  CalorieTrackerTests/            App unit tests (SwiftData, profile, scan flow, images)
  CalorieTrackerUITests/          End-to-end UI tests with screenshots
  Packages/CalorieCore/           Platform-independent domain logic + tests (also runs on Linux)
  Config/                         xcconfig + Info.plist (backend URL, bundle id, team)
backend/                          Cloudflare Worker that calls Claude vision (holds the API key)
docs/                             Android → iOS mapping
.github/workflows/                CI: iPhone simulator build + tests, Linux package tests, backend tests
```

## Requirements

* Xcode 16 or newer (the project uses synchronized folders, `objectVersion` 77)
* iOS 17+ (SwiftData, Observation)
* For the AI scanner: a deployed backend (see [backend/README.md](backend/README.md)) and an Anthropic API key

## Getting started

1. Open `ios/CalorieTracker.xcodeproj` in Xcode.
2. Copy `ios/Config/Secrets.example.xcconfig` to `ios/Config/Secrets.xcconfig` (git-ignored) and set:
   * `DEVELOPMENT_TEAM` and `APP_BUNDLE_IDENTIFIER` (needed to run on a device),
   * `SCAN_API_BASE_URL`: your backend URL, written as `https:/$()/your-worker.workers.dev`,
   * `SCAN_API_CLIENT_TOKEN` (optional): must match the backend's `APP_CLIENT_TOKEN`.
3. Pick an iPhone simulator and run (⌘R). Run all tests with ⌘U.

Without a backend URL the app still works fully, except that scanning shows a friendly "not set up" message with a
manual-entry fallback.

### Backend

```bash
cd backend
npm install
npx wrangler secret put ANTHROPIC_API_KEY
npm run deploy
```

Details, security measures and local development: [backend/README.md](backend/README.md).

## Tests

| Suite | What it covers | Runs on |
| --- | --- | --- |
| `CalorieCoreTests` | BMR, daily goal, macro goals (parity with Android), safety floor, macro validation, portion scaling, draft editing, daily/meal totals, history aggregation, Open Food Facts parsing and filtering, scan API request/response/error mapping | `swift test` (macOS, Linux), Xcode |
| `CalorieTrackerTests` | SwiftData persistence and day queries, editing and deleting entries, profile persistence, scan flow state, image downscaling | iPhone simulator |
| `CalorieTrackerUITests` | Onboarding → goal 2,510 kcal → dashboard; scan → edit portion → save; manual add → edit → delete; search → amount → add; History and Profile screens (with screenshots) | iPhone simulator |
| `backend/test` | Request validation, auth, rate limiting, normalization, error mapping, Claude request shape | Node (vitest) |

```bash
swift test --package-path ios/Packages/CalorieCore
xcodebuild test -project ios/CalorieTracker.xcodeproj -scheme CalorieTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16'
(cd backend && npm test)
```

CI (`.github/workflows/ios.yml`) builds the app, runs all three Swift suites on an iPhone simulator and uploads the
UI-test screenshots as the `simulator-screenshots` artifact.

The UI tests launch the app with `-ui-testing`, which uses an in-memory store, isolated defaults, a mock scanner
(the simulator has no camera) and an offline food list.

## Before App Store submission

* Set your team and bundle identifier in `Config/Secrets.xcconfig`; bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
* Deploy the backend on a paid Workers plan and consider adding App Attest verification to it.
* Add a privacy policy URL in App Store Connect. The app sends meal photos to your backend and to Anthropic for
  analysis; nothing is stored server-side by this backend. `PrivacyInfo.xcprivacy` declares photo collection for app
  functionality (not linked, no tracking) and the UserDefaults API reason.
* App Store screenshots: the UI tests already capture the main screens.
* Calorie and nutrient values are estimates. The app shows this in Profile and on the scan review screen.
