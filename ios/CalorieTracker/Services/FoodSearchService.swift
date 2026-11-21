import Foundation

/// Searches a food database (Android: `TrackerRepository.searchFood`).
protocol FoodSearching: Sendable {
    func search(_ query: String) async throws -> [TrackableFood]
}

/// Open Food Facts search, the same public database the Android app uses. No API key required.
struct OpenFoodFactsService: FoodSearching {
    var session: URLSession = .shared

    func search(_ query: String) async throws -> [TrackableFood] {
        guard let url = OpenFoodFactsAPI.searchURL(query: query) else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(OpenFoodFactsAPI.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try OpenFoodFactsAPI.parseSearchResponse(data)
    }
}

/// Offline food list for UI tests and previews.
struct MockFoodSearch: FoodSearching {
    static let foods: [TrackableFood] = [
        TrackableFood(id: "banana", name: "Banana", brand: nil, imageURL: nil,
                      per100g: NutritionFacts(calories: 89, protein: 1.1, carbs: 22.8, fat: 0.3)),
        TrackableFood(id: "greek-yogurt", name: "Greek yogurt", brand: "Dairy Farm", imageURL: nil,
                      per100g: NutritionFacts(calories: 97, protein: 9, carbs: 3.6, fat: 5)),
        TrackableFood(id: "oats", name: "Rolled oats", brand: "Good Oats", imageURL: nil,
                      per100g: NutritionFacts(calories: 379, protein: 13.2, carbs: 67.7, fat: 6.5)),
        TrackableFood(id: "whole-milk", name: "Whole milk", brand: nil, imageURL: nil,
                      per100g: NutritionFacts(calories: 64, protein: 3.3, carbs: 4.8, fat: 3.6)),
    ]

    func search(_ query: String) async throws -> [TrackableFood] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        try await Task.sleep(for: .milliseconds(200))
        return Self.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}
