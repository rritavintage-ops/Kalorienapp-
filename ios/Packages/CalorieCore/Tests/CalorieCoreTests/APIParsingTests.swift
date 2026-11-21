import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CalorieCore

final class OpenFoodFactsTests: XCTestCase {
    func testSearchURLContainsQueryAndFields() throws {
        let url = try XCTUnwrap(OpenFoodFactsAPI.searchURL(query: " greek yogurt ", page: 1, pageSize: 25))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "world.openfoodfacts.org")
        XCTAssertEqual(components.path, "/cgi/search.pl")
        XCTAssertEqual(items["search_terms"], "greek yogurt")
        XCTAssertEqual(items["json"], "1")
        XCTAssertEqual(items["page_size"], "25")
        XCTAssertTrue(items["fields"]?.contains("nutriments") ?? false)
        XCTAssertNil(OpenFoodFactsAPI.searchURL(query: "   "))
    }

    func testParsesValidResponseAndUsesFatField() throws {
        let json = """
        {
          "count": 3,
          "products": [
            {
              "code": "123",
              "product_name": "Oat Flakes",
              "brands": "Good Oats, Other Brand",
              "image_front_thumb_url": "https://images.example.org/oats.jpg",
              "nutriments": {
                "energy-kcal_100g": 372,
                "carbohydrates_100g": 58.7,
                "proteins_100g": 13.5,
                "fat_100g": 7
              }
            },
            {
              "product_name": "Name only, no nutriments"
            },
            {
              "code": "456",
              "product_name": "Greek Yogurt",
              "nutriments": {
                "energy_100g": "406",
                "carbohydrates_100g": "3,6",
                "proteins_100g": 9,
                "fat_100g": 5
              }
            }
          ]
        }
        """
        let foods = try OpenFoodFactsAPI.parseSearchResponse(Data(json.utf8))
        XCTAssertEqual(foods.count, 2)

        let oats = foods[0]
        XCTAssertEqual(oats.id, "123")
        XCTAssertEqual(oats.name, "Oat Flakes")
        XCTAssertEqual(oats.brand, "Good Oats")
        XCTAssertEqual(oats.imageURL?.absoluteString, "https://images.example.org/oats.jpg")
        XCTAssertEqual(oats.per100g.fat, 7, "fat must come from fat_100g (Android used proteins_100g)")
        XCTAssertEqual(oats.per100g.protein, 13.5)

        let yogurt = foods[1]
        XCTAssertEqual(yogurt.per100g.calories, 406 / 4.184, accuracy: 0.01, "kJ-only products are converted")
        XCTAssertEqual(yogurt.per100g.carbs, 3.6, accuracy: 0.0001, "numeric strings with commas are accepted")
    }

    func testMissingProductsKeyYieldsEmptyList() throws {
        XCTAssertEqual(try OpenFoodFactsAPI.parseSearchResponse(Data("{}".utf8)), [])
    }

    func testPlausibilityFilter() {
        XCTAssertTrue(OpenFoodFactsAPI.isPlausible(NutritionFacts(calories: 89, protein: 1.1, carbs: 22.8, fat: 0.3)))
        // Energy far below what the macros imply.
        XCTAssertFalse(OpenFoodFactsAPI.isPlausible(NutritionFacts(calories: 10, protein: 20, carbs: 50, fat: 20)))
        // More than 100 g of macros in 100 g.
        XCTAssertFalse(OpenFoodFactsAPI.isPlausible(NutritionFacts(calories: 900, protein: 50, carbs: 50, fat: 50)))
        XCTAssertFalse(OpenFoodFactsAPI.isPlausible(NutritionFacts(calories: -1, protein: 0, carbs: 0, fat: 0)))
        // Water / zero-calorie drinks are fine.
        XCTAssertTrue(OpenFoodFactsAPI.isPlausible(.zero))
    }

    func testDuplicateProductsAreRemoved() throws {
        let json = """
        {"products": [
          {"product_name": "Banana", "nutriments": {"energy-kcal_100g": 89, "carbohydrates_100g": 22.8, "proteins_100g": 1.1, "fat_100g": 0.3}},
          {"product_name": "banana", "nutriments": {"energy-kcal_100g": 89, "carbohydrates_100g": 22.8, "proteins_100g": 1.1, "fat_100g": 0.3}}
        ]}
        """
        XCTAssertEqual(try OpenFoodFactsAPI.parseSearchResponse(Data(json.utf8)).count, 1)
    }
}

final class MealScanAPITests: XCTestCase {
    private let baseURL = URL(string: "https://scan.example.com")!

    func testRequestCarriesImageAndHeaders() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
        let request = try MealScanAPI.makeRequest(
            baseURL: baseURL,
            imageJPEG: image,
            locale: "de_DE",
            clientToken: "secret-token",
            installationID: "install-1"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://scan.example.com/v1/meal-scans")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Installation-ID"), "install-1")

        let body = try JSONDecoder().decode(MealScanRequest.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.mediaType, "image/jpeg")
        XCTAssertEqual(body.locale, "de_DE")
        XCTAssertEqual(Data(base64Encoded: body.imageBase64), image)
    }

    func testRequestWithoutTokenHasNoAuthorizationHeader() throws {
        let request = try MealScanAPI.makeRequest(baseURL: baseURL, imageJPEG: Data([1, 2, 3]), locale: nil, clientToken: "  ", installationID: nil)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Installation-ID"))
    }

    func testOversizedImageIsRejectedBeforeUpload() {
        let big = Data(count: MealScanAPI.maximumImageBytes + 1)
        XCTAssertThrowsError(try MealScanAPI.makeRequest(baseURL: baseURL, imageJPEG: big, locale: nil, clientToken: nil, installationID: nil)) { error in
            XCTAssertEqual(error as? MealScanError, .imageTooLarge)
        }
    }

    func testDecodesSuccessfulScanIntoDrafts() throws {
        let json = """
        {
          "containsFood": true,
          "mealName": "Chicken, rice and broccoli",
          "items": [
            {"name": "Grilled chicken breast", "portion": "1 fillet", "grams": 150, "calories": 248, "protein": 46.5, "carbs": 0, "fat": 5.4, "confidence": "high"},
            {"name": "White rice", "portion": " ", "grams": 180, "calories": 234, "protein": 4.3, "carbs": 51, "fat": 0.5, "confidence": "MEDIUM"},
            {"name": "  ", "grams": 10, "calories": 10, "protein": 0, "carbs": 0, "fat": 0, "confidence": "low"},
            {"name": "Sauce", "grams": 30, "calories": -5, "protein": 0, "carbs": 2, "fat": 1, "confidence": "unsure"}
          ],
          "notes": "Portions estimated from a standard dinner plate."
        }
        """
        let response = try MealScanAPI.decodeResponse(data: Data(json.utf8), statusCode: 200)
        XCTAssertTrue(response.containsFood)
        XCTAssertEqual(response.mealName, "Chicken, rice and broccoli")

        let drafts = response.drafts()
        XCTAssertEqual(drafts.map(\.name), ["Grilled chicken breast", "White rice", "Sauce"])
        XCTAssertEqual(drafts[0].grams, 150)
        XCTAssertEqual(drafts[0].totals.calories, 248, accuracy: 0.0001)
        XCTAssertEqual(drafts[0].portionDescription, "1 fillet")
        XCTAssertEqual(drafts[0].confidence, .high)
        XCTAssertNil(drafts[1].portionDescription, "blank portions are dropped")
        XCTAssertEqual(drafts[1].confidence, .medium, "confidence is case-insensitive")
        XCTAssertEqual(drafts[2].totals.calories, 0, "negative estimates are clamped")
        XCTAssertEqual(drafts[2].confidence, .medium, "unknown confidence falls back to medium")
    }

    func testDecodesNotFoodResponse() throws {
        let json = #"{"containsFood": false, "mealName": null, "items": [], "notes": "This looks like a cat."}"#
        let response = try MealScanAPI.decodeResponse(data: Data(json.utf8), statusCode: 200)
        XCTAssertFalse(response.containsFood)
        XCTAssertTrue(response.drafts().isEmpty)
    }

    func testMapsErrorStatusCodes() {
        func scanError(for status: Int, body: String = "{}") -> MealScanError? {
            do {
                _ = try MealScanAPI.decodeResponse(data: Data(body.utf8), statusCode: status)
                return nil
            } catch {
                return error as? MealScanError
            }
        }
        XCTAssertEqual(scanError(for: 401), .unauthorized)
        XCTAssertEqual(scanError(for: 413), .imageTooLarge)
        XCTAssertEqual(scanError(for: 429), .rateLimited)
        XCTAssertEqual(scanError(for: 502, body: #"{"error": {"code": "upstream", "message": "Try again soon."}}"#),
                       .server(message: "Try again soon."))
        XCTAssertEqual(scanError(for: 500, body: "not json"), .server(message: nil))
        XCTAssertEqual(scanError(for: 200, body: "not json"), .invalidResponse)
    }

    func testMapsTransportErrors() {
        XCTAssertEqual(MealScanAPI.mapTransportError(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(MealScanAPI.mapTransportError(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(MealScanAPI.mapTransportError(MealScanError.rateLimited), .rateLimited)
    }

    func testErrorsHaveUserFacingMessages() {
        let errors: [MealScanError] = [.notConfigured, .imageTooLarge, .unauthorized, .rateLimited, .offline, .timedOut, .server(message: nil), .invalidResponse]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}
