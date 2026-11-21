import Foundation
import SwiftData

/// One logged food in the diary (Android: `TrackedFoodEntity`).
///
/// Nutrients are stored per 100 g together with the portion weight, so the portion values are always
/// derived and editing the amount later rescales them correctly.
@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var grams: Double
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var mealTypeRaw: String
    /// When the food was eaten; day queries use `[startOfDay, nextDay)`.
    var date: Date
    var createdAt: Date
    var sourceRaw: String
    var portionDescription: String?
    var imageURLString: String?
    /// Small JPEG thumbnail of the scanned meal.
    @Attribute(.externalStorage) var photoData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        per100g: NutritionFacts,
        mealType: MealType,
        date: Date,
        source: EntrySource,
        portionDescription: String? = nil,
        imageURLString: String? = nil,
        photoData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.caloriesPer100g = per100g.calories
        self.proteinPer100g = per100g.protein
        self.carbsPer100g = per100g.carbs
        self.fatPer100g = per100g.fat
        self.mealTypeRaw = mealType.rawValue
        self.date = date
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
        self.portionDescription = portionDescription
        self.imageURLString = imageURLString
        self.photoData = photoData
    }
}

extension FoodEntry {
    convenience init(draft: FoodDraft, mealType: MealType, date: Date, source: EntrySource, imageURL: URL? = nil, photoData: Data? = nil) {
        self.init(
            name: draft.trimmedName,
            grams: draft.grams,
            per100g: draft.per100g.clamped,
            mealType: mealType,
            date: date,
            source: source,
            portionDescription: draft.portionDescription,
            imageURLString: imageURL?.absoluteString,
            photoData: photoData
        )
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: EntrySource {
        EntrySource(rawValue: sourceRaw) ?? .manual
    }

    var per100g: NutritionFacts {
        get {
            NutritionFacts(calories: caloriesPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
        }
        set {
            caloriesPer100g = newValue.calories
            proteinPer100g = newValue.protein
            carbsPer100g = newValue.carbs
            fatPer100g = newValue.fat
        }
    }

    /// Nutrients of the logged portion.
    var nutrients: NutritionFacts {
        per100g.forPortion(grams: grams)
    }

    var loggedFood: LoggedFood {
        LoggedFood(mealType: mealType, nutrients: nutrients, date: date)
    }

    var imageURL: URL? {
        imageURLString.flatMap(URL.init(string:))
    }

    var draft: FoodDraft {
        FoodDraft(id: id, name: name, grams: grams, per100g: per100g, portionDescription: portionDescription)
    }

    func apply(_ draft: FoodDraft, mealType: MealType) {
        name = draft.trimmedName
        grams = draft.grams
        per100g = draft.per100g.clamped
        portionDescription = draft.portionDescription
        self.mealType = mealType
    }
}
