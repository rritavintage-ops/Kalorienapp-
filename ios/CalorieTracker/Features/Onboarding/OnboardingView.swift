import SwiftUI

/// Steps of the questionnaire (Android: Welcome → Gender → Age → Height → Weight → Activity → Goal → NutrientGoal).
enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case gender
    case age
    case height
    case weight
    case activity
    case goal
    case macros
    case summary

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// Progress through the questions (welcome excluded).
    var progress: Double {
        Double(rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
}

struct OnboardingView: View {
    @Environment(ProfileStore.self) private var store
    @State private var step: OnboardingStep = .welcome
    @State private var isMovingForward = true
    @State private var gender: Gender?
    @State private var profile = UserProfile.default
    @State private var macros = MacroPercents(ratios: .balanced)

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
                    .transition(.opacity)
            }

            ZStack {
                content
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Button(primaryTitle) {
                advance()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .accessibilityIdentifier("onboarding.next")
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("onboarding.back")

            ProgressView(value: step.progress)
                .tint(Theme.accent)
                .animation(.snappy, value: step)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .gender:
            QuestionStep(title: "What's your gender?", subtitle: "Used to estimate your basal metabolic rate.") {
                VStack(spacing: 12) {
                    ForEach(Gender.allCases) { option in
                        ChoiceCard(title: option.title, subtitle: nil, symbol: option.symbol, isSelected: gender == option) {
                            gender = option
                        }
                        .accessibilityIdentifier("onboarding.gender.\(option.rawValue)")
                    }
                }
            }
        case .age:
            QuestionStep(title: "How old are you?", subtitle: nil) {
                WheelPicker(selection: $profile.age, values: Array(UserProfile.ageRange), unit: "years") { "\($0)" }
            }
        case .height:
            QuestionStep(title: "How tall are you?", subtitle: nil) {
                WheelPicker(selection: heightBinding, values: Array(100...250), unit: "cm") { "\($0)" }
            }
        case .weight:
            QuestionStep(title: "What's your weight?", subtitle: nil) {
                WheelPicker(selection: $profile.weightKg, values: Self.weightOptions, unit: "kg") { Format.editable($0) }
            }
        case .activity:
            QuestionStep(title: "How active are you?", subtitle: nil) {
                VStack(spacing: 12) {
                    ForEach(ActivityLevel.allCases) { level in
                        ChoiceCard(title: level.title, subtitle: level.subtitle, symbol: level.symbol, isSelected: profile.activityLevel == level) {
                            profile.activityLevel = level
                        }
                        .accessibilityIdentifier("onboarding.activity.\(level.rawValue)")
                    }
                }
            }
        case .goal:
            QuestionStep(title: "What's your goal?", subtitle: nil) {
                VStack(spacing: 12) {
                    ForEach(GoalType.allCases) { goal in
                        ChoiceCard(title: goal.title, subtitle: goal.subtitle, symbol: goal.symbol, isSelected: profile.goalType == goal) {
                            profile.goalType = goal
                        }
                        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
                    }
                }
            }
        case .macros:
            QuestionStep(title: "Your nutrient goals", subtitle: "How your calories should split between carbs, protein and fat. You can change this later.") {
                MacroSplitEditor(percents: $macros)
                    .card()
            }
        case .summary:
            SummaryStep(profile: finalProfile)
        }
    }

    // MARK: Navigation

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .welcome: return "Let's go"
        case .summary: return "Start tracking"
        default: return "Next"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .gender: return gender != nil
        case .macros: return macros.isValid
        default: return true
        }
    }

    private var finalProfile: UserProfile {
        var result = profile
        result.gender = gender ?? .male
        if case .success(let ratios) = macros.validated {
            result.macroRatios = ratios
        }
        result.customCalorieGoal = nil
        return result
    }

    private func advance() {
        guard canAdvance else { return }
        if step == .summary {
            store.save(finalProfile)
            return
        }
        guard let next = step.next else { return }
        isMovingForward = true
        withAnimation(.snappy(duration: 0.35)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        isMovingForward = false
        withAnimation(.snappy(duration: 0.35)) {
            step = previous
        }
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { Int(profile.heightCm.rounded()) },
            set: { profile.heightCm = Double($0) }
        )
    }

    static let weightOptions: [Double] = Array(stride(from: 30.0, through: 250.0, by: 0.5))
}

// MARK: - Steps

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.12), lineWidth: 22)
                Circle()
                    .trim(from: 0, to: appeared ? 0.72 : 0)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "fork.knife")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 170, height: 170)
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Calorie Tracker")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Snap a photo of your meal and get calories and macros in seconds. First, let's find out a little about you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.2)) {
                appeared = true
            }
        }
    }
}

private struct QuestionStep<Content: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct WheelPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var values: [Value]
    var unit: String
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: 180)
            Text(unit)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 12)
    }
}

private struct SummaryStep: View {
    let profile: UserProfile

    var body: some View {
        let goals = NutritionCalculator.goals(for: profile)
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Your daily goal")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Based on your answers. You can adjust everything later in Profile.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                ZStack {
                    CalorieRing(progress: 1, isOverGoal: false, lineWidth: 20)
                    VStack(spacing: 2) {
                        Text(Format.kcal(goals.calories))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("onboarding.summary.goal")
                        Text("kcal per day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 220)

                HStack(spacing: 12) {
                    MacroGoalPill(title: "Carbs", grams: goals.carbsGrams, color: Theme.carbs)
                    MacroGoalPill(title: "Protein", grams: goals.proteinGrams, color: Theme.protein)
                    MacroGoalPill(title: "Fat", grams: goals.fatGrams, color: Theme.fat)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
