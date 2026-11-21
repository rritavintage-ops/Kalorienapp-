import Foundation
import Observation

/// Persists the user's profile (Android: `DefaultPreferences` on SharedPreferences).
@Observable
final class ProfileStore {
    private(set) var profile: UserProfile?

    private let defaults: UserDefaults
    static let profileKey = "profile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.profileKey) {
            profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        }
    }

    /// Onboarding is finished once a profile has been saved.
    var hasCompletedOnboarding: Bool {
        profile != nil
    }

    /// The saved profile, or the onboarding defaults before one exists.
    var currentProfile: UserProfile {
        profile ?? .default
    }

    var goals: NutritionGoals {
        NutritionCalculator.goals(for: currentProfile)
    }

    func save(_ profile: UserProfile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    func update(_ change: (inout UserProfile) -> Void) {
        var updated = currentProfile
        change(&updated)
        save(updated)
    }

    /// Removes the profile, which sends the user back to onboarding.
    func reset() {
        profile = nil
        defaults.removeObject(forKey: Self.profileKey)
    }
}

/// Random identifier for this installation, sent to the scan backend for per-device rate limiting.
/// It is not linked to any personal data.
enum InstallationID {
    private static let key = "installation.id"

    static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}
