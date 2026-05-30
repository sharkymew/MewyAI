import SwiftUI

struct AIPromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID: UUID?
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: PromptField?

    private let configurationID: UUID?

    init(configurationID: UUID? = nil) {
        self.configurationID = configurationID
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
                ForEach(selectedConfiguration?.promptPresets ?? []) { promptPreset in
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
                updateSelectedConfiguration { configuration in
                    configuration.addPromptPreset()
                }
            }

            Button("恢复默认内容") {
                hideKeyboard()
                updateSelectedConfiguration { configuration in
                    configuration.restoreDefaultSelectedPrompt()
                }
            }
            .disabled(selectedConfiguration?.systemPrompt == AIConfiguration.defaultSystemPrompt)

            Button(role: .destructive) {
                hideKeyboard()
                updateSelectedConfiguration { configuration in
                    configuration.deleteSelectedPromptPreset()
                }
            } label: {
                Label("删除当前提示词", systemImage: "trash")
            }
            .disabled((selectedConfiguration?.promptPresets.count ?? 0) <= 1)

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("提示词")
        } footer: {
            Text("当前选中的内容会作为每次对话的 system message 发送。留空则不发送提示词。")
        }
    }

    private var selectedPromptPresetIDBinding: Binding<UUID> {
        Binding(
            get: {
                selectedConfiguration?.selectedPromptPreset?.id
                    ?? selectedConfiguration?.promptPresets.first?.id
                    ?? UUID()
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration.selectPromptPreset(newValue)
                }
            }
        )
    }

    private var selectedPromptPresetNameBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.selectedPromptPreset?.name ?? "" },
            set: { newValue in
                updateSelectedConfiguration(persists: false) { configuration in
                    configuration.updateSelectedPromptName(newValue)
                }
            }
        )
    }

    private var selectedPromptPresetContentBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.selectedPromptPreset?.content ?? "" },
            set: { newValue in
                updateSelectedConfiguration(persists: false) { configuration in
                    configuration.updateSelectedPromptContent(newValue)
                }
            }
        )
    }

    private func ensureSelection() {
        if configurations.isEmpty {
            configurations = [AIConfiguration()]
        }

        if let configurationID,
           configurations.contains(where: { $0.id == configurationID }) {
            selectedConfigurationID = configurationID
            return
        }

        if let selectedConfigurationID,
           configurations.contains(where: { $0.id == selectedConfigurationID }) {
            return
        }

        if let storedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID(),
           configurations.contains(where: { $0.id == storedConfigurationID }) {
            selectedConfigurationID = storedConfigurationID
        } else {
            selectedConfigurationID = configurations[0].id
        }
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

    private func saveCurrentState() {
        ensureSelection()
        let didSave = AIConfigurationStore.saveConfigurations(configurations)
        saveErrorMessage = didSave ? nil : "提示词保存失败，请检查钥匙串或本机存储权限。"
        if let selectedConfigurationID {
            AIConfigurationStore.saveSelectedConfigurationID(selectedConfigurationID)
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
