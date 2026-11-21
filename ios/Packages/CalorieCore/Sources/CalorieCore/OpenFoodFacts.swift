import Foundation

/// A food from a database search, with nutrients per 100 g (Android: `TrackableFood`).
public struct TrackableFood: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var brand: String?
    public var imageURL: URL?
    public var per100g: NutritionFacts

    public init(id: String, name: String, brand: String?, imageURL: URL?, per100g: NutritionFacts) {
        self.id = id
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.per100g = per100g
    }

    public func draft(grams: Double) -> FoodDraft {
        FoodDraft(name: name, grams: grams, per100g: per100g)
    }
}

// MARK: - DTOs

public struct OpenFoodFactsSearchResponse: Decodable, Sendable {
    public var products: [OpenFoodFactsProduct]

    enum CodingKeys: String, CodingKey {
        case products
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = (try? container.decodeIfPresent([OpenFoodFactsProduct].self, forKey: .products)) ?? []
    }
}

public struct OpenFoodFactsProduct: Decodable, Sendable {
    public var code: String?
    public var productName: String?
    public var brands: String?
    public var imageFrontThumbURL: String?
    public var nutriments: Nutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case imageFrontThumbURL = "image_front_thumb_url"
        case nutriments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        productName = try? container.decodeIfPresent(String.self, forKey: .productName)
        brands = try? container.decodeIfPresent(String.self, forKey: .brands)
        imageFrontThumbURL = try? container.decodeIfPresent(String.self, forKey: .imageFrontThumbURL)
        nutriments = try? container.decodeIfPresent(Nutriments.self, forKey: .nutriments)
    }

    public struct Nutriments: Decodable, Sendable {
        public var energyKcal100g: Double?
        public var energyKJ100g: Double?
        public var carbohydrates100g: Double?
        public var proteins100g: Double?
        public var fat100g: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case energyKJ100g = "energy-kj_100g"
            case energy100g = "energy_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case proteins100g = "proteins_100g"
            case fat100g = "fat_100g"
        }

        public init(energyKcal100g: Double?, energyKJ100g: Double?, carbohydrates100g: Double?, proteins100g: Double?, fat100g: Double?) {
            self.energyKcal100g = energyKcal100g
            self.energyKJ100g = energyKJ100g
            self.carbohydrates100g = carbohydrates100g
            self.proteins100g = proteins100g
            self.fat100g = fat100g
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func value(_ key: CodingKeys) -> Double? {
                guard let flexible = try? container.decodeIfPresent(FlexibleDouble.self, forKey: key) else {
                    return nil
                }
                return flexible.value
            }
            energyKcal100g = value(.energyKcal100g)
            // `energy_100g` is always kJ in Open Food Facts.
            energyKJ100g = value(.energyKJ100g) ?? value(.energy100g)
            carbohydrates100g = value(.carbohydrates100g)
            proteins100g = value(.proteins100g)
            fat100g = value(.fat100g)
        }
    }
}

/// Open Food Facts sometimes encodes numbers as strings ("12.5").
struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
        } else if let text = try? container.decode(String.self) {
            value = NumberInput.parseDecimal(text)
        } else {
            value = nil
        }
    }
}

// MARK: - API helpers

public enum OpenFoodFactsAPI {
    public static let baseURL = URL(string: "https://world.openfoodfacts.org")!
    /// Open Food Facts asks API clients to identify themselves.
    public static let userAgent = "CalorieTracker-iOS/1.0"
    public static let kilojoulesPerKilocalorie = 4.184

    public static func searchURL(query: String, page: Int = 1, pageSize: Int = 30) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("cgi/search.pl"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: String(min(max(1, pageSize), 100))),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,image_front_thumb_url"),
        ]
        return components?.url
    }

    public static func parseSearchResponse(_ data: Data) throws -> [TrackableFood] {
        let response = try JSONDecoder().decode(OpenFoodFactsSearchResponse.self, from: data)
        return trackableFoods(from: response.products)
    }

    public static func trackableFoods(from products: [OpenFoodFactsProduct]) -> [TrackableFood] {
        var seen = Set<String>()
        var foods: [TrackableFood] = []
        for product in products {
            guard let food = trackableFood(from: product), !seen.contains(food.id) else { continue }
            seen.insert(food.id)
            foods.append(food)
        }
        return foods
    }

    /// Maps a product to a `TrackableFood`, or `nil` when the name or nutrients are missing or implausible.
    public static func trackableFood(from product: OpenFoodFactsProduct) -> TrackableFood? {
        guard
            let rawName = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawName.isEmpty,
            let nutriments = product.nutriments,
            let carbs = nutriments.carbohydrates100g,
            let protein = nutriments.proteins100g,
            let fat = nutriments.fat100g
        else {
            return nil
        }
        let kcal = nutriments.energyKcal100g ?? nutriments.energyKJ100g.map { $0 / kilojoulesPerKilocalorie }
        guard let calories = kcal else { return nil }

        // Android maps fat from `proteins100g` by mistake; this uses `fat_100g`.
        let per100g = NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
        guard isPlausible(per100g) else { return nil }

        let brand = product.brands?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let id = product.code.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(rawName.lowercased())|\(brand?.lowercased() ?? "")|\(Int(calories.rounded()))"
        let imageURL = product.imageFrontThumbURL.flatMap { URL(string: $0) }
        return TrackableFood(id: id, name: rawName, brand: brand, imageURL: imageURL, per100g: per100g)
    }

    /// Rejects data-entry errors: negative values, more than 100 g of macros per 100 g, impossible energy,
    /// or label energy that is far from the energy implied by the macros.
    public static func isPlausible(_ per100g: NutritionFacts) -> Bool {
        guard per100g.isValid else { return false }
        guard per100g.protein + per100g.carbs + per100g.fat <= 101 else { return false }
        guard per100g.calories <= 950 else { return false }
        let fromMacros = per100g.caloriesFromMacros
        let tolerance = max(20, 0.25 * max(per100g.calories, fromMacros))
        return abs(per100g.calories - fromMacros) <= tolerance
    }
}
