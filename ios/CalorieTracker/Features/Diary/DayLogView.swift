import SwiftData
import SwiftUI

/// Summary card plus the four meal sections for one day. Shared by Home (today) and History (past days).
struct DayLogView: View {
    let day: Date
    let coordinator: FoodLoggingCoordinator
    var bottomPadding: CGFloat = 0

    @Query private var entries: [FoodEntry]
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.launchOptions) private var launchOptions

    init(day: Date, coordinator: FoodLoggingCoordinator, bottomPadding: CGFloat = 0) {
        self.day = day
        self.coordinator = coordinator
        self.bottomPadding = bottomPadding
        let interval = LogDate.dayInterval(containing: day)
        let start = interval.start
        let end = interval.end
        _entries = Query(
            filter: #Predicate<FoodEntry> { entry in
                entry.date >= start && entry.date < end
            },
            sort: [SortDescriptor(\FoodEntry.date), SortDescriptor(\FoodEntry.createdAt)]
        )
    }

    private var summary: DailySummary {
        DailySummary(foods: entries.map(\.loggedFood), goals: profileStore.goals)
    }

    var body: some View {
        let summary = self.summary
        List {
            Section {
                DailySummaryCard(summary: summary, day: day)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(MealType.allCases) { meal in
                MealSection(
                    meal: meal,
                    entries: entries.filter { $0.mealType == meal },
                    totals: summary.totals(for: meal),
                    coordinator: coordinator,
                    launchOptions: launchOptions,
                    onDelete: delete
                )
            }

            if bottomPadding > 0 {
                Color.clear
                    .frame(height: bottomPadding)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func delete(_ entry: FoodEntry) {
        withAnimation(.snappy) {
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }
}

/// Ring with remaining calories, goal / eaten / remaining stats and macro bars.
struct DailySummaryCard: View {
    let summary: DailySummary
    let day: Date

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center, spacing: 22) {
                ZStack {
                    CalorieRing(progress: summary.calorieProgress, isOverGoal: summary.isOverGoal)
                    VStack(spacing: 0) {
                        Text(Format.kcal(abs(summary.remainingCalories)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(summary.remainingCalories)))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .accessibilityIdentifier("summary.remaining")
                        Text(summary.isOverGoal ? "kcal over" : "kcal left")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(summary.isOverGoal ? Theme.over : .secondary)
                    }
                    .padding(.horizontal, 22)
                    .animation(.snappy, value: summary.remainingCalories)
                }
                .frame(width: 156, height: 156)

                VStack(alignment: .leading, spacing: 14) {
                    StatLine(title: "Goal", value: summary.goals.calories, symbol: "flag.fill", tint: .secondary, identifier: "summary.goal")
                    StatLine(title: "Eaten", value: summary.consumedCalories, symbol: "fork.knife", tint: Theme.accent, identifier: "summary.consumed")
                    StatLine(
                        title: summary.isOverGoal ? "Over" : "Remaining",
                        value: abs(summary.remainingCalories),
                        symbol: summary.isOverGoal ? "exclamationmark.circle.fill" : "hourglass",
                        tint: summary.isOverGoal ? Theme.over : Theme.accentSecondary,
                        identifier: "summary.remainingStat"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 14) {
                MacroProgressBar(title: "Carbs", consumed: summary.consumed.carbs, goal: summary.goals.carbsGrams, color: Theme.carbs)
                MacroProgressBar(title: "Protein", consumed: summary.consumed.protein, goal: summary.goals.proteinGrams, color: Theme.protein)
                MacroProgressBar(title: "Fat", consumed: summary.consumed.fat, goal: summary.goals.fatGrams, color: Theme.fat)
            }
        }
        .card(padding: 20)
        .padding(.top, 4)
    }
}

private struct StatLine: View {
    var title: LocalizedStringKey
    var value: Int
    var symbol: String
    var tint: Color
    var identifier: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.kcal(value))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(value)))
                        .accessibilityIdentifier(identifier)
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy, value: value)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One meal (breakfast, lunch, dinner, snacks) with its entries and an add menu.
struct MealSection: View {
    let meal: MealType
    let entries: [FoodEntry]
    let totals: NutritionFacts
    let coordinator: FoodLoggingCoordinator
    let launchOptions: LaunchOptions
    let onDelete: (FoodEntry) -> Void

    var body: some View {
        Section {
            ForEach(entries) { entry in
                Button {
                    coordinator.edit(entry)
                } label: {
                    FoodEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("entry.\(entry.name)")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        coordinator.edit(entry)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Menu {
                Button {
                    coordinator.startCamera(meal: meal, launchOptions: launchOptions)
                } label: {
                    Label("Scan with camera", systemImage: "camera")
                }
                Button {
                    coordinator.startPhotoLibrary(meal: meal)
                } label: {
                    Label("Choose photo", systemImage: "photo.on.rectangle")
                }
                Button {
                    coordinator.startSearch(meal: meal)
                } label: {
                    Label("Search food", systemImage: "magnifyingglass")
                }
                Button {
                    coordinator.startManualEntry(meal: meal)
                } label: {
                    Label("Enter manually", systemImage: "square.and.pencil")
                }
            } label: {
                Label("Add food", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("addFood.\(meal.rawValue)")
        } header: {
            HStack(spacing: 8) {
                Image(systemName: meal.symbol)
                    .foregroundStyle(Theme.color(for: meal))
                Text(meal.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Format.kcal(totals.calories)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(totals.calories > 0 ? Color.primary : Color.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("mealTotal.\(meal.rawValue)")
            }
            .textCase(nil)
            .padding(.horizontal, 4)
        }
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        let nutrients = entry.nutrients
        HStack(spacing: 12) {
            FoodThumbnail(photoData: entry.photoData, imageURL: entry.imageURL, meal: entry.mealType)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(Format.grams(entry.grams)) g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MacroSummaryText(nutrients: nutrients)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.kcal(nutrients.calories))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
