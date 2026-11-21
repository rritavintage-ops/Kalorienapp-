import XCTest
@testable import CalorieCore

final class NutritionFactsTests: XCTestCase {
    func testPortionScalingMatchesAndroidTrackFood() {
        // Android: ((caloriesPer100g / 100f) * amount).roundToInt()
        let oats = NutritionFacts(calories: 379, protein: 13.2, carbs: 67.7, fat: 6.5)
        let portion = oats.forPortion(grams: 60)
        XCTAssertEqual(portion.calories, 227.4, accuracy: 0.0001)
        XCTAssertEqual(portion.protein, 7.92, accuracy: 0.0001)
        XCTAssertEqual(portion.carbs, 40.62, accuracy: 0.0001)
        XCTAssertEqual(portion.fat, 3.9, accuracy: 0.0001)
    }

    func testNegativePortionIsTreatedAsZero() {
        let food = NutritionFacts(calories: 100, protein: 1, carbs: 1, fat: 1)
        XCTAssertEqual(food.forPortion(grams: -50), .zero)
    }

    func testPerHundredGramsInvertsPortionScaling() throws {
        let portion = NutritionFacts(calories: 248, protein: 46.5, carbs: 0, fat: 5.4)
        let density = try XCTUnwrap(portion.perHundredGrams(fromPortionOf: 150))
        XCTAssertEqual(density.calories, 165.333, accuracy: 0.001)
        let back = density.forPortion(grams: 150)
        XCTAssertEqual(back.calories, 248, accuracy: 0.0001)
        XCTAssertEqual(back.protein, 46.5, accuracy: 0.0001)
        XCTAssertNil(portion.perHundredGrams(fromPortionOf: 0))
    }

    func testSumAndCaloriesFromMacros() {
        let a = NutritionFacts(calories: 100, protein: 5, carbs: 10, fat: 2)
        let b = NutritionFacts(calories: 50, protein: 1, carbs: 2, fat: 3)
        XCTAssertEqual([a, b].sum(), NutritionFacts(calories: 150, protein: 6, carbs: 12, fat: 5))
        XCTAssertEqual(a.caloriesFromMacros, 5 * 4 + 10 * 4 + 2 * 9)
    }

    func testClampingRemovesNegativeAndNonFiniteValues() {
        let dirty = NutritionFacts(calories: -10, protein: .nan, carbs: .infinity, fat: 3)
        XCTAssertFalse(dirty.isValid)
        XCTAssertEqual(dirty.clamped, NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 3))
    }
}

final class FoodDraftTests: XCTestCase {
    func testChangingGramsRescalesTotals() {
        var draft = FoodDraft(name: "Rice", grams: 180, portionTotals: NutritionFacts(calories: 234, protein: 4.3, carbs: 51, fat: 0.5))
        draft.grams = 90
        XCTAssertEqual(draft.totals.calories, 117, accuracy: 0.0001)
        XCTAssertEqual(draft.totals.carbs, 25.5, accuracy: 0.0001)
    }

    func testEditingPortionValueUpdatesDensity() {
        var draft = FoodDraft(name: "Pasta", grams: 200, portionTotals: NutritionFacts(calories: 300, protein: 10, carbs: 60, fat: 2))
        draft.setPortionValue(\.calories, to: 400)
        XCTAssertEqual(draft.totals.calories, 400, accuracy: 0.0001)
        XCTAssertEqual(draft.per100g.calories, 200, accuracy: 0.0001)
        // Other nutrients are unchanged.
        XCTAssertEqual(draft.totals.protein, 10, accuracy: 0.0001)
        // Doubling the portion afterwards doubles the edited value too.
        draft.grams = 400
        XCTAssertEqual(draft.totals.calories, 800, accuracy: 0.0001)
    }

    func testSettingPortionValueWithZeroGramsFallsBackToHundredGrams() {
        var draft = FoodDraft(name: "Soup", grams: 0, per100g: .zero)
        draft.setPortionValue(\.calories, to: 120)
        XCTAssertEqual(draft.grams, 100)
        XCTAssertEqual(draft.totals.calories, 120, accuracy: 0.0001)
    }

    func testUnknownWeightIsTreatedAsHundredGrams() {
        let draft = FoodDraft(name: "Coffee", grams: 0, portionTotals: NutritionFacts(calories: 5, protein: 0.3, carbs: 0, fat: 0))
        XCTAssertEqual(draft.grams, 100)
        XCTAssertEqual(draft.totals.calories, 5, accuracy: 0.0001)
    }

    func testScalePortion() {
        var draft = FoodDraft(name: "Apple", grams: 150, per100g: NutritionFacts(calories: 52, protein: 0.3, carbs: 14, fat: 0.2))
        draft.scalePortion(by: 0.5)
        XCTAssertEqual(draft.grams, 75)
        draft.scalePortion(by: 1000)
        XCTAssertEqual(draft.grams, FoodDraft.maximumGrams)
        draft.scalePortion(by: -1)
        XCTAssertEqual(draft.grams, FoodDraft.maximumGrams)
    }

    func testValidation() {
        var draft = FoodDraft.empty()
        XCTAssertFalse(draft.isValid, "a name is required")
        draft.name = "  Banana "
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.trimmedName, "Banana")
        draft.grams = 0
        XCTAssertFalse(draft.isValid, "the portion must be positive")
        draft.grams = FoodDraft.maximumGrams + 1
        XCTAssertFalse(draft.isValid)
    }
}

final class NumberInputTests: XCTestCase {
    func testParsesDotAndCommaDecimals() {
        XCTAssertEqual(NumberInput.parseDecimal("12"), 12)
        XCTAssertEqual(NumberInput.parseDecimal("12.5"), 12.5)
        XCTAssertEqual(NumberInput.parseDecimal("12,5"), 12.5)
        XCTAssertEqual(NumberInput.parseDecimal(" 7 "), 7)
        XCTAssertEqual(NumberInput.parseDecimal(".5"), 0.5)
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(NumberInput.parseDecimal(""))
        XCTAssertNil(NumberInput.parseDecimal("."))
        XCTAssertNil(NumberInput.parseDecimal("1.2.3"))
        XCTAssertNil(NumberInput.parseDecimal("-5"))
        XCTAssertNil(NumberInput.parseDecimal("abc"))
    }

    func testDigitsOnlyMatchesAndroidFilterOutDigits() {
        XCTAssertEqual(NumberInput.digitsOnly("1a2b3"), "123")
        XCTAssertEqual(NumberInput.digitsOnly("٣4"), "4", "non-ASCII digits are dropped")
    }
}
