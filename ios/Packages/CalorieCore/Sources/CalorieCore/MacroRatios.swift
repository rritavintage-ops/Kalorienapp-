import Foundation

/// Share of daily calories that should come from each macronutrient (fractions that add up to 1).
public struct MacroRatios: Codable, Equatable, Hashable, Sendable {
    public var carbs: Double
    public var protein: Double
    public var fat: Double

    public init(carbs: Double, protein: Double, fat: Double) {
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }

    public init(carbsPercent: Int, proteinPercent: Int, fatPercent: Int) {
        self.init(
            carbs: Double(carbsPercent) / 100,
            protein: Double(proteinPercent) / 100,
            fat: Double(fatPercent) / 100
        )
    }

    public var carbsPercent: Int { Int((carbs * 100).rounded()) }
    public var proteinPercent: Int { Int((protein * 100).rounded()) }
    public var fatPercent: Int { Int((fat * 100).rounded()) }

    /// Android default: 40 % carbs, 30 % protein, 30 % fat.
    public static let balanced = MacroRatios(carbsPercent: 40, proteinPercent: 30, fatPercent: 30)
    public static let highProtein = MacroRatios(carbsPercent: 30, proteinPercent: 40, fatPercent: 30)
    public static let lowCarb = MacroRatios(carbsPercent: 20, proteinPercent: 40, fatPercent: 40)
}

public struct MacroPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let ratios: MacroRatios

    public static let all: [MacroPreset] = [
        MacroPreset(id: "balanced", name: "Balanced", ratios: .balanced),
        MacroPreset(id: "high-protein", name: "High protein", ratios: .highProtein),
        MacroPreset(id: "low-carb", name: "Low carb", ratios: .lowCarb),
    ]
}

public enum MacroValidationError: Error, Equatable, Sendable {
    case invalidValues
    case notOneHundredPercent(total: Int)
}

/// Port of Android's `ValidateNutrients` use case.
public enum MacroRatioValidator {
    public static func validate(carbsPercent: Int, proteinPercent: Int, fatPercent: Int) -> Result<MacroRatios, MacroValidationError> {
        let values = [carbsPercent, proteinPercent, fatPercent]
        guard values.allSatisfy({ (0...100).contains($0) }) else {
            return .failure(.invalidValues)
        }
        let total = values.reduce(0, +)
        guard total == 100 else {
            return .failure(.notOneHundredPercent(total: total))
        }
        return .success(MacroRatios(carbsPercent: carbsPercent, proteinPercent: proteinPercent, fatPercent: fatPercent))
    }

    public static func validate(carbsText: String, proteinText: String, fatText: String) -> Result<MacroRatios, MacroValidationError> {
        guard
            let carbs = Int(carbsText.trimmingCharacters(in: .whitespaces)),
            let protein = Int(proteinText.trimmingCharacters(in: .whitespaces)),
            let fat = Int(fatText.trimmingCharacters(in: .whitespaces))
        else {
            return .failure(.invalidValues)
        }
        return validate(carbsPercent: carbs, proteinPercent: protein, fatPercent: fat)
    }
}
