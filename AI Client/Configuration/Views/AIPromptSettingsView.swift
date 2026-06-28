import SwiftUI

struct AIPromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configurations: [AIConfiguration]
    @State private var promptPresets: [AIPromptPreset]
    @State private var selectedConfigurationID: UUID?
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: PromptField?

    private let configurationID: UUID?

    init(configurationID: UUID? = nil) {
        let configurations = AIConfigurationStore.loadConfigurations()
        self.configurationID = configurationID
        _configurations = State(initialValue: configurations)
        _promptPresets = State(initialValue: AIConfigurationStore.loadPromptPresets(configurations: configurations))
        _selectedConfigurationID = State(initialValue: configurationID ?? AIConfigurationStore.loadSelectedConfigurationID())
    }

    private enum PromptField: Hashable {
        case name
        case content
    }

    private var selectedIndex: Int? {
        guard let selectedConfigurationID else { return configurations.indices.first }
        return configurations.firstIndex { $0.id == selectedConfigurationID } ?? configurations.indices.first
    }

    private var selectedConfiguration: AIConfiguration? {
        guard let selectedIndex else { return nil }
        return configurations[selectedIndex]
    }

    private var selectedPromptPresetIndex: Int? {
        guard let selectedConfiguration else { return promptPresets.indices.first }
        let selectedPromptPreset = AIConfiguration.selectedPromptPreset(
            for: selectedConfiguration,
            in: promptPresets
        )
        return selectedPromptPreset.flatMap { selectedPreset in
            promptPresets.firstIndex { $0.id == selectedPreset.id }
        } ?? promptPresets.indices.first
    }

    private var selectedPromptPreset: AIPromptPreset? {
        guard let selectedPromptPresetIndex else { return nil }
        return promptPresets[selectedPromptPresetIndex]
    }

    var body: some View {
        NavigationStack {
            Form {
                promptSection
            }
            .background(
                KeyboardDismissTapLayer {
                    hideKeyboard()
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("提示词设置")
            .onAppear {
                ensureSelection()
            }
            .onDisappear {
                saveCurrentState()
            }
            .onChange(of: focusedField) { oldField, newField in
                if oldField != newField {
                    commitEditedField(oldField)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        hideKeyboard()
                        saveCurrentState()
                        dismiss()
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        Section {
            Picker("当前提示词", selection: selectedPromptPresetIDBinding) {
                ForEach(promptPresets) { promptPreset in
                    Text(promptPreset.displayName).tag(promptPreset.id)
                }
            }

            TextField("提示词名称", text: selectedPromptPresetNameBinding)
                .focused($focusedField, equals: .name)

            TextEditor(text: selectedPromptPresetContentBinding)
                .focused($focusedField, equals: .content)
                .frame(minHeight: 180)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()

            Button("新增提示词") {
                hideKeyboard()
                addPromptPreset()
            }

            Button("恢复默认内容") {
                hideKeyboard()
                updateSelectedPromptPreset(updatesContent: true) { promptPreset in
                    promptPreset.content = AIConfiguration.defaultSystemPrompt
                }
            }
            .disabled(selectedPromptPreset?.content == AIConfiguration.defaultSystemPrompt)

            Button(role: .destructive) {
                hideKeyboard()
                deleteSelectedPromptPreset()
            } label: {
                Label("删除当前提示词", systemImage: "trash")
            }
            .disabled(promptPresets.count <= 1)

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("提示词")
        } footer: {
            Text("提示词预设会在所有配置中共享。当前选中的内容会作为每次对话的 system message 发送。留空则不发送提示词。")
        }
    }

    private var selectedPromptPresetIDBinding: Binding<UUID> {
        Binding(
            get: {
                selectedPromptPreset?.id ?? promptPresets.first?.id ?? UUID()
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration.selectPromptPreset(newValue, from: promptPresets)
                }
            }
        )
    }

    private var selectedPromptPresetNameBinding: Binding<String> {
        Binding(
            get: { selectedPromptPreset?.name ?? "" },
            set: { newValue in
                updateSelectedPromptPreset(persists: false) { promptPreset in
                    promptPreset.name = newValue
                }
            }
        )
    }

    private var selectedPromptPresetContentBinding: Binding<String> {
        Binding(
            get: { selectedPromptPreset?.content ?? "" },
            set: { newValue in
                updateSelectedPromptPreset(persists: false, updatesContent: true) { promptPreset in
                    promptPreset.content = newValue
                }
            }
        )
    }

    private func ensureSelection() {
        if configurations.isEmpty {
            configurations = [AIConfiguration()]
        }
        var normalizedPromptPresets = promptPresets
        _ = AIConfigurationStore.builtInDefaultPromptPreset(in: &normalizedPromptPresets)
        promptPresets = normalizedPromptPresets

        if let configurationID,
           configurations.contains(where: { $0.id == configurationID }) {
            selectedConfigurationID = configurationID
            normalizeConfigurationPromptSelections()
            return
        }

        if let selectedConfigurationID,
           configurations.contains(where: { $0.id == selectedConfigurationID }) {
            normalizeConfigurationPromptSelections()
            return
        }

        if let storedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID(),
           configurations.contains(where: { $0.id == storedConfigurationID }) {
            selectedConfigurationID = storedConfigurationID
        } else {
            selectedConfigurationID = configurations[0].id
        }
        normalizeConfigurationPromptSelections()
    }

    private func updateSelectedConfiguration(
        persists: Bool = true,
        _ update: (inout AIConfiguration) -> Void
    ) {
        ensureSelection()
        guard let selectedIndex else { return }
        update(&configurations[selectedIndex])
        configurations[selectedIndex].updatedAt = Date()
        if persists {
            saveCurrentState()
        }
    }

    private func updateSelectedPromptPreset(
        persists: Bool = true,
        updatesContent: Bool = false,
        _ update: (inout AIPromptPreset) -> Void
    ) {
        ensureSelection()
        guard let selectedPromptPresetIndex else { return }
        let promptPresetID = promptPresets[selectedPromptPresetIndex].id
        update(&promptPresets[selectedPromptPresetIndex])
        promptPresets[selectedPromptPresetIndex].updatedAt = Date()
        if updatesContent {
            applyPromptPresetContentToSelectedConfigurations(promptPresetID)
        }
        if persists {
            saveCurrentState()
        }
    }

    private func addPromptPreset() {
        ensureSelection()
        let promptPreset = AIPromptPreset(
            name: AppLocalizations.format(
                "promptPreset.numberedName",
                defaultValue: "Prompt %d",
                arguments: [promptPresets.count + 1]
            ),
            content: ""
        )
        promptPresets.append(promptPreset)
        updateSelectedConfiguration(persists: false) { configuration in
            configuration.selectPromptPreset(promptPreset.id, from: promptPresets)
        }
        saveCurrentState()
    }

    private func deleteSelectedPromptPreset() {
        ensureSelection()
        guard promptPresets.count > 1,
              let selectedPromptPresetIndex else { return }

        let removedPromptPresetID = promptPresets[selectedPromptPresetIndex].id
        promptPresets.remove(at: selectedPromptPresetIndex)
        let nextIndex = min(selectedPromptPresetIndex, promptPresets.count - 1)
        let nextPromptPreset = promptPresets[nextIndex]

        for index in configurations.indices where configurations[index].selectedPromptPresetID == removedPromptPresetID {
            configurations[index].selectPromptPreset(nextPromptPreset.id, from: promptPresets)
            configurations[index].updatedAt = Date()
        }

        saveCurrentState()
    }

    private func saveCurrentState() {
        ensureSelection()
        syncPromptPresetsToConfigurations()
        let didSaveConfigurations = AIConfigurationStore.saveConfigurations(configurations)
        let didSavePromptPresets = AIConfigurationStore.savePromptPresets(promptPresets)
        let didSave = didSaveConfigurations && didSavePromptPresets
        saveErrorMessage = didSave
            ? nil
            : AppLocalizations.string(
                "promptPreset.saveFailed",
                defaultValue: "Failed to save prompt. Check Keychain or local storage permissions."
            )
        if let selectedConfigurationID {
            AIConfigurationStore.saveSelectedConfigurationID(selectedConfigurationID)
        }
    }

    @discardableResult
    private func normalizeConfigurationPromptSelections() -> Bool {
        var didChange = false

        for index in configurations.indices {
            let previousPromptPresetID = configurations[index].selectedPromptPresetID
            let previousSystemPrompt = configurations[index].systemPrompt
            configurations[index].normalizePromptSelection(from: promptPresets)

            if configurations[index].selectedPromptPresetID != previousPromptPresetID
                || configurations[index].systemPrompt != previousSystemPrompt {
                configurations[index].updatedAt = Date()
                didChange = true
            }
        }

        return didChange
    }

    private func syncPromptPresetsToConfigurations() {
        for index in configurations.indices {
            configurations[index].promptPresets = promptPresets
        }
    }

    private func applyPromptPresetContentToSelectedConfigurations(_ promptPresetID: UUID) {
        guard let promptPreset = promptPresets.first(where: { $0.id == promptPresetID }) else { return }

        for index in configurations.indices where configurations[index].selectedPromptPresetID == promptPresetID {
            configurations[index].systemPrompt = promptPreset.content
            configurations[index].updatedAt = Date()
        }
    }

    private func hideKeyboard() {
        let fieldToCommit = focusedField
        focusedField = nil
        commitEditedField(fieldToCommit)
        KeyboardDismissal.dismissNowAndDeferred()
    }

    private func commitEditedField(_ field: PromptField?) {
        guard field != nil else { return }
        saveCurrentState()
    }
}

#Preview {
    AIPromptSettingsView()
}
