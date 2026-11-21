import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Wire format of the meal-scan backend (see backend/src/schema.ts). Keep both sides in sync.

public enum ScanConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScanConfidence(rawValue: raw.lowercased()) ?? .medium
    }
}

public struct MealScanRequest: Codable, Equatable, Sendable {
    public var imageBase64: String
    public var mediaType: String
    public var locale: String?
    public var note: String?

    public init(imageBase64: String, mediaType: String, locale: String?, note: String?) {
        self.imageBase64 = imageBase64
        self.mediaType = mediaType
        self.locale = locale
        self.note = note
    }
}

public struct ScannedFoodItem: Codable, Equatable, Sendable {
    public var name: String
    /// Human-readable portion, e.g. "1 medium bowl".
    public var portion: String?
    public var grams: Double
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var confidence: ScanConfidence

    public init(name: String, portion: String?, grams: Double, calories: Double, protein: Double, carbs: Double, fat: Double, confidence: ScanConfidence) {
        self.name = name
        self.portion = portion
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case name, portion, grams, calories, protein, carbs, fat, confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        portion = try container.decodeIfPresent(String.self, forKey: .portion)
        grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        confidence = try container.decodeIfPresent(ScanConfidence.self, forKey: .confidence) ?? .medium
    }

    public var portionTotals: NutritionFacts {
        NutritionFacts(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

public struct MealScanResponse: Codable, Equatable, Sendable {
    public var containsFood: Bool
    public var mealName: String?
    public var items: [ScannedFoodItem]
    public var notes: String?

    public init(containsFood: Bool, mealName: String?, items: [ScannedFoodItem], notes: String?) {
        self.containsFood = containsFood
        self.mealName = mealName
        self.items = items
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case containsFood, mealName, items, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ScannedFoodItem].self, forKey: .items) ?? []
        containsFood = try container.decodeIfPresent(Bool.self, forKey: .containsFood) ?? !items.isEmpty
        mealName = try container.decodeIfPresent(String.self, forKey: .mealName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public static let maximumItems = 20

    /// Editable drafts for the review screen. Items without a name are dropped and negative values clamped.
    public func drafts() -> [FoodDraft] {
        items.prefix(Self.maximumItems).compactMap { item -> FoodDraft? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let portion = item.portion?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FoodDraft(
                name: name,
                grams: min(item.grams.rounded(), FoodDraft.maximumGrams),
                portionTotals: item.portionTotals,
                portionDescription: (portion?.isEmpty ?? true) ? nil : portion,
                confidence: item.confidence
            )
        }
    }
}

public struct MealScanErrorEnvelope: Codable, Equatable, Sendable {
    public struct Body: Codable, Equatable, Sendable {
        public var code: String
        public var message: String?
    }

    public var error: Body
}

public enum MealScanError: Error, Equatable, LocalizedError, Sendable {
    case notConfigured
    case imageTooLarge
    case unauthorized
    case rateLimited
    case offline
    case timedOut
    case server(message: String?)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Food scanning isn't set up in this build yet. You can still add the meal manually."
        case .imageTooLarge:
            return "This photo is too large to analyze. Please try another one."
        case .unauthorized:
            return "The scanning service rejected this app. Please update the app and try again."
        case .rateLimited:
            return "You've scanned a lot in a short time. Please wait a minute and try again."
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The analysis took too long. Please try again."
        case .server(let message):
            return message ?? "The scanning service is unavailable right now. Please try again."
        case .invalidResponse:
            return "We couldn't read the analysis result. Please try again."
        }
    }
}

public enum MealScanAPI {
    public static let path = "v1/meal-scans"
    public static let maximumImageBytes = 4_500_000

    public static func endpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent(path)
    }

    public static func makeRequest(
        baseURL: URL,
        imageJPEG: Data,
        locale: String?,
        note: String? = nil,
        clientToken: String?,
        installationID: String?
    ) throws -> URLRequest {
        guard !imageJPEG.isEmpty else { throw MealScanError.invalidResponse }
        guard imageJPEG.count <= maximumImageBytes else { throw MealScanError.imageTooLarge }

        var request = URLRequest(url: endpoint(baseURL: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = clientToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let installationID, !installationID.isEmpty {
            request.setValue(installationID, forHTTPHeaderField: "X-Installation-ID")
        }
        let body = MealScanRequest(
            imageBase64: imageJPEG.base64EncodedString(),
            mediaType: "image/jpeg",
            locale: locale,
            note: note
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public static func decodeResponse(data: Data, statusCode: Int) throws -> MealScanResponse {
        switch statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(MealScanResponse.self, from: data)
            } catch {
                throw MealScanError.invalidResponse
            }
        case 401, 403:
            throw MealScanError.unauthorized
        case 413:
            throw MealScanError.imageTooLarge
        case 429:
            throw MealScanError.rateLimited
        default:
            let envelope = try? JSONDecoder().decode(MealScanErrorEnvelope.self, from: data)
            throw MealScanError.server(message: envelope?.error.message)
        }
    }

    /// Maps transport errors to user-facing scan errors.
    public static func mapTransportError(_ error: Error) -> MealScanError {
        if let scanError = error as? MealScanError {
            return scanError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timedOut
            default:
                return .server(message: nil)
            }
        }
        return .server(message: nil)
    }
}
