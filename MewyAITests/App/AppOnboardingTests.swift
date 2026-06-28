import XCTest
@testable import MewyAI

@MainActor
final class AppOnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppOnboardingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNewInstallDefaultsRequireConsentAndSetup() {
        let configuration = AIConfiguration(apiKey: "")

        let snapshot = AppOnboardingStore.snapshot(
            defaults: defaults,
            configurations: [configuration]
        )

        XCTAssertFalse(snapshot.hasAcceptedTerms)
        XCTAssertFalse(snapshot.hasCompletedInitialSetup)
        XCTAssertFalse(snapshot.hasConfiguredAPIKey)
        XCTAssertTrue(snapshot.needsInitialSetup)
    }

    func testExistingAPIKeySkipsInitialSetupAfterConsent() {
        let configuration = AIConfiguration(apiKey: "sk-test")
        AppOnboardingStore.acceptTerms(defaults: defaults)

        let snapshot = AppOnboardingStore.snapshot(
            defaults: defaults,
            configurations: [configuration]
        )

        XCTAssertTrue(snapshot.hasAcceptedTerms)
        XCTAssertTrue(snapshot.hasConfiguredAPIKey)
        XCTAssertFalse(snapshot.needsInitialSetup)
    }

    func testMemoryDefaultsAreOptIn() {
        XCTAssertFalse(ChatMemoryStore.defaultMemoryEnabled)
        XCTAssertFalse(ChatMemoryStore.defaultHistoryRecallEnabled)
    }

    func testMemoryPreferencesPersistFromWizardDraft() {
        var draft = DeepSeekSetupDraft()
        draft.enablesMemory = true
        draft.enablesHistoryRecall = true

        DeepSeekSetupCoordinator.applyMemoryPreferences(
            draft: draft,
            defaults: defaults
        )

        XCTAssertTrue(defaults.bool(forKey: ChatMemoryStore.memoryEnabledKey))
        XCTAssertTrue(defaults.bool(forKey: ChatMemoryStore.historyRecallEnabledKey))
    }

    func testDeepSeekConnectionUpdatesSelectedConfiguration() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_002)
        var configurations = [
            AIConfiguration(
                id: id,
                baseURL: "https://old.example",
                endpoint: "old",
                apiKey: "",
                selectedModel: ""
            )
        ]
        var selectedConfigurationID: UUID? = id
        var draft = DeepSeekSetupDraft()
        draft.baseURLChoice = .custom
        draft.customBaseURL = " https://proxy.example/v1 "
        draft.apiKey = " sk-new "

        let didApply = DeepSeekSetupCoordinator.applyConnection(
            draft: draft,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID,
            now: now
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(selectedConfigurationID, id)
        XCTAssertEqual(configurations[0].baseURL, "https://proxy.example/v1")
        XCTAssertEqual(configurations[0].endpoint, "chat/completions")
        XCTAssertEqual(configurations[0].apiFormat, .openAIChatCompletions)
        XCTAssertEqual(configurations[0].apiKey, "sk-new")
        XCTAssertEqual(configurations[0].selectedModel, "deepseek-v4-pro")
        XCTAssertEqual(configurations[0].updatedAt, now)
    }

    func testDeepSeekConnectionRejectsMissingKeyAndCustomBaseURL() {
        var configurations = [AIConfiguration(apiKey: "")]
        var selectedConfigurationID: UUID?

        var missingKeyDraft = DeepSeekSetupDraft()
        missingKeyDraft.apiKey = " "

        XCTAssertFalse(DeepSeekSetupCoordinator.applyConnection(
            draft: missingKeyDraft,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        ))

        var missingBaseURLDraft = DeepSeekSetupDraft()
        missingBaseURLDraft.baseURLChoice = .custom
        missingBaseURLDraft.customBaseURL = " "
        missingBaseURLDraft.apiKey = "sk-test"

        XCTAssertFalse(DeepSeekSetupCoordinator.applyConnection(
            draft: missingBaseURLDraft,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        ))
    }
}
