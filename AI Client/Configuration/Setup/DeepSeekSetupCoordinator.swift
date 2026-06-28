import Foundation

struct DeepSeekSetupDraft: Equatable {
    enum BaseURLChoice: String, CaseIterable, Identifiable {
        case official
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .official:
                return "DeepSeek 官方地址"
            case .custom:
                return "自定义 Base URL"
            }
        }
    }

    var baseURLChoice: BaseURLChoice = .official
    var customBaseURL = ""
    var apiKey = ""
    var enablesMemory = false
    var enablesHistoryRecall = false

    var resolvedBaseURL: String {
        switch baseURLChoice {
        case .official:
            return DeepSeekSetupCoordinator.officialBaseURL
        case .custom:
            return customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSaveConnection: Bool {
        !resolvedBaseURL.isEmpty && !trimmedAPIKey.isEmpty
    }
}

enum DeepSeekSetupCoordinator {
    static let officialBaseURL = "https://api.deepseek.com"
    static let endpoint = "chat/completions"
    static let defaultModelName = "deepseek-v4-pro"

    @discardableResult
    static func applyConnection(
        draft: DeepSeekSetupDraft,
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?,
        now: Date = Date()
    ) -> Bool {
        guard draft.canSaveConnection else { return false }

        if configurations.isEmpty {
            configurations = [AIConfiguration()]
        }

        let selectedIndex = selectedConfigurationIndex(
            in: configurations,
            selectedConfigurationID: selectedConfigurationID
        )
        var configuration = configurations[selectedIndex]
        configuration.baseURL = draft.resolvedBaseURL
        configuration.endpoint = endpoint
        configuration.apiFormat = .openAIChatCompletions
        configuration.apiKey = draft.trimmedAPIKey
        configuration.updatedAt = now

        if configuration.models.isEmpty {
            configuration.models = [AIModelConfiguration(name: defaultModelName, supportsTools: true)]
        }
        if configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.selectedModel = configuration.models.first?.name ?? defaultModelName
        }

        configurations[selectedIndex] = configuration
        selectedConfigurationID = configuration.id
        return true
    }

    static func applyMemoryPreferences(
        draft: DeepSeekSetupDraft,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(draft.enablesMemory, forKey: ChatMemoryStore.memoryEnabledKey)
        defaults.set(draft.enablesHistoryRecall, forKey: ChatMemoryStore.historyRecallEnabledKey)
    }

    private static func selectedConfigurationIndex(
        in configurations: [AIConfiguration],
        selectedConfigurationID: UUID?
    ) -> Int {
        if let selectedConfigurationID,
           let index = configurations.firstIndex(where: { $0.id == selectedConfigurationID }) {
            return index
        }
        return 0
    }
}
