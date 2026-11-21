import Foundation

public enum NumberInput {
    /// Parses user input such as "12", "12.5" or "12,5" (German keyboards). Returns `nil` for anything else.
    public static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let allowed = Set("0123456789.")
        guard normalized.allSatisfy({ allowed.contains($0) }),
              normalized.filter({ $0 == "." }).count <= 1,
              normalized != "."
        else {
            return nil
        }
        return Double(normalized)
    }

    /// Port of Android's `FilterOutDigits`: keeps ASCII digits only.
    public static func digitsOnly(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }
}
