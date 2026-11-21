import Foundation

/// Daily targets derived from a `UserProfile`.
public struct NutritionGoals: Equatable, Sendable {
    public var calories: Int
    public var carbsGrams: Int
    public var proteinGrams: Int
    public var fatGrams: Int

    public init(calories: Int, carbsGrams: Int, proteinGrams: Int, fatGrams: Int) {
        self.calories = calories
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
    }
}

/// Port of the goal calculation in Android's `CalculateMealNutrients` use case.
public enum NutritionCalculator {
    /// Lower bound for a *calculated* goal so the weight-loss deficit never produces an unsafe target.
    public static let minimumCalculatedCalories = 1200

    /// Harris–Benedict basal metabolic rate in kcal/day, rounded like the Android implementation.
    public static func basalMetabolicRate(for profile: UserProfile) -> Int {
        let weight = profile.weightKg
        let height = profile.heightCm
        let age = Double(profile.age)
        let value: Double
        switch profile.gender {
        case .male:
            value = 66.47 + 13.75 * weight + 5.0 * height - 6.75 * age
        case .female:
            value = 665.09 + 9.56 * weight + 1.84 * height - 4.67 * age
        }
        return Int(value.rounded())
    }

    /// BMR × activity factor + goal adjustment, floored at `minimumCalculatedCalories`.
    public static func calculatedDailyCalories(for profile: UserProfile) -> Int {
        let bmr = Double(basalMetabolicRate(for: profile))
        let total = bmr * profile.activityLevel.multiplier + Double(profile.goalType.calorieAdjustment)
        return max(minimumCalculatedCalories, Int(total.rounded()))
    }

    /// The goal the app works with: the custom goal when set, otherwise the calculated one.
    public static func dailyCalorieGoal(for profile: UserProfile) -> Int {
        if let custom = profile.customCalorieGoal, custom > 0 {
            return custom
        }
        return calculatedDailyCalories(for: profile)
    }

    public static func goals(for profile: UserProfile) -> NutritionGoals {
        let calories = dailyCalorieGoal(for: profile)
        let ratios = profile.macroRatios
        return NutritionGoals(
            calories: calories,
            carbsGrams: Int((Double(calories) * ratios.carbs / 4).rounded()),
            proteinGrams: Int((Double(calories) * ratios.protein / 4).rounded()),
            fatGrams: Int((Double(calories) * ratios.fat / 9).rounded())
        )
    }
}
