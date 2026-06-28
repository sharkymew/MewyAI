import Foundation

enum AIConfigurationSelection {
    struct UpdateResult: Equatable {
        let configurationID: UUID
        let shouldClearImages: Bool
    }

    struct PromptSelectionResult: Equatable {
        let configuration: AIConfiguration
        let configurationID: UUID
    }

    static func selectModel(
        _ model: String,
        currentConfigurationID: UUID,
        configurations: inout [AIConfiguration],
        now: Date = Date()
    ) -> UpdateResult? {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfigurationID }) else {
            return nil
        }

        configurations[index].selectedModel = model
        if !configurations[index].models.contains(where: { $0.name == model }) {
            configurations[index].models.append(AIModelConfiguration(name: model))
        }
        configurations[index].updatedAt = now

        return UpdateResult(
            configurationID: configurations[index].id,
            shouldClearImages: !configurations[index].selectedModelSupportsImages
        )
    }

    static func selectReasoningEffort(
        _ effort: ReasoningEffort,
        currentConfigurationID: UUID,
        configurations: inout [AIConfiguration],
        now: Date = Date()
    ) -> UpdateResult? {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfigurationID }) else {
            return nil
        }

        configurations[index].reasoningEnabled = true
        configurations[index].reasoningEffort = effort
        configurations[index].updatedAt = now

        return UpdateResult(
            configurationID: configurations[index].id,
            shouldClearImages: false
        )
    }

    static func setReasoningEnabled(
        _ isEnabled: Bool,
        currentConfigurationID: UUID,
        configurations: inout [AIConfiguration],
        now: Date = Date()
    ) -> UpdateResult? {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfigurationID }) else {
            return nil
        }

        configurations[index].reasoningEnabled = isEnabled
        configurations[index].updatedAt = now

        return UpdateResult(
            configurationID: configurations[index].id,
            shouldClearImages: false
        )
    }

    static func selectBuiltInDefaultPrompt(
        currentConfigurationID: UUID,
        configurations: inout [AIConfiguration],
        promptPresets: inout [AIPromptPreset],
        now: Date = Date()
    ) -> PromptSelectionResult {
        if configurations.isEmpty {
            let configuration = AIConfiguration(updatedAt: now)
            configurations = [configuration]
        }

        let index = configurations.firstIndex { $0.id == currentConfigurationID }
            ?? configurations.startIndex
        let defaultPromptPreset = AIConfigurationStore.builtInDefaultPromptPreset(in: &promptPresets)
        configurations[index].selectPromptPreset(defaultPromptPreset.id, from: promptPresets)
        configurations[index].updatedAt = now

        return PromptSelectionResult(
            configuration: configurations[index],
            configurationID: configurations[index].id
        )
    }
}
