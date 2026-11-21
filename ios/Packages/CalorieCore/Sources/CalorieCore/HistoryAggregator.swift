import Foundation

public struct DayTotal: Equatable, Identifiable, Sendable {
    /// Start of the day.
    public var day: Date
    public var nutrients: NutritionFacts
    public var entryCount: Int

    public var id: Date { day }

    public init(day: Date, nutrients: NutritionFacts, entryCount: Int) {
        self.day = day
        self.nutrients = nutrients
        self.entryCount = entryCount
    }

    public var calories: Int { Int(nutrients.calories.rounded()) }
}

public enum HistoryAggregator {
    /// One total per day that has at least one entry, newest first.
    public static func dailyTotals(for foods: [LoggedFood], calendar: Calendar = .current) -> [DayTotal] {
        var byDay: [Date: DayTotal] = [:]
        for food in foods {
            let day = calendar.startOfDay(for: food.date)
            var total = byDay[day] ?? DayTotal(day: day, nutrients: .zero, entryCount: 0)
            total.nutrients += food.nutrients
            total.entryCount += 1
            byDay[day] = total
        }
        return byDay.values.sorted { $0.day > $1.day }
    }

    /// `count` consecutive days ending with `lastDay`, oldest first. Days without entries have zero totals.
    public static func lastDays(_ count: Int, endingOn lastDay: Date, foods: [LoggedFood], calendar: Calendar = .current) -> [DayTotal] {
        guard count > 0 else { return [] }
        let totals = Dictionary(uniqueKeysWithValues: dailyTotals(for: foods, calendar: calendar).map { ($0.day, $0) })
        let end = calendar.startOfDay(for: lastDay)
        return (0..<count).reversed().compactMap { offset -> DayTotal? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return totals[day] ?? DayTotal(day: day, nutrients: .zero, entryCount: 0)
        }
    }

    /// Average calories over the days that have entries, or `nil` if there are none.
    public static func averageCalories(of days: [DayTotal]) -> Int? {
        let logged = days.filter { $0.entryCount > 0 }
        guard !logged.isEmpty else { return nil }
        let sum = logged.reduce(0.0) { $0 + $1.nutrients.calories }
        return Int((sum / Double(logged.count)).rounded())
    }

    /// Number of days in `days` whose calories stayed within `tolerance` of the goal (and had entries).
    public static func daysOnTarget(_ days: [DayTotal], goal: Int, tolerance: Double = 0.1) -> Int {
        guard goal > 0 else { return 0 }
        return days.filter { day in
            day.entryCount > 0 && abs(day.nutrients.calories - Double(goal)) <= Double(goal) * tolerance
        }.count
    }
}
