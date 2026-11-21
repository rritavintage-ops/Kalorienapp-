import Foundation

/// Analyzes a meal photo and returns estimated foods, portions and nutrients.
protocol MealScanning: Sendable {
    func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse
}

/// Talks to the CalorieTracker backend (see `backend/`), which holds the AI provider's API key.
/// The app itself never contains an AI API key.
struct RemoteMealScanService: MealScanning {
    let baseURL: URL
    let clientToken: String?
    let session: URLSession

    init(baseURL: URL, clientToken: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.clientToken = clientToken
        self.session = session
    }

    /// Reads `ScanAPIBaseURL` / `ScanAPIClientToken` from Info.plist (populated from `Config/*.xcconfig`).
    static func fromBundle(_ bundle: Bundle = .main) -> RemoteMealScanService? {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "ScanAPIBaseURL") as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else {
            return nil
        }
        let token = bundle.object(forInfoDictionaryKey: "ScanAPIClientToken") as? String
        return RemoteMealScanService(baseURL: url, clientToken: token)
    }

    func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse {
        let request = try MealScanAPI.makeRequest(
            baseURL: baseURL,
            imageJPEG: imageJPEG,
            locale: locale,
            clientToken: clientToken,
            installationID: InstallationID.current
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MealScanError.invalidResponse
            }
            return try MealScanAPI.decodeResponse(data: data, statusCode: http.statusCode)
        } catch {
            throw MealScanAPI.mapTransportError(error)
        }
    }
}

/// Used when no backend URL is configured.
struct UnavailableMealScanner: MealScanning {
    func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse {
        throw MealScanError.notConfigured
    }
}

/// Deterministic scanner for UI tests and previews.
struct MockMealScanner: MealScanning {
    var delay: Duration = .milliseconds(600)

    static let sampleResponse = MealScanResponse(
        containsFood: true,
        mealName: "Chicken, rice and broccoli",
        items: [
            ScannedFoodItem(name: "Grilled chicken breast", portion: "1 fillet", grams: 150, calories: 248, protein: 46.5, carbs: 0, fat: 5.4, confidence: .high),
            ScannedFoodItem(name: "White rice", portion: "1 cup", grams: 180, calories: 234, protein: 4.3, carbs: 51, fat: 0.5, confidence: .medium),
            ScannedFoodItem(name: "Steamed broccoli", portion: "1 handful", grams: 90, calories: 31, protein: 2.5, carbs: 6, fat: 0.3, confidence: .medium),
        ],
        notes: "Portions estimated from a standard dinner plate."
    )

    func analyze(imageJPEG: Data, locale: String?) async throws -> MealScanResponse {
        try await Task.sleep(for: delay)
        return Self.sampleResponse
    }
}
