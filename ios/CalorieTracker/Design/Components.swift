import SwiftUI
import UIKit

/// Rounded card background used across the app.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Full-width primary action button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.3)))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tappable card used for single-choice questions (onboarding).
struct ChoiceCard: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var symbol: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isSelected ? Color.white : Theme.accent)
                    .background(Circle().fill(isSelected ? Theme.accent : Theme.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Decimal text field bound to a `Double`, committing on every keystroke so a tap on "Save"
/// never loses the last edit. Accepts both "." and "," as decimal separators.
struct NumberField: View {
    var title: LocalizedStringKey
    @Binding var value: Double
    var unit: String
    var fractionDigits: Int = 1
    var identifier: String?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(minWidth: 60, maxWidth: 120)
                .monospacedDigit()
                .accessibilityIdentifier(identifier ?? "")
                .onChange(of: text) { _, newText in
                    guard isFocused else { return }
                    if let parsed = NumberInput.parseDecimal(newText) {
                        value = parsed
                    } else if newText.trimmingCharacters(in: .whitespaces).isEmpty {
                        value = 0
                    }
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .leading)
        }
        .onAppear { text = Format.editable(value, fractionDigits: fractionDigits) }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                text = Format.editable(newValue, fractionDigits: fractionDigits)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                text = Format.editable(value, fractionDigits: fractionDigits)
            }
        }
    }
}

/// Square thumbnail for a diary entry: the meal photo, a product image, or the meal symbol.
struct FoodThumbnail: View {
    var photoData: Data?
    var imageURL: URL?
    var meal: MealType
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Theme.color(for: meal).opacity(0.14)
            Image(systemName: meal.symbol)
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.color(for: meal))
        }
    }
}

/// "● P 30  ● C 20  ● F 10" style macro summary, always on one line.
struct MacroSummaryText: View {
    var nutrients: NutritionFacts

    var body: some View {
        Text(attributed)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var attributed: AttributedString {
        let parts: [(String, Double, Color)] = [
            ("P", nutrients.protein, Theme.protein),
            ("C", nutrients.carbs, Theme.carbs),
            ("F", nutrients.fat, Theme.fat),
        ]
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result += AttributedString("  ")
            }
            var dot = AttributedString("● ")
            dot.foregroundColor = part.2
            var label = AttributedString("\(part.0) \(Format.grams(part.1))")
            label.foregroundColor = Color.secondary
            result += dot
            result += label
        }
        return result
    }
}

/// Segmented meal picker.
struct MealPicker: View {
    @Binding var selection: MealType

    var body: some View {
        Picker("Meal", selection: $selection) {
            ForEach(MealType.allCases) { meal in
                Text(meal.name).tag(meal)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mealPicker")
    }
}
