import Combine
import SwiftUI

struct HomeView: View {
    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var coordinator = FoodLoggingCoordinator(day: Calendar.current.startOfDay(for: Date()))
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.launchOptions) private var launchOptions

    var body: some View {
        NavigationStack {
            DayLogView(day: today, coordinator: coordinator)
                .id(today)
                .navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CaptureBar(coordinator: coordinator, launchOptions: launchOptions)
                }
        }
        .foodLogging(coordinator)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshDay()
        }
    }

    /// Keeps Home on the current day when the app stays open past midnight.
    private func refreshDay() {
        let now = Calendar.current.startOfDay(for: Date())
        if now != today {
            today = now
            coordinator.day = now
        }
    }
}

/// Large central camera button with photo-library and search shortcuts.
struct CaptureBar: View {
    let coordinator: FoodLoggingCoordinator
    let launchOptions: LaunchOptions

    @State private var cameraTaps = 0

    var body: some View {
        HStack(spacing: 34) {
            SecondaryCaptureButton(symbol: "photo.on.rectangle", label: "Choose photo", identifier: "home.photoButton") {
                coordinator.startPhotoLibrary()
            }

            Button {
                cameraTaps += 1
                coordinator.startCamera(launchOptions: launchOptions)
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(Theme.accentGradient))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 18, y: 8)
            }
            .buttonStyle(PressableButtonStyle())
            .sensoryFeedback(.impact(weight: .medium), trigger: cameraTaps)
            .accessibilityLabel("Scan food with camera")
            .accessibilityIdentifier("home.cameraButton")

            SecondaryCaptureButton(symbol: "magnifyingglass", label: "Search food", identifier: "home.searchButton") {
                coordinator.startSearch()
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background.opacity(0.92), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}

private struct SecondaryCaptureButton: View {
    var symbol: String
    var label: LocalizedStringKey
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.card))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
