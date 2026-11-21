import XCTest
@testable import CalorieCore

final class NutritionCalculatorTests: XCTestCase {
    /// The profile used by the Android `CalculateMealNutrientsTest`.
    private let androidTestProfile = UserProfile(
        gender: .male,
        age: 20,
        heightCm: 180,
        weightKg: 80,
        activityLevel: .medium,
        goalType: .keepWeight,
        macroRatios: MacroRatios(carbsPercent: 40, proteinPercent: 30, fatPercent: 30)
    )

    func testMaleBasalMetabolicRateMatchesHarrisBenedict() {
        // 66.47 + 13.75 * 80 + 5 * 180 - 6.75 * 20 = 1931.47
        XCTAssertEqual(NutritionCalculator.basalMetabolicRate(for: androidTestProfile), 1931)
    }

    func testFemaleBasalMetabolicRateMatchesHarrisBenedict() {
        let profile = UserProfile(gender: .female, age: 30, heightCm: 165, weightKg: 65, activityLevel: .low, goalType: .keepWeight)
        // 665.09 + 9.56 * 65 + 1.84 * 165 - 4.67 * 30 = 1449.99
        XCTAssertEqual(NutritionCalculator.basalMetabolicRate(for: profile), 1450)
    }

    func testDailyCaloriesForAndroidReferenceProfile() {
        // 1931 * 1.3 = 2510.3
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: androidTestProfile), 2510)
    }

    func testActivityLevelsUseAndroidFactors() {
        var profile = androidTestProfile
        profile.activityLevel = .low
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), 2317) // 1931 * 1.2 = 2317.2
        profile.activityLevel = .high
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), 2703) // 1931 * 1.4 = 2703.4
    }

    func testGoalTypeAdjustsByFiveHundredCalories() {
        var profile = androidTestProfile
        profile.goalType = .loseWeight
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), 2010)
        profile.goalType = .gainWeight
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), 3010)
    }

    func testCalculatedGoalNeverDropsBelowSafetyFloor() {
        let profile = UserProfile(gender: .female, age: 70, heightCm: 150, weightKg: 45, activityLevel: .low, goalType: .loseWeight)
        // BMR = 665.09 + 430.2 + 276 - 326.9 = 1044 -> 1044 * 1.2 - 500 = 753
        XCTAssertEqual(NutritionCalculator.basalMetabolicRate(for: profile), 1044)
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), NutritionCalculator.minimumCalculatedCalories)
    }

    func testCustomGoalOverridesCalculatedGoal() {
        var profile = androidTestProfile
        profile.customCalorieGoal = 1800
        XCTAssertEqual(NutritionCalculator.dailyCalorieGoal(for: profile), 1800)
        XCTAssertEqual(NutritionCalculator.calculatedDailyCalories(for: profile), 2510)
    }

    func testNonPositiveCustomGoalIsIgnored() {
        var profile = androidTestProfile
        profile.customCalorieGoal = 0
        XCTAssertEqual(NutritionCalculator.dailyCalorieGoal(for: profile), 2510)
    }

    func testMacroGoalsUseCaloriesPerGram() {
        let goals = NutritionCalculator.goals(for: androidTestProfile)
        XCTAssertEqual(goals.calories, 2510)
        XCTAssertEqual(goals.carbsGrams, 251)   // 2510 * 0.4 / 4
        XCTAssertEqual(goals.proteinGrams, 188) // 2510 * 0.3 / 4 = 188.25
        XCTAssertEqual(goals.fatGrams, 84)      // 2510 * 0.3 / 9 = 83.67
    }

    func testMacroGoalsFollowCustomRatios() {
        var profile = androidTestProfile
        profile.customCalorieGoal = 2000
        profile.macroRatios = .lowCarb // 20 / 40 / 40
        let goals = NutritionCalculator.goals(for: profile)
        XCTAssertEqual(goals.carbsGrams, 100)
        XCTAssertEqual(goals.proteinGrams, 200)
        XCTAssertEqual(goals.fatGrams, 89) // 800 / 9 = 88.9
    }
}

final class MacroRatioValidatorTests: XCTestCase {
    func testValidSplitIsAccepted() {
        let result = MacroRatioValidator.validate(carbsPercent: 40, proteinPercent: 30, fatPercent: 30)
        XCTAssertEqual(result, .success(.balanced))
    }

    func testSplitThatDoesNotAddUpIsRejected() {
        let result = MacroRatioValidator.validate(carbsPercent: 40, proteinPercent: 40, fatPercent: 30)
        XCTAssertEqual(result, .failure(.notOneHundredPercent(total: 110)))
    }

    func testOutOfRangeValuesAreRejected() {
        let result = MacroRatioValidator.validate(carbsPercent: 120, proteinPercent: -10, fatPercent: -10)
        XCTAssertEqual(result, .failure(.invalidValues))
    }

    func testTextInputLikeAndroidValidateNutrients() {
        XCTAssertEqual(MacroRatioValidator.validate(carbsText: "50", proteinText: " 25", fatText: "25"),
                       .success(MacroRatios(carbsPercent: 50, proteinPercent: 25, fatPercent: 25)))
        XCTAssertEqual(MacroRatioValidator.validate(carbsText: "abc", proteinText: "25", fatText: "25"),
                       .failure(.invalidValues))
        XCTAssertEqual(MacroRatioValidator.validate(carbsText: "", proteinText: "25", fatText: "25"),
                       .failure(.invalidValues))
    }

    func testPercentRoundTrip() {
        let ratios = MacroRatios(carbsPercent: 35, proteinPercent: 35, fatPercent: 30)
        XCTAssertEqual(ratios.carbsPercent, 35)
        XCTAssertEqual(ratios.proteinPercent, 35)
        XCTAssertEqual(ratios.fatPercent, 30)
    }

    func testPresetsAllAddUpToOneHundred() {
        for preset in MacroPreset.all {
            let r = preset.ratios
            XCTAssertEqual(r.carbsPercent + r.proteinPercent + r.fatPercent, 100, preset.name)
        }
    }
}
