import Foundation

public enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case male
    case female

    public var id: String { rawValue }
}

public enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    /// Multiplier applied to the basal metabolic rate (same factors as the Android app).
    public var multiplier: Double {
        switch self {
        case .low: return 1.2
        case .medium: return 1.3
        case .high: return 1.4
        }
    }
}

public enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case loseWeight = "lose_weight"
    case keepWeight = "keep_weight"
    case gainWeight = "gain_weight"

    public var id: String { rawValue }

    /// Daily calorie adjustment in kcal (same values as the Android app).
    public var calorieAdjustment: Int {
        switch self {
        case .loseWeight: return -500
        case .keepWeight: return 0
        case .gainWeight: return 500
        }
    }
}

/// Everything needed to compute a personal calorie and macro goal.
public struct UserProfile: Codable, Equatable, Sendable {
    public var gender: Gender
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activityLevel: ActivityLevel
    public var goalType: GoalType
    public var macroRatios: MacroRatios
    /// When set, overrides the calculated daily calorie goal.
    public var customCalorieGoal: Int?

    public init(
        gender: Gender,
        age: Int,
        heightCm: Double,
        weightKg: Double,
        activityLevel: ActivityLevel,
        goalType: GoalType,
        macroRatios: MacroRatios = .balanced,
        customCalorieGoal: Int? = nil
    ) {
        self.gender = gender
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.goalType = goalType
        self.macroRatios = macroRatios
        self.customCalorieGoal = customCalorieGoal
    }

    /// Defaults shown at the start of onboarding (mirrors the Android onboarding defaults).
    public static let `default` = UserProfile(
        gender: .male,
        age: 20,
        heightCm: 180,
        weightKg: 80,
        activityLevel: .medium,
        goalType: .keepWeight,
        macroRatios: .balanced,
        customCalorieGoal: nil
    )

    public static let ageRange: ClosedRange<Int> = 13...100
    public static let heightRange: ClosedRange<Double> = 100...250
    public static let weightRange: ClosedRange<Double> = 30...300
    public static let customGoalRange: ClosedRange<Int> = 1000...6000
}
