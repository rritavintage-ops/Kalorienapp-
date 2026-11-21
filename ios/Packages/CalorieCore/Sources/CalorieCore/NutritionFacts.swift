import Foundation

/// Energy and macronutrients. Depending on context the values describe 100 g of a food
/// (a density) or a concrete portion.
public struct NutritionFacts: Codable, Equatable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 0)

    public func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor
        )
    }

    /// Interprets `self` as values per 100 g and returns the values for `grams`.
    public func forPortion(grams: Double) -> NutritionFacts {
        scaled(by: max(0, grams) / 100)
    }

    /// Interprets `self` as the values of a `grams` portion and returns the per-100 g density.
    /// Returns `nil` when the portion weight is not positive.
    public func perHundredGrams(fromPortionOf grams: Double) -> NutritionFacts? {
        guard grams > 0 else { return nil }
        return scaled(by: 100 / grams)
    }

    /// Energy implied by the macronutrients (Atwater factors 4/4/9).
    public var caloriesFromMacros: Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    /// All values are finite and not negative.
    public var isValid: Bool {
        [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 }
    }

    /// Replaces negative or non-finite values with zero.
    public var clamped: NutritionFacts {
        func clean(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
        return NutritionFacts(calories: clean(calories), protein: clean(protein), carbs: clean(carbs), fat: clean(fat))
    }

    public static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    public static func += (lhs: inout NutritionFacts, rhs: NutritionFacts) {
        lhs = lhs + rhs
    }
}

public extension Sequence where Element == NutritionFacts {
    func sum() -> NutritionFacts {
        reduce(.zero, +)
    }
}
