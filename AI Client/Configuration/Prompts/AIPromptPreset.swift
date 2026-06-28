import Foundation

struct AIPromptPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var content: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? AppLocalizations.string("promptPreset.unnamed", defaultValue: "Unnamed Prompt")
            : trimmedName
    }
}

extension AIConfiguration {
    mutating func selectPromptPreset(_ id: UUID, from promptPresets: [AIPromptPreset]) {
        guard let preset = promptPresets.first(where: { $0.id == id }) else { return }
        selectedPromptPresetID = preset.id
        systemPrompt = preset.content
    }

    mutating func normalizePromptSelection(from promptPresets: [AIPromptPreset]) {
        guard let preset = Self.selectedPromptPreset(for: self, in: promptPresets) else { return }
        selectedPromptPresetID = preset.id
        systemPrompt = preset.content
    }

    static func selectedPromptPreset(
        for configuration: AIConfiguration,
        in promptPresets: [AIPromptPreset]
    ) -> AIPromptPreset? {
        selectedPromptPreset(
            selectedPromptPresetID: configuration.selectedPromptPresetID,
            systemPrompt: configuration.systemPrompt,
            in: promptPresets
        )
    }

    static func selectedPromptPreset(
        selectedPromptPresetID: UUID?,
        systemPrompt: String,
        in promptPresets: [AIPromptPreset]
    ) -> AIPromptPreset? {
        selectedPromptPresetID.flatMap { selectedID in
            promptPresets.first { $0.id == selectedID }
        } ?? promptPresets.first { $0.content == systemPrompt }
            ?? promptPresets.first { $0.content == Self.defaultSystemPrompt }
            ?? promptPresets.first
    }

    static func normalizedPromptSelection(
        promptPresets: [AIPromptPreset]?,
        selectedPromptPresetID: UUID?,
        fallbackSystemPrompt: String
    ) -> (presets: [AIPromptPreset], selectedID: UUID, systemPrompt: String) {
        var presets: [AIPromptPreset]
        if let promptPresets, !promptPresets.isEmpty {
            presets = promptPresets
        } else {
            presets = [AIPromptPreset(
                name: AppLocalizations.string("promptPreset.defaultName", defaultValue: "Default Prompt"),
                content: fallbackSystemPrompt
            )]
        }

        if let selectedPreset = selectedPromptPresetID.flatMap({ selectedID in
            presets.first { $0.id == selectedID }
        }) ?? presets.first(where: { $0.content == fallbackSystemPrompt }) {
            return (presets, selectedPreset.id, selectedPreset.content)
        }

        let recoveredPreset = AIPromptPreset(
            id: selectedPromptPresetID ?? UUID(),
            name: AppLocalizations.string("promptPreset.currentName", defaultValue: "Current Prompt"),
            content: fallbackSystemPrompt
        )
        presets.append(recoveredPreset)
        return (presets, recoveredPreset.id, recoveredPreset.content)
    }
}
