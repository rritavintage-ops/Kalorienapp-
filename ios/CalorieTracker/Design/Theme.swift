import SwiftUI
import UIKit

enum Theme {
    static let accent = Color("AccentColor")
    static let accentSecondary = Color(hex: 0x00C7BE)

    static let carbs = Color(hex: 0x0A84FF)
    static let protein = Color(hex: 0xFF375F)
    static let fat = Color(hex: 0xFFB800)
    static let over = Color(hex: 0xFF6B3D)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 16

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func color(for meal: MealType) -> Color {
        switch meal {
        case .breakfast: return Color(hex: 0xFF9F0A)
        case .lunch: return Color(hex: 0x30B0C7)
        case .dinner: return Color(hex: 0x5E5CE6)
        case .snack: return Color(hex: 0xFF2D55)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Display names

extension MealType {
    var title: LocalizedStringKey {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snacks"
        }
    }

    /// Short, plain-string name (used in button labels like "Add to Lunch").
    var name: String {
        switch self {
        case .breakfast: return String(localized: "Breakfast")
        case .lunch: return String(localized: "Lunch")
        case .dinner: return String(localized: "Dinner")
        case .snack: return String(localized: "Snack")
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
        }
    }
}

extension Gender {
    var title: LocalizedStringKey {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }

    var symbol: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        }
    }
}

extension ActivityLevel {
    var title: LocalizedStringKey {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .low: return "Mostly sitting, little exercise"
        case .medium: return "On your feet often or exercise 2–3× a week"
        case .high: return "Physical job or exercise most days"
        }
    }

    var symbol: String {
        switch self {
        case .low: return "figure.seated.side"
        case .medium: return "figure.walk"
        case .high: return "figure.run"
        }
    }
}

extension GoalType {
    var title: LocalizedStringKey {
        switch self {
        case .loseWeight: return "Lose weight"
        case .keepWeight: return "Keep weight"
        case .gainWeight: return "Gain weight"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .loseWeight: return "500 kcal below your daily need"
        case .keepWeight: return "Eat what your body uses"
        case .gainWeight: return "500 kcal above your daily need"
        }
    }

    var symbol: String {
        switch self {
        case .loseWeight: return "arrow.down.right"
        case .keepWeight: return "equal"
        case .gainWeight: return "arrow.up.right"
        }
    }
}

// MARK: - Number formatting

enum Format {
    static func kcal(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    static func kcal(_ value: Int) -> String {
        value.formatted()
    }

    static func grams(_ value: Double) -> String {
        let rounded = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
        return rounded.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Value for a text field (no grouping separators so it parses back).
    static func editable(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)).grouping(.never))
    }
}
