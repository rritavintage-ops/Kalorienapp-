import XCTest
@testable import CalorieCore

final class DailySummaryTests: XCTestCase {
    private let goals = NutritionGoals(calories: 2000, carbsGrams: 200, proteinGrams: 150, fatGrams: 67)
    private let now = Date(timeIntervalSince1970: 1_763_726_400) // fixed reference date

    private func food(_ meal: MealType, kcal: Double, p: Double = 0, c: Double = 0, f: Double = 0) -> LoggedFood {
        LoggedFood(mealType: meal, nutrients: NutritionFacts(calories: kcal, protein: p, carbs: c, fat: f), date: now)
    }

    func testEmptyDay() {
        let summary = DailySummary(foods: [], goals: goals)
        XCTAssertEqual(summary.consumedCalories, 0)
        XCTAssertEqual(summary.remainingCalories, 2000)
        XCTAssertEqual(summary.calorieProgress, 0)
        XCTAssertFalse(summary.isOverGoal)
        XCTAssertEqual(summary.totals(for: .breakfast), .zero)
    }

    func testTotalsPerMealAndDay() {
        let foods = [
            food(.breakfast, kcal: 350.4, p: 12, c: 50, f: 9),
            food(.breakfast, kcal: 120, p: 10, c: 4, f: 6),
            food(.lunch, kcal: 640, p: 45, c: 60, f: 20),
            food(.snack, kcal: 95, p: 0.5, c: 25, f: 0.3),
        ]
        let summary = DailySummary(foods: foods, goals: goals)
        XCTAssertEqual(summary.totals(for: .breakfast).calories, 470.4, accuracy: 0.0001)
        XCTAssertEqual(summary.totals(for: .breakfast).protein, 22, accuracy: 0.0001)
        XCTAssertEqual(summary.totals(for: .lunch).calories, 640, accuracy: 0.0001)
        XCTAssertEqual(summary.totals(for: .dinner), .zero)
        XCTAssertEqual(summary.consumed.calories, 1205.4, accuracy: 0.0001)
        XCTAssertEqual(summary.consumedCalories, 1205)
        XCTAssertEqual(summary.remainingCalories, 795)
        XCTAssertEqual(summary.calorieProgress, 1205.4 / 2000, accuracy: 0.0001)
        XCTAssertEqual(summary.proteinProgress, 67.5 / 150, accuracy: 0.0001)
    }

    func testMealTotalsAddUpToDayTotal() {
        // Same idea as Android's randomized CalculateMealNutrientsTest, with a seeded generator.
        var generator = SeededGenerator(seed: 42)
        let foods = (0..<50).map { _ in
            food(MealType.allCases.randomElement(using: &generator)!,
                 kcal: Double(Int.random(in: 0..<2000, using: &generator)),
                 p: Double(Int.random(in: 0..<100, using: &generator)),
                 c: Double(Int.random(in: 0..<100, using: &generator)),
                 f: Double(Int.random(in: 0..<100, using: &generator)))
        }
        let summary = DailySummary(foods: foods, goals: goals)
        for meal in MealType.allCases {
            let expected = foods.filter { $0.mealType == meal }.reduce(0) { $0 + $1.nutrients.carbs }
            XCTAssertEqual(summary.totals(for: meal).carbs, expected, accuracy: 0.0001, meal.rawValue)
        }
        let mealSum = MealType.allCases.map { summary.totals(for: $0) }.sum()
        XCTAssertEqual(mealSum.calories, summary.consumed.calories, accuracy: 0.0001)
    }

    func testOverGoalProducesNegativeRemaining() {
        let summary = DailySummary(foods: [food(.dinner, kcal: 2300)], goals: goals)
        XCTAssertTrue(summary.isOverGoal)
        XCTAssertEqual(summary.remainingCalories, -300)
        XCTAssertEqual(summary.calorieProgress, 1.15, accuracy: 0.0001)
    }

    func testExactlyAtGoalIsNotOver() {
        let summary = DailySummary(foods: [food(.lunch, kcal: 2000)], goals: goals)
        XCTAssertFalse(summary.isOverGoal)
        XCTAssertEqual(summary.remainingCalories, 0)
    }

    func testZeroGoalDoesNotDivideByZero() {
        let summary = DailySummary(foods: [food(.lunch, kcal: 500)], goals: NutritionGoals(calories: 0, carbsGrams: 0, proteinGrams: 0, fatGrams: 0))
        XCTAssertEqual(summary.calorieProgress, 0)
        XCTAssertEqual(summary.carbsProgress, 0)
    }
}

final class MealTypeAndDateTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testSuggestedMealByTimeOfDay() {
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 7), calendar: calendar), .breakfast)
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 12, 30), calendar: calendar), .lunch)
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 16), calendar: calendar), .snack)
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 19), calendar: calendar), .dinner)
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 23), calendar: calendar), .snack)
        XCTAssertEqual(MealType.suggested(for: date(2026, 11, 21, 2), calendar: calendar), .snack)
    }

    func testMealTypeRawValuesMatchAndroid() {
        XCTAssertEqual(MealType.allCases.map(\.rawValue), ["breakfast", "lunch", "dinner", "snack"])
        XCTAssertEqual(GoalType.loseWeight.rawValue, "lose_weight")
        XCTAssertEqual(ActivityLevel.medium.rawValue, "medium")
    }

    func testDayInterval() {
        let interval = LogDate.dayInterval(containing: date(2026, 11, 21, 15), calendar: calendar)
        XCTAssertEqual(interval.start, date(2026, 11, 21, 0))
        XCTAssertEqual(interval.end, date(2026, 11, 22, 0))
    }

    func testEntryDateUsesNowForTodayAndNoonForOtherDays() {
        let now = date(2026, 11, 21, 18, 45)
        XCTAssertEqual(LogDate.entryDate(forDay: date(2026, 11, 21, 0), now: now, calendar: calendar), now)
        XCTAssertEqual(LogDate.entryDate(forDay: date(2026, 11, 18, 0), now: now, calendar: calendar), date(2026, 11, 18, 12))
    }
}

final class HistoryAggregatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func food(_ kcal: Double, on date: Date) -> LoggedFood {
        LoggedFood(mealType: .lunch, nutrients: NutritionFacts(calories: kcal, protein: 0, carbs: 0, fat: 0), date: date)
    }

    func testDailyTotalsGroupByDayNewestFirst() {
        let foods = [food(500, on: day(0, hour: 8)), food(700, on: day(0, hour: 20)), food(1800, on: day(-2))]
        let totals = HistoryAggregator.dailyTotals(for: foods, calendar: calendar)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[0].day, calendar.startOfDay(for: day(0)))
        XCTAssertEqual(totals[0].calories, 1200)
        XCTAssertEqual(totals[0].entryCount, 2)
        XCTAssertEqual(totals[1].calories, 1800)
    }

    func testLastDaysFillsGapsWithZero() {
        let foods = [food(500, on: day(0)), food(1800, on: day(-2)), food(999, on: day(-10))]
        let week = HistoryAggregator.lastDays(7, endingOn: day(0), foods: foods, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.day, calendar.startOfDay(for: day(-6)))
        XCTAssertEqual(week.last?.day, calendar.startOfDay(for: day(0)))
        XCTAssertEqual(week.map(\.calories), [0, 0, 0, 0, 1800, 0, 500])
    }

    func testAverageIgnoresEmptyDays() {
        let foods = [food(500, on: day(0)), food(1800, on: day(-2))]
        let week = HistoryAggregator.lastDays(7, endingOn: day(0), foods: foods, calendar: calendar)
        XCTAssertEqual(HistoryAggregator.averageCalories(of: week), 1150)
        XCTAssertNil(HistoryAggregator.averageCalories(of: []))
    }

    func testDaysOnTarget() {
        let foods = [food(1950, on: day(0)), food(2600, on: day(-1)), food(1850, on: day(-2))]
        let week = HistoryAggregator.lastDays(7, endingOn: day(0), foods: foods, calendar: calendar)
        XCTAssertEqual(HistoryAggregator.daysOnTarget(week, goal: 2000), 2)
    }
}

/// Deterministic generator so the randomized test is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
