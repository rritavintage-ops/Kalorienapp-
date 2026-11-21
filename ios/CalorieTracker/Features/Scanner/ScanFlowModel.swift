import Foundation
import Observation
import UIKit

/// State of one photo scan: upload → AI estimate → user review.
@Observable
final class ScanFlowModel {
    enum Phase: Equatable {
        case analyzing
        case review
        case notFood(message: String?)
        case failed(message: String)
    }

    var phase: Phase = .analyzing
    var drafts: [FoodDraft] = []
    var mealName: String?
    var notes: String?
    var mealType: MealType

    init(mealType: MealType) {
        self.mealType = mealType
    }

    var totals: NutritionFacts {
        drafts.map(\.totals).sum()
    }

    var canSave: Bool {
        !drafts.isEmpty && drafts.allSatisfy(\.isValid)
    }

    @MainActor
    func analyze(image: UIImage, scanner: any MealScanning, locale: Locale = .current) async {
        phase = .analyzing
        do {
            let jpeg = try ImageProcessor.uploadJPEG(from: image)
            let response = try await scanner.analyze(imageJPEG: jpeg, locale: locale.identifier)
            apply(response)
        } catch is CancellationError {
            return
        } catch {
            let scanError = MealScanAPI.mapTransportError(error)
            phase = .failed(message: scanError.errorDescription ?? String(localized: "Something went wrong. Please try again."))
        }
    }

    func apply(_ response: MealScanResponse) {
        let newDrafts = response.drafts()
        guard response.containsFood, !newDrafts.isEmpty else {
            phase = .notFood(message: response.notes)
            return
        }
        drafts = newDrafts
        mealName = response.mealName
        notes = response.notes
        phase = .review
    }

    /// Lets the user continue without AI results (e.g. the scanner is unavailable).
    func startManualReview() {
        drafts = []
        mealName = nil
        notes = nil
        phase = .review
    }

    func upsert(_ draft: FoodDraft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
    }

    func remove(_ draft: FoodDraft) {
        drafts.removeAll { $0.id == draft.id }
    }
}
