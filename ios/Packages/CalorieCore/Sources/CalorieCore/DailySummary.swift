import Foundation

/// The calculation-relevant part of a diary entry.
public struct LoggedFood: Equatable, Sendable {
    public var mealType: MealType
    public var nutrients: NutritionFacts
    public var date: Date

    public init(mealType: MealType, nutrients: NutritionFacts, date: Date) {
        self.mealType = mealType
        self.nutrients = nutrients
        self.date = date
    }
}

/// Totals for one day compared to the user's goals (port of `CalculateMealNutrients.Result`).
public struct DailySummary: Equatable, Sendable {
    public let goals: NutritionGoals
    public let consumed: NutritionFacts
    public let meals: [MealType: NutritionFacts]

    public init(foods: [LoggedFood], goals: NutritionGoals) {
        var meals: [MealType: NutritionFacts] = [:]
        for food in foods {
            meals[food.mealType, default: .zero] += food.nutrients
        }
        self.goals = goals
        self.meals = meals
        self.consumed = foods.map(\.nutrients).sum()
    }

    public func totals(for meal: MealType) -> NutritionFacts {
        meals[meal] ?? .zero
    }

    public var consumedCalories: Int {
        Int(consumed.calories.rounded())
    }

    /// Calories still available today. Negative when the goal is exceeded.
    public var remainingCalories: Int {
        goals.calories - consumedCalories
    }

    public var isOverGoal: Bool {
        consumedCalories > goals.calories
    }

    /// Consumed / goal. Can exceed 1.
    public var calorieProgress: Double {
        Self.progress(consumed.calories, goal: goals.calories)
    }

    public var carbsProgress: Double { Self.progress(consumed.carbs, goal: goals.carbsGrams) }
    public var proteinProgress: Double { Self.progress(consumed.protein, goal: goals.proteinGrams) }
    public var fatProgress: Double { Self.progress(consumed.fat, goal: goals.fatGrams) }

    static func progress(_ value: Double, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return max(0, value) / Double(goal)
    }
}
