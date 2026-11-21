import SwiftUI

/// Circular progress ring for the daily calorie goal. Animates from zero on appear.
struct CalorieRing: View {
    var progress: Double
    var isOverGoal: Bool
    var lineWidth: CGFloat = 18

    @State private var displayedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(displayedProgress, 0), 1))
                .stroke(ringStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (isOverGoal ? Theme.over : Theme.accent).opacity(0.25), radius: 6, y: 2)
        }
        .padding(lineWidth / 2)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.1)) {
                displayedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                displayedProgress = newValue
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Calorie progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }

    private var ringStyle: AnyShapeStyle {
        if isOverGoal {
            return AnyShapeStyle(Theme.over)
        }
        return AnyShapeStyle(
            AngularGradient(
                colors: [Theme.accentSecondary, Theme.accent, Theme.accent],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        )
    }
}

/// Small ring used in list rows (History).
struct MiniRing: View {
    var progress: Double
    var isOverGoal: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(isOverGoal ? Theme.over : Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// Horizontal progress bar for one macronutrient.
struct MacroProgressBar: View {
    var title: LocalizedStringKey
    var consumed: Double
    var goal: Int
    var color: Color

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(max(consumed / Double(goal), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Capsule()
                .fill(color.opacity(0.15))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color)
                            .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                    }
                }
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: fraction)
            Text("\(Format.grams(consumed)) / \(goal) g")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
