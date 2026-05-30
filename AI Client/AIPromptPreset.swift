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
        return trimmedName.isEmpty ? "未命名提示词" : trimmedName
    }
}

extension AIConfiguration {
    mutating func selectPromptPreset(_ id: UUID) {
        guard let preset = promptPresets.first(where: { $0.id == id }) else { return }
        selectedPromptPresetID = preset.id
        systemPrompt = preset.content
    }

    mutating func updateSelectedPromptName(_ name: String) {
        guard let index = selectedPromptPresetIndex else { return }
        promptPresets[index].name = name
        promptPresets[index].updatedAt = Date()
    }

    mutating func updateSelectedPromptContent(_ content: String) {
        guard let index = selectedPromptPresetIndex else { return }
        promptPresets[index].content = content
        promptPresets[index].updatedAt = Date()
        systemPrompt = content
    }

    mutating func addPromptPreset() {
        let preset = AIPromptPreset(name: "提示词 \(promptPresets.count + 1)", content: "")
        promptPresets.append(preset)
        selectPromptPreset(preset.id)
    }

    mutating func deleteSelectedPromptPreset() {
        guard promptPresets.count > 1,
              let index = selectedPromptPresetIndex else { return }
        promptPresets.remove(at: index)
        let nextIndex = min(index, promptPresets.count - 1)
        selectPromptPreset(promptPresets[nextIndex].id)
    }

    mutating func restoreDefaultSelectedPrompt() {
        updateSelectedPromptContent(Self.defaultSystemPrompt)
    }

    mutating func selectBuiltInDefaultPrompt() {
        if let preset = promptPresets.first(where: { $0.content == Self.defaultSystemPrompt }) {
            selectPromptPreset(preset.id)
            return
        }

        let preset = AIPromptPreset(name: "默认提示词", content: Self.defaultSystemPrompt)
        promptPresets.insert(preset, at: 0)
        selectPromptPreset(preset.id)
    }

    static func normalizedPromptSelection(
        promptPresets: [AIPromptPreset]?,
        selectedPromptPresetID: UUID?,
        fallbackSystemPrompt: String
    ) -> (presets: [AIPromptPreset], selectedID: UUID, systemPrompt: String) {
        let presets: [AIPromptPreset]
        if let promptPresets, !promptPresets.isEmpty {
            presets = promptPresets
        } else {
            presets = [AIPromptPreset(name: "默认提示词", content: fallbackSystemPrompt)]
        }

        let selectedPreset = selectedPromptPresetID.flatMap { selectedID in
            presets.first { $0.id == selectedID }
        } ?? presets.first { $0.content == fallbackSystemPrompt } ?? presets[0]

        return (presets, selectedPreset.id, selectedPreset.content)
    }

    private var selectedPromptPresetIndex: Int? {
        promptPresets.firstIndex { $0.id == selectedPromptPresetID } ?? promptPresets.indices.first
    }
}
