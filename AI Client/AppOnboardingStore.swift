import Foundation

enum AppOnboardingStore {
    private static let termsAcceptedKey = "mewyAI.onboarding.termsAccepted.v1"
    private static let initialSetupCompletedKey = "mewyAI.onboarding.initialSetupCompleted.v1"

    static func snapshot(
        defaults: UserDefaults = .standard,
        configurations: [AIConfiguration] = AIConfigurationStore.loadConfigurations()
    ) -> AppOnboardingSnapshot {
        AppOnboardingSnapshot(
            hasAcceptedTerms: hasAcceptedTerms(defaults: defaults),
            hasCompletedInitialSetup: hasCompletedInitialSetup(defaults: defaults),
            hasConfiguredAPIKey: hasConfiguredAPIKey(in: configurations)
        )
    }

    static func hasAcceptedTerms(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: termsAcceptedKey)
    }

    static func hasCompletedInitialSetup(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: initialSetupCompletedKey)
    }

    static func acceptTerms(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: termsAcceptedKey)
    }

    static func completeInitialSetup(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: initialSetupCompletedKey)
    }

    static func hasConfiguredAPIKey(in configurations: [AIConfiguration]) -> Bool {
        configurations.contains { configuration in
            !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct AppOnboardingSnapshot: Equatable {
    var hasAcceptedTerms: Bool
    var hasCompletedInitialSetup: Bool
    var hasConfiguredAPIKey: Bool

    var needsInitialSetup: Bool {
        !hasCompletedInitialSetup && !hasConfiguredAPIKey
    }
}
