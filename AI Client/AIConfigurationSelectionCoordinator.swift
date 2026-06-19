import Foundation

enum AIConfigurationSelectionCoordinator {
    static func selectModel(
        _ model: String,
        currentConfiguration: AIConfiguration,
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?,
        attachmentDraft: inout ChatAttachmentDraft
    ) {
        guard let result = AIConfigurationSelection.selectModel(
            model,
            currentConfigurationID: currentConfiguration.id,
            configurations: &configurations
        ) else { return }

        if result.shouldClearImages {
            attachmentDraft.clearImages()
        }
        persistConfigurationSelection(
            result.configurationID,
            configurations: configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    static func selectReasoningEffort(
        _ effort: ReasoningEffort,
        currentConfiguration: AIConfiguration,
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?
    ) {
        guard let result = AIConfigurationSelection.selectReasoningEffort(
            effort,
            currentConfigurationID: currentConfiguration.id,
            configurations: &configurations
        ) else { return }

        persistConfigurationSelection(
            result.configurationID,
            configurations: configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    static func setReasoningEnabled(
        _ isEnabled: Bool,
        currentConfiguration: AIConfiguration,
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?
    ) {
        guard let result = AIConfigurationSelection.setReasoningEnabled(
            isEnabled,
            currentConfigurationID: currentConfiguration.id,
            configurations: &configurations
        ) else { return }

        persistConfigurationSelection(
            result.configurationID,
            configurations: configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    @discardableResult
    static func selectBuiltInDefaultPrompt(
        currentConfiguration: AIConfiguration,
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?
    ) -> AIConfiguration {
        var promptPresets = AIConfigurationStore.loadPromptPresets(configurations: configurations)
        let result = AIConfigurationSelection.selectBuiltInDefaultPrompt(
            currentConfigurationID: currentConfiguration.id,
            configurations: &configurations,
            promptPresets: &promptPresets
        )
        selectedConfigurationID = result.configurationID
        AIConfigurationStore.saveSelectedConfigurationID(result.configurationID)
        AIConfigurationStore.savePromptPresets(promptPresets)
        AIConfigurationStore.saveConfigurations(configurations)
        return result.configuration
    }

    static func reload(
        configurations: inout [AIConfiguration],
        selectedConfigurationID: inout UUID?
    ) {
        configurations = AIConfigurationStore.loadConfigurations()
        selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
        if selectedConfigurationID == nil,
           let firstConfiguration = configurations.first {
            selectedConfigurationID = firstConfiguration.id
            AIConfigurationStore.saveSelectedConfigurationID(firstConfiguration.id)
        }
    }

    private static func persistConfigurationSelection(
        _ id: UUID,
        configurations: [AIConfiguration],
        selectedConfigurationID: inout UUID?
    ) {
        selectedConfigurationID = id
        AIConfigurationStore.saveSelectedConfigurationID(id)
        AIConfigurationStore.saveConfigurations(configurations)
    }
}
