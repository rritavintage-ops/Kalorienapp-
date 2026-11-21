import UIKit
import XCTest
@testable import CalorieTracker

final class ProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CalorieTrackerTests.ProfileStore"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testNewStoreRequiresOnboarding() {
        let store = ProfileStore(defaults: defaults)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertEqual(store.currentProfile, .default)
    }

    func testSavedProfileSurvivesRelaunch() {
        let profile = UserProfile(gender: .female, age: 31, heightCm: 168, weightKg: 62.5, activityLevel: .high, goalType: .loseWeight,
                                  macroRatios: .highProtein, customCalorieGoal: nil)
        ProfileStore(defaults: defaults).save(profile)

        let relaunched = ProfileStore(defaults: defaults)
        XCTAssertTrue(relaunched.hasCompletedOnboarding)
        XCTAssertEqual(relaunched.profile, profile)
        XCTAssertEqual(relaunched.goals, NutritionCalculator.goals(for: profile))
    }

    func testUpdateAndCustomGoal() {
        let store = ProfileStore(defaults: defaults)
        store.save(.default)
        XCTAssertEqual(store.goals.calories, 2510)

        store.update { $0.customCalorieGoal = 1900 }
        XCTAssertEqual(store.goals.calories, 1900)
        XCTAssertEqual(ProfileStore(defaults: defaults).goals.calories, 1900)
    }

    func testResetReturnsToOnboarding() {
        let store = ProfileStore(defaults: defaults)
        store.save(.default)
        store.reset()
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertFalse(ProfileStore(defaults: defaults).hasCompletedOnboarding)
    }
}

final class ScanFlowModelTests: XCTestCase {
    private struct FailingScanner: MealScanning {
        let error: Error
        func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse {
            throw error
        }
    }

    private struct FixedScanner: MealScanning {
        let response: MealScanResponse
        func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse {
            XCTAssertFalse(imageJPEG.isEmpty)
            return response
        }
    }

    @MainActor
    func testSuccessfulScanShowsReviewWithTotals() async {
        let model = ScanFlowModel(mealType: .lunch)
        await model.analyze(image: ImageProcessor.samplePlateImage(), scanner: FixedScanner(response: MockMealScanner.sampleResponse))

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.drafts.count, 3)
        XCTAssertEqual(model.totals.calories, 513, accuracy: 0.0001) // 248 + 234 + 31
        XCTAssertEqual(model.mealName, "Chicken, rice and broccoli")
        XCTAssertTrue(model.canSave)
    }

    @MainActor
    func testEditingAndRemovingItemsUpdatesTotals() async {
        let model = ScanFlowModel(mealType: .dinner)
        model.apply(MockMealScanner.sampleResponse)

        var rice = model.drafts[1]
        rice.grams = 90 // half the estimated portion
        model.upsert(rice)
        XCTAssertEqual(model.totals.calories, 396, accuracy: 0.0001) // 248 + 117 + 31

        model.remove(model.drafts[0])
        XCTAssertEqual(model.drafts.count, 2)
        XCTAssertEqual(model.totals.calories, 148, accuracy: 0.0001) // 117 + 31

        model.upsert(FoodDraft(name: "Sauce", grams: 30, portionTotals: NutritionFacts(calories: 60, protein: 0, carbs: 4, fat: 5)))
        XCTAssertEqual(model.drafts.count, 3)
        XCTAssertEqual(model.totals.calories, 208, accuracy: 0.0001) // 117 + 31 + 60
    }

    @MainActor
    func testNoFoodResponse() {
        let model = ScanFlowModel(mealType: .snack)
        model.apply(MealScanResponse(containsFood: false, mealName: nil, items: [], notes: "This looks like a keyboard."))
        XCTAssertEqual(model.phase, .notFood(message: "This looks like a keyboard."))
        XCTAssertFalse(model.canSave)
    }

    @MainActor
    func testUnconfiguredScannerShowsFriendlyError() async {
        let model = ScanFlowModel(mealType: .lunch)
        await model.analyze(image: ImageProcessor.samplePlateImage(), scanner: UnavailableMealScanner())
        XCTAssertEqual(model.phase, .failed(message: MealScanError.notConfigured.errorDescription ?? ""))
    }

    @MainActor
    func testOfflineErrorIsMapped() async {
        let model = ScanFlowModel(mealType: .lunch)
        await model.analyze(image: ImageProcessor.samplePlateImage(), scanner: FailingScanner(error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(model.phase, .failed(message: MealScanError.offline.errorDescription ?? ""))
    }

    @MainActor
    func testManualFallbackStartsEmptyReview() {
        let model = ScanFlowModel(mealType: .lunch)
        model.startManualReview()
        XCTAssertEqual(model.phase, .review)
        XCTAssertFalse(model.canSave, "at least one item is needed")
    }
}

final class ImageProcessorTests: XCTestCase {
    func testUploadImageIsDownscaledJPEG() throws {
        let large = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }

        let data = try ImageProcessor.uploadJPEG(from: large)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG magic bytes")
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), ImageProcessor.uploadMaxDimension)
        XCTAssertEqual(decoded.size.width / decoded.size.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testSmallImagesAreNotUpscaled() {
        let small = ImageProcessor.resized(ImageProcessor.samplePlateImage(), maxDimension: 2000)
        XCTAssertEqual(small.size.width, 900)
    }

    func testThumbnailIsSmall() throws {
        let data = try XCTUnwrap(ImageProcessor.thumbnailJPEG(from: ImageProcessor.samplePlateImage()))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), ImageProcessor.thumbnailMaxDimension)
    }
}
