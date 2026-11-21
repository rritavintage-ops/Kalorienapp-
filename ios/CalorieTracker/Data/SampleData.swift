import Foundation
import SwiftData

/// Example meals for UI tests, screenshots and SwiftUI previews.
enum SampleData {
    static func insert(into context: ModelContext, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        func at(_ dayOffset: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }

        let entries: [FoodEntry] = [
            FoodEntry(name: "Oatmeal with berries", grams: 250,
                      per100g: NutritionFacts(calories: 128, protein: 4.4, carbs: 21.6, fat: 2.6),
                      mealType: .breakfast, date: at(0, hour: 8), source: .manual, portionDescription: "1 bowl"),
            FoodEntry(name: "Greek yogurt", grams: 150,
                      per100g: NutritionFacts(calories: 97, protein: 9, carbs: 3.6, fat: 5),
                      mealType: .breakfast, date: at(0, hour: 8), source: .search),
            FoodEntry(name: "Chicken salad", grams: 320,
                      per100g: NutritionFacts(calories: 118, protein: 11.5, carbs: 4.2, fat: 6.1),
                      mealType: .lunch, date: at(0, hour: 13), source: .scan, portionDescription: "1 large bowl"),
            FoodEntry(name: "Apple", grams: 180,
                      per100g: NutritionFacts(calories: 52, protein: 0.3, carbs: 13.8, fat: 0.2),
                      mealType: .snack, date: at(0, hour: 16), source: .manual, portionDescription: "1 medium"),
        ]

        let previousDays: [(Int, Double)] = [(-1, 2140), (-2, 1890), (-3, 2420), (-4, 2010), (-5, 1760), (-6, 2230)]
        var history: [FoodEntry] = []
        for (offset, kcal) in previousDays {
            history.append(FoodEntry(name: "Breakfast", grams: 100,
                                     per100g: NutritionFacts(calories: kcal * 0.25, protein: 18, carbs: 60, fat: 12),
                                     mealType: .breakfast, date: at(offset, hour: 8), source: .manual))
            history.append(FoodEntry(name: "Lunch", grams: 100,
                                     per100g: NutritionFacts(calories: kcal * 0.4, protein: 35, carbs: 90, fat: 25),
                                     mealType: .lunch, date: at(offset, hour: 13), source: .manual))
            history.append(FoodEntry(name: "Dinner", grams: 100,
                                     per100g: NutritionFacts(calories: kcal * 0.35, protein: 40, carbs: 70, fat: 22),
                                     mealType: .dinner, date: at(offset, hour: 19), source: .manual))
        }

        for entry in entries + history {
            context.insert(entry)
        }
    }
}
