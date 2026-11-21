import SwiftUI

struct RootView: View {
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        ZStack {
            if profileStore.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: profileStore.hasCompletedOnboarding)
        .tint(Theme.accent)
    }
}

struct MainTabView: View {
    enum AppTab: Hashable {
        case home
        case history
        case profile
    }

    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
                .tag(AppTab.history)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
        }
    }
}
