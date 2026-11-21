import SwiftData
import SwiftUI
import UIKit

/// Form for editing a food's name, portion and nutrients.
/// Changing the amount rescales the nutrients; changing a nutrient keeps the amount.
/// Has no NavigationStack of its own so it can be pushed or wrapped in a sheet.
struct FoodDraftForm: View {
    @Binding var draft: FoodDraft
    /// When non-nil a meal picker is shown.
    var meal: Binding<MealType>?
    var photo: UIImage?

    var body: some View {
        Form {
            if let photo {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                }
            }

            Section("Food") {
                TextField("Name, e.g. Banana", text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.name")
                if let meal {
                    MealPicker(selection: meal)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                NumberField(title: "Amount", value: $draft.grams, unit: "g", fractionDigits: 0, identifier: "editor.grams")
                HStack(spacing: 10) {
                    PortionButton(title: "½×") { draft.scalePortion(by: 0.5) }
                    PortionButton(title: "−10 g") { draft.grams = max(1, draft.grams - 10) }
                    PortionButton(title: "+10 g") { draft.grams = min(FoodDraft.maximumGrams, draft.grams + 10) }
                    PortionButton(title: "2×") { draft.scalePortion(by: 2) }
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Portion")
            } footer: {
                if let portion = draft.portionDescription {
                    Text("Estimated portion: \(portion)")
                }
            }

            Section {
                NumberField(title: "Calories", value: portionBinding(\.calories), unit: "kcal", fractionDigits: 0, identifier: "editor.calories")
                NumberField(title: "Protein", value: portionBinding(\.protein), unit: "g", identifier: "editor.protein")
                NumberField(title: "Carbs", value: portionBinding(\.carbs), unit: "g", identifier: "editor.carbs")
                NumberField(title: "Fat", value: portionBinding(\.fat), unit: "g", identifier: "editor.fat")
            } header: {
                Text("Nutrition for this portion")
            } footer: {
                Text("Changing the amount scales these values automatically.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private func portionBinding(_ keyPath: WritableKeyPath<NutritionFacts, Double>) -> Binding<Double> {
        Binding(
            get: { draft.totals[keyPath: keyPath] },
            set: { draft.setPortionValue(keyPath, to: $0) }
        )
    }
}

private struct PortionButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.borderless)
    }
}

/// Editing an existing diary entry, with delete.
struct EntryEditorView: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FoodDraft
    @State private var meal: MealType
    @State private var isConfirmingDelete = false

    init(entry: FoodEntry) {
        self.entry = entry
        _draft = State(initialValue: entry.draft)
        _meal = State(initialValue: entry.mealType)
    }

    var body: some View {
        NavigationStack {
            FoodDraftForm(draft: $draft, meal: $meal, photo: entry.photoData.flatMap(UIImage.init(data:)))
                .safeAreaInset(edge: .bottom) {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("editor.delete")
                }
                .navigationTitle("Edit food")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!draft.isValid)
                            .accessibilityIdentifier("editor.save")
                    }
                }
                .confirmationDialog("Delete this entry?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete() }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private func save() {
        entry.apply(draft, mealType: meal)
        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        modelContext.delete(entry)
        try? modelContext.save()
        dismiss()
    }
}

/// Adding a food by hand (also the fallback when the scanner is unavailable).
struct ManualEntryView: View {
    let day: Date
    var showsCancel = true
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoodDraft.empty()
    @State private var meal: MealType

    init(initialMeal: MealType, day: Date, showsCancel: Bool = true, onSaved: @escaping () -> Void = {}) {
        self.day = day
        self.showsCancel = showsCancel
        self.onSaved = onSaved
        _meal = State(initialValue: initialMeal)
    }

    var body: some View {
        FoodDraftForm(draft: $draft, meal: $meal)
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("editor.save")
                }
            }
    }

    private func save() {
        let entry = FoodEntry(draft: draft, mealType: meal, date: LogDate.entryDate(forDay: day), source: .manual)
        modelContext.insert(entry)
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}
