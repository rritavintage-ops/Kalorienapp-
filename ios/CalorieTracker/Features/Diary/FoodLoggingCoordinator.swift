import Observation
import PhotosUI
import SwiftUI
import UIKit

struct ScanImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Drives every "add / edit food" presentation for one diary day (Home uses today, History a past day).
@Observable
final class FoodLoggingCoordinator {
    enum Sheet: Identifiable {
        case scan(ScanImage, MealType)
        case search(MealType)
        case manual(MealType)
        case edit(FoodEntry)

        var id: String {
            switch self {
            case .scan(let image, _): return "scan-\(image.id)"
            case .search: return "search"
            case .manual: return "manual"
            case .edit(let entry): return "edit-\(entry.id)"
            }
        }
    }

    var day: Date
    var sheet: Sheet?
    var isCameraPresented = false
    var isPhotoPickerPresented = false
    var photoSelection: PhotosPickerItem?
    var alertMessage: String?
    /// Incremented after each successful save; drives haptic feedback.
    var savedCount = 0

    private var pendingMeal: MealType = .breakfast
    private var capturedImage: UIImage?

    init(day: Date) {
        self.day = day
    }

    /// Meal suggested for new entries: by time of day for today, lunch-time default for other days.
    var suggestedMeal: MealType {
        MealType.suggested(for: LogDate.entryDate(forDay: day))
    }

    // MARK: Starting flows

    func startCamera(meal: MealType? = nil, launchOptions: LaunchOptions) {
        pendingMeal = meal ?? suggestedMeal
        if launchOptions.isUITesting {
            // The simulator has no camera; use a generated plate photo.
            sheet = .scan(ScanImage(image: ImageProcessor.samplePlateImage()), pendingMeal)
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            isCameraPresented = true
        } else {
            isPhotoPickerPresented = true
        }
    }

    func startPhotoLibrary(meal: MealType? = nil) {
        pendingMeal = meal ?? suggestedMeal
        isPhotoPickerPresented = true
    }

    func startSearch(meal: MealType? = nil) {
        sheet = .search(meal ?? suggestedMeal)
    }

    func startManualEntry(meal: MealType? = nil) {
        sheet = .manual(meal ?? suggestedMeal)
    }

    func edit(_ entry: FoodEntry) {
        sheet = .edit(entry)
    }

    // MARK: Callbacks

    func cameraCaptured(_ image: UIImage?) {
        capturedImage = image
        isCameraPresented = false
    }

    /// Called after the camera cover is gone, so the scan sheet can be presented safely.
    func cameraDismissed() {
        guard let image = capturedImage else { return }
        capturedImage = nil
        sheet = .scan(ScanImage(image: image), pendingMeal)
    }

    func photoSelected(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let meal = pendingMeal
        Task { @MainActor in
            defer { self.photoSelection = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    self.alertMessage = String(localized: "This photo couldn't be loaded. Please choose another one.")
                    return
                }
                self.sheet = .scan(ScanImage(image: image), meal)
            } catch {
                self.alertMessage = String(localized: "This photo couldn't be loaded. Please choose another one.")
            }
        }
    }

    func didSave() {
        savedCount += 1
    }
}

/// Attaches the camera, photo picker and food sheets for a coordinator.
struct FoodLoggingPresenter: ViewModifier {
    @Bindable var coordinator: FoodLoggingCoordinator

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coordinator.isCameraPresented, onDismiss: coordinator.cameraDismissed) {
                CameraPicker { image in
                    coordinator.cameraCaptured(image)
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $coordinator.isPhotoPickerPresented, selection: $coordinator.photoSelection, matching: .images)
            .onChange(of: coordinator.photoSelection) { _, item in
                coordinator.photoSelected(item)
            }
            .sheet(item: $coordinator.sheet) { sheet in
                switch sheet {
                case .scan(let scanImage, let meal):
                    ScanFlowView(image: scanImage.image, initialMeal: meal, day: coordinator.day, onSaved: coordinator.didSave)
                case .search(let meal):
                    FoodSearchView(initialMeal: meal, day: coordinator.day, onSaved: coordinator.didSave)
                case .manual(let meal):
                    NavigationStack {
                        ManualEntryView(initialMeal: meal, day: coordinator.day, onSaved: coordinator.didSave)
                    }
                case .edit(let entry):
                    EntryEditorView(entry: entry)
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { coordinator.alertMessage != nil },
                    set: { if !$0 { coordinator.alertMessage = nil } }
                ),
                presenting: coordinator.alertMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sensoryFeedback(.success, trigger: coordinator.savedCount)
    }
}

extension View {
    func foodLogging(_ coordinator: FoodLoggingCoordinator) -> some View {
        modifier(FoodLoggingPresenter(coordinator: coordinator))
    }
}
