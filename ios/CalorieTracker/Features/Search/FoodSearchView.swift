import SwiftData
import SwiftUI

/// Search Open Food Facts and log a food with a chosen amount (Android: `SearchScreen`).
struct FoodSearchView: View {
    let day: Date
    var onSaved: () -> Void = {}

    @Environment(\.foodSearch) private var foodSearch
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealType
    @State private var query = ""
    @State private var results: [TrackableFood] = []
    @State private var state: SearchState = .idle
    @State private var path: [Route] = []

    enum SearchState: Equatable {
        case idle
        case searching
        case loaded
        case failed
    }

    enum Route: Hashable {
        case food(TrackableFood)
        case manual
    }

    init(initialMeal: MealType, day: Date, onSaved: @escaping () -> Void = {}) {
        self.day = day
        self.onSaved = onSaved
        _meal = State(initialValue: initialMeal)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { food in
                            NavigationLink(value: Route.food(food)) {
                                TrackableFoodRow(food: food)
                            }
                            .accessibilityIdentifier("search.result.\(food.name)")
                        }
                    }
                }

                Section {
                    NavigationLink(value: Route.manual) {
                        Label("Enter food manually", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("search.manual")
                } footer: {
                    Text("Nutrition data from Open Food Facts.")
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                overlayContent
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods, e.g. oats")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .navigationTitle("Search food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .food(let food):
                    FoodAmountView(food: food, meal: $meal, day: day) {
                        onSaved()
                        dismiss()
                    }
                case .manual:
                    ManualEntryView(initialMeal: meal, day: day, showsCancel: false) {
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch state {
        case .searching:
            ProgressView("Searching…")
        case .failed:
            ContentUnavailableView {
                Label("Search failed", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try again") { Task { await search() } }
            }
        case .loaded where results.isEmpty:
            ContentUnavailableView.search(text: query)
        case .idle where results.isEmpty:
            ContentUnavailableView {
                Label("Find a food", systemImage: "magnifyingglass")
            } description: {
                Text("Search by name or brand, then choose how much you ate.")
            }
            .padding(.bottom, 120)
        default:
            EmptyView()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .searching
        results = []
        do {
            results = try await foodSearch.search(trimmed)
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed
        }
    }
}

private struct TrackableFoodRow: View {
    let food: TrackableFood

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: food.imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.accent.opacity(0.12)
                        Image(systemName: "fork.knife")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let brand = food.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MacroSummaryText(nutrients: food.per100g)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.kcal(food.per100g.calories))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("kcal / 100 g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Choose the amount of a database food and log it.
private struct FoodAmountView: View {
    let food: TrackableFood
    @Binding var meal: MealType
    let day: Date
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var grams: Double = 100

    private var nutrients: NutritionFacts {
        food.per100g.forPortion(grams: grams)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.title3.weight(.semibold))
                    if let brand = food.brand {
                        Text(brand)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                MealPicker(selection: $meal)
                    .listRowSeparator(.hidden)
            }

            Section("Amount") {
                NumberField(title: "Amount", value: $grams, unit: "g", fractionDigits: 0, identifier: "search.amount")
                Stepper("Adjust by 10 g", value: $grams, in: 0...FoodDraft.maximumGrams, step: 10)
            }

            Section("Nutrition") {
                LabeledContent("Calories", value: "\(Format.kcal(nutrients.calories)) kcal")
                LabeledContent("Protein", value: "\(Format.grams(nutrients.protein)) g")
                LabeledContent("Carbs", value: "\(Format.grams(nutrients.carbs)) g")
                LabeledContent("Fat", value: "\(Format.grams(nutrients.fat)) g")
            }
        }
        .navigationTitle("Add food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                add()
            } label: {
                Text("Add to \(meal.name) · \(Format.kcal(nutrients.calories)) kcal")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(grams <= 0)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .accessibilityIdentifier("search.add")
        }
    }

    private func add() {
        let entry = FoodEntry(
            draft: food.draft(grams: grams),
            mealType: meal,
            date: LogDate.entryDate(forDay: day),
            source: .search,
            imageURL: food.imageURL
        )
        modelContext.insert(entry)
        try? modelContext.save()
        onAdded()
    }
}
