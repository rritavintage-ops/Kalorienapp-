import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        let foods = entries.map(\.loggedFood)
        let goal = profileStore.goals.calories
        let week = HistoryAggregator.lastDays(7, endingOn: Date(), foods: foods)
        let days = HistoryAggregator.dailyTotals(for: foods)

        NavigationStack {
            List {
                if !days.isEmpty {
                    Section {
                        WeeklyOverviewCard(week: week, goal: goal)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Section("Logged days") {
                        ForEach(days) { day in
                            NavigationLink(value: day.day) {
                                DayHistoryRow(day: day, goal: goal)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if days.isEmpty {
                    ContentUnavailableView {
                        Label("No meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Meals you log will show up here, day by day.")
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
        }
    }
}

private struct WeeklyOverviewCard: View {
    let week: [DayTotal]
    let goal: Int

    var body: some View {
        let average = HistoryAggregator.averageCalories(of: week)
        let onTarget = HistoryAggregator.daysOnTarget(week, goal: goal)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last 7 days")
                        .font(.headline)
                    Text("Daily average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(average.map { Format.kcal($0) } ?? "–")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("history.average")
                        Text("kcal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("On target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(onTarget)/7")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
            }

            Chart {
                ForEach(week) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Calories", day.nutrients.calories)
                    )
                    .foregroundStyle(day.nutrients.calories > Double(goal) ? Theme.over.gradient : Theme.accent.gradient)
                    .cornerRadius(6)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(Format.kcal(goal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Calories per day for the last seven days")
        }
        .card()
        .padding(.top, 4)
    }
}

private struct DayHistoryRow: View {
    let day: DayTotal
    let goal: Int

    var body: some View {
        let progress = goal > 0 ? day.nutrients.calories / Double(goal) : 0
        let isOver = day.calories > goal
        HStack(spacing: 14) {
            MiniRing(progress: progress, isOverGoal: isOver)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayTitle.text(for: day.day, compact: true))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(day.entryCount) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.kcal(day.calories)) kcal")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("of \(Format.kcal(goal))")
                    .font(.caption)
                    .foregroundStyle(isOver ? Theme.over : .secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

enum DayTitle {
    /// "Today", "Yesterday" or e.g. "Thursday, 19 November" (Android: `parseDateText`).
    static func text(for day: Date, compact: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "Today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        if compact {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct DayDetailView: View {
    let day: Date
    @State private var coordinator: FoodLoggingCoordinator

    init(day: Date) {
        self.day = day
        _coordinator = State(initialValue: FoodLoggingCoordinator(day: day))
    }

    var body: some View {
        DayLogView(day: day, coordinator: coordinator)
            .navigationTitle(DayTitle.text(for: day))
            .navigationBarTitleDisplayMode(.inline)
            .foodLogging(coordinator)
    }
}
