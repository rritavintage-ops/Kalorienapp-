import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingReset = false

    private var profile: Binding<UserProfile> {
        Binding(
            get: { store.currentProfile },
            set: { store.save($0) }
        )
    }

    var body: some View {
        let current = store.currentProfile
        let goals = store.goals

        NavigationStack {
            Form {
                Section {
                    GoalHeader(goals: goals, isCustom: current.customCalorieGoal != nil)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Body") {
                    Picker("Gender", selection: profile.gender) {
                        ForEach(Gender.allCases) { gender in
                            Text(gender.title).tag(gender)
                        }
                    }
                    Stepper(value: profile.age, in: UserProfile.ageRange) {
                        LabeledContent("Age", value: "\(current.age) years")
                    }
                    .accessibilityIdentifier("profile.age")
                    Stepper(value: profile.heightCm, in: UserProfile.heightRange, step: 1) {
                        LabeledContent("Height", value: "\(Int(current.heightCm)) cm")
                    }
                    Stepper(value: profile.weightKg, in: UserProfile.weightRange, step: 0.5) {
                        LabeledContent("Weight", value: "\(Format.editable(current.weightKg)) kg")
                    }
                    .accessibilityIdentifier("profile.weight")
                }

                Section("Lifestyle") {
                    Picker("Activity level", selection: profile.activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Picker("Goal", selection: profile.goalType) {
                        ForEach(GoalType.allCases) { goal in
                            Text(goal.title).tag(goal)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        MacroSplitScreen(ratios: current.macroRatios) { ratios in
                            store.update { $0.macroRatios = ratios }
                        }
                    } label: {
                        LabeledContent(
                            "Macro split",
                            value: "\(current.macroRatios.carbsPercent) / \(current.macroRatios.proteinPercent) / \(current.macroRatios.fatPercent) %"
                        )
                    }
                    Toggle("Custom calorie goal", isOn: customGoalEnabled)
                        .accessibilityIdentifier("profile.customGoalToggle")
                    if let custom = current.customCalorieGoal {
                        Stepper(value: customGoalValue(default: custom), in: UserProfile.customGoalRange, step: 50) {
                            LabeledContent("Daily goal", value: "\(Format.kcal(custom)) kcal")
                        }
                    }
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Carbs / protein / fat. Your goal is calculated with the Harris–Benedict formula from your body data, activity level and goal.")
                }

                Section {
                    Button("Reset all data", role: .destructive) {
                        isConfirmingReset = true
                    }
                } footer: {
                    Text("Calorie Tracker provides estimates for general wellness and is not medical advice.")
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog(
                "Delete all meals and your profile?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private var customGoalEnabled: Binding<Bool> {
        Binding(
            get: { store.currentProfile.customCalorieGoal != nil },
            set: { enabled in
                store.update { profile in
                    profile.customCalorieGoal = enabled ? NutritionCalculator.calculatedDailyCalories(for: profile) : nil
                }
            }
        )
    }

    private func customGoalValue(default value: Int) -> Binding<Int> {
        Binding(
            get: { store.currentProfile.customCalorieGoal ?? value },
            set: { newValue in store.update { $0.customCalorieGoal = newValue } }
        )
    }

    private func resetAll() {
        try? modelContext.delete(model: FoodEntry.self)
        try? modelContext.save()
        store.reset()
    }
}

private struct GoalHeader: View {
    let goals: NutritionGoals
    let isCustom: Bool

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Daily goal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.kcal(goals.calories))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(goals.calories)))
                        .accessibilityIdentifier("profile.goal")
                    Text("kcal")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy, value: goals.calories)
                Text(isCustom ? "Custom goal" : "Calculated from your profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                MacroGoalPill(title: "Carbs", grams: goals.carbsGrams, color: Theme.carbs)
                MacroGoalPill(title: "Protein", grams: goals.proteinGrams, color: Theme.protein)
                MacroGoalPill(title: "Fat", grams: goals.fatGrams, color: Theme.fat)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct MacroGoalPill: View {
    var title: LocalizedStringKey
    var grams: Int
    var color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(grams) g")
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Pushed from Profile: edit and save the macro split.
private struct MacroSplitScreen: View {
    @State private var percents: MacroPercents
    let onSave: (MacroRatios) -> Void
    @Environment(\.dismiss) private var dismiss

    init(ratios: MacroRatios, onSave: @escaping (MacroRatios) -> Void) {
        _percents = State(initialValue: MacroPercents(ratios: ratios))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                MacroSplitEditor(percents: $percents)
            } footer: {
                Text("The three values must add up to 100 %.")
            }
        }
        .navigationTitle("Macro split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if case .success(let ratios) = percents.validated {
                        onSave(ratios)
                        dismiss()
                    }
                }
                .disabled(!percents.isValid)
            }
        }
    }
}

/// Integer percentages being edited.
struct MacroPercents: Equatable {
    var carbs: Int
    var protein: Int
    var fat: Int

    init(carbs: Int, protein: Int, fat: Int) {
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }

    init(ratios: MacroRatios) {
        self.init(carbs: ratios.carbsPercent, protein: ratios.proteinPercent, fat: ratios.fatPercent)
    }

    var total: Int { carbs + protein + fat }

    var validated: Result<MacroRatios, MacroValidationError> {
        MacroRatioValidator.validate(carbsPercent: carbs, proteinPercent: protein, fatPercent: fat)
    }

    var isValid: Bool {
        if case .success = validated { return true }
        return false
    }
}

/// Presets plus three steppers (5 % steps) with a live total.
struct MacroSplitEditor: View {
    @Binding var percents: MacroPercents

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MacroPreset.all) { preset in
                        let isSelected = MacroPercents(ratios: preset.ratios) == percents
                        Button {
                            withAnimation(.snappy) { percents = MacroPercents(ratios: preset.ratios) }
                        } label: {
                            Text(preset.name)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(isSelected ? Theme.accent : Theme.accent.opacity(0.12)))
                                .foregroundStyle(isSelected ? Color.white : Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            MacroStepper(title: "Carbs", value: $percents.carbs, color: Theme.carbs)
            MacroStepper(title: "Protein", value: $percents.protein, color: Theme.protein)
            MacroStepper(title: "Fat", value: $percents.fat, color: Theme.fat)

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label("\(percents.total) %", systemImage: percents.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(percents.isValid ? Theme.accent : Theme.over)
                    .contentTransition(.numericText(value: Double(percents.total)))
                    .accessibilityIdentifier("macros.total")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacroStepper: View {
    var title: LocalizedStringKey
    @Binding var value: Int
    var color: Color

    var body: some View {
        Stepper(value: $value, in: 0...100, step: 5) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title)
                Spacer()
                Text("\(value) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
