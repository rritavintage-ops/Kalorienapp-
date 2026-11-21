import SwiftData
import XCTest
@testable import CalorieTracker

final class FoodEntryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = AppEnvironment.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func entries(on day: Date) throws -> [FoodEntry] {
        let interval = LogDate.dayInterval(containing: day)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor)
    }

    func testInsertedEntryIsPersistedWithDerivedNutrients() throws {
        let draft = FoodDraft(name: " Rice ", grams: 180, portionTotals: NutritionFacts(calories: 234, protein: 4.3, carbs: 51, fat: 0.5))
        context.insert(FoodEntry(draft: draft, mealType: .lunch, date: Date(), source: .scan))
        try context.save()

        let saved = try XCTUnwrap(try entries(on: Date()).first)
        XCTAssertEqual(saved.name, "Rice", "names are trimmed")
        XCTAssertEqual(saved.mealType, .lunch)
        XCTAssertEqual(saved.source, .scan)
        XCTAssertEqual(saved.nutrients.calories, 234, accuracy: 0.0001)
        XCTAssertEqual(saved.loggedFood.nutrients.carbs, 51, accuracy: 0.0001)
    }

    func testDayQueryOnlyReturnsThatDay() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let food = NutritionFacts(calories: 100, protein: 1, carbs: 1, fat: 1)
        context.insert(FoodEntry(name: "Today early", grams: 100, per100g: food, mealType: .breakfast, date: today, source: .manual))
        context.insert(FoodEntry(name: "Yesterday late", grams: 100, per100g: food, mealType: .dinner,
                                 date: today.addingTimeInterval(-1), source: .manual))
        context.insert(FoodEntry(name: "Yesterday noon", grams: 100, per100g: food, mealType: .lunch,
                                 date: LogDate.entryDate(forDay: yesterday), source: .manual))
        try context.save()

        XCTAssertEqual(try entries(on: today).map(\.name), ["Today early"])
        XCTAssertEqual(Set(try entries(on: yesterday).map(\.name)), ["Yesterday late", "Yesterday noon"])
    }

    func testEditingAmountRescalesNutrients() throws {
        let entry = FoodEntry(name: "Pasta", grams: 200, per100g: NutritionFacts(calories: 150, protein: 5, carbs: 30, fat: 1),
                              mealType: .dinner, date: Date(), source: .manual)
        context.insert(entry)

        var draft = entry.draft
        draft.grams = 300
        entry.apply(draft, mealType: .lunch)
        try context.save()

        XCTAssertEqual(entry.nutrients.calories, 450, accuracy: 0.0001)
        XCTAssertEqual(entry.mealType, .lunch)
    }

    func testDailySummaryFromEntries() throws {
        let day = Date()
        let items: [(String, MealType, Double, NutritionFacts)] = [
            ("Oats", .breakfast, 60, NutritionFacts(calories: 379, protein: 13.2, carbs: 67.7, fat: 6.5)),
            ("Milk", .breakfast, 200, NutritionFacts(calories: 64, protein: 3.3, carbs: 4.8, fat: 3.6)),
            ("Chicken", .dinner, 150, NutritionFacts(calories: 165, protein: 31, carbs: 0, fat: 3.6)),
        ]
        for (name, meal, grams, per100g) in items {
            context.insert(FoodEntry(name: name, grams: grams, per100g: per100g, mealType: meal, date: day, source: .manual))
        }
        try context.save()

        let goals = NutritionGoals(calories: 2000, carbsGrams: 200, proteinGrams: 150, fatGrams: 67)
        let summary = DailySummary(foods: try entries(on: day).map(\.loggedFood), goals: goals)
        // 227.4 + 128 + 247.5 = 602.9
        XCTAssertEqual(summary.consumedCalories, 603)
        XCTAssertEqual(summary.remainingCalories, 1397)
        XCTAssertEqual(summary.totals(for: .breakfast).calories, 355.4, accuracy: 0.0001)
        XCTAssertEqual(summary.totals(for: .lunch), .zero)
    }

    func testDeletingEntry() throws {
        let entry = FoodEntry(name: "Cookie", grams: 30, per100g: NutritionFacts(calories: 480, protein: 6, carbs: 65, fat: 22),
                              mealType: .snack, date: Date(), source: .manual)
        context.insert(entry)
        try context.save()
        XCTAssertEqual(try entries(on: Date()).count, 1)

        context.delete(entry)
        try context.save()
        XCTAssertTrue(try entries(on: Date()).isEmpty)
    }

    func testSampleDataCoversTodayAndPreviousWeek() throws {
        SampleData.insert(into: context)
        try context.save()
        let all = try context.fetch(FetchDescriptor<FoodEntry>())
        let days = HistoryAggregator.dailyTotals(for: all.map(\.loggedFood))
        XCTAssertEqual(days.count, 7)
        XCTAssertFalse(try entries(on: Date()).isEmpty)
    }
}
