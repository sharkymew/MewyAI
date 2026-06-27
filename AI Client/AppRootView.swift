import SwiftUI

struct AppRootView: View {
    @State private var onboardingSnapshot = AppOnboardingStore.snapshot()

    var body: some View {
        Group {
            if !onboardingSnapshot.hasAcceptedTerms {
                OnboardingConsentView {
                    AppOnboardingStore.acceptTerms()
                    reloadOnboardingSnapshot()
                }
            } else if onboardingSnapshot.needsInitialSetup {
                DeepSeekSetupWizardView {
                    AppOnboardingStore.completeInitialSetup()
                    reloadOnboardingSnapshot()
                }
            } else {
                ContentView()
            }
        }
    }

    private func reloadOnboardingSnapshot() {
        onboardingSnapshot = AppOnboardingStore.snapshot()
    }
}
