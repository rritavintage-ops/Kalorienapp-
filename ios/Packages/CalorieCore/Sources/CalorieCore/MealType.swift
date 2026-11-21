import Foundation

public enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    public var id: String { rawValue }

    /// The meal a user most likely means when logging food at `date`.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

public enum EntrySource: String, Codable, CaseIterable, Sendable {
    case scan
    case search
    case manual
}

public enum LogDate {
    /// The half-open interval `[start of day, start of next day)` containing `date`.
    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// Timestamp for a new entry logged for `day`: now when `day` is today, otherwise noon of that day.
    public static func entryDate(forDay day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            return now
        }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }
}
