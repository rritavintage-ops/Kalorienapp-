import Foundation

/// An editable food item before (or while) it is saved to the diary.
///
/// Nutrients are stored as a per-100 g density, so changing `grams` rescales the portion values and
/// editing a portion value updates the density. This is how the scanner review screen, manual entry
/// and the entry editor let users correct the food *and* the portion size.
public struct FoodDraft: Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var grams: Double
    public var per100g: NutritionFacts
    /// Human-readable portion from the scanner, e.g. "1 cup" or "2 slices".
    public var portionDescription: String?
    public var confidence: ScanConfidence?

    public static let maximumGrams: Double = 5000

    public init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        per100g: NutritionFacts,
        portionDescription: String? = nil,
        confidence: ScanConfidence? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.per100g = per100g
        self.portionDescription = portionDescription
        self.confidence = confidence
    }

    /// Creates a draft from the nutrient values of a concrete portion.
    /// When the weight is unknown (`grams <= 0`) the portion is treated as 100 g.
    public init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        portionTotals: NutritionFacts,
        portionDescription: String? = nil,
        confidence: ScanConfidence? = nil
    ) {
        let totals = portionTotals.clamped
        let weight = grams.isFinite && grams > 0 ? grams : 100
        self.init(
            id: id,
            name: name,
            grams: weight,
            per100g: totals.perHundredGrams(fromPortionOf: weight) ?? totals,
            portionDescription: portionDescription,
            confidence: confidence
        )
    }

    public static func empty(id: UUID = UUID()) -> FoodDraft {
        FoodDraft(id: id, name: "", grams: 100, per100g: .zero)
    }

    /// Nutrients of the current portion.
    public var totals: NutritionFacts {
        per100g.forPortion(grams: grams)
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !trimmedName.isEmpty && grams > 0 && grams <= Self.maximumGrams && per100g.isValid
    }

    /// Sets the portion value of one nutrient (e.g. `\.calories`) by updating the density.
    public mutating func setPortionValue(_ keyPath: WritableKeyPath<NutritionFacts, Double>, to value: Double) {
        let cleanValue = value.isFinite ? max(0, value) : 0
        if grams <= 0 {
            grams = 100
        }
        per100g[keyPath: keyPath] = cleanValue * 100 / grams
    }

    /// Multiplies the portion size, e.g. 0.5 for half or 2 for a double portion.
    public mutating func scalePortion(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        grams = min(Self.maximumGrams, (grams * factor).rounded())
    }
}
