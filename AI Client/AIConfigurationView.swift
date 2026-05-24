import SwiftUI

struct AIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var showAPIKey = false
    @State private var showCustomHeaders = false
    @State private var newModelName = ""
    @State private var modelFetchMessage: String?
    @State private var isFetchingModels = false
    @State private var fetchedModels: [AIModelConfiguration] = []
    @State private var selectedFetchedModelNames: Set<String> = []
    @State private var isModelImportSheetPresented = false
    @State private var isDeleteAllModelsConfirmationPresented = false
    @FocusState private var focusedField: ConfigurationField?
    
    private let aiService = AIService()
    
    private enum ConfigurationField: Hashable {
        case name
        case baseURL
        case endpoint
        case apiKey
        case customHeaders
        case systemPrompt
        case newModel
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
                configurationPickerSection
                requestSection
                authSection
                customHeadersSection
                promptSection
                modelsSection
            }
            .background(
                KeyboardDismissTapLayer {
                    hideKeyboard()
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI 配置")
            .onAppear {
                ensureSelection()
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
            .sheet(isPresented: $isModelImportSheetPresented) {
                modelImportSheet
            }
            .confirmationDialog(
                "删除本配置下的所有模型？",
                isPresented: $isDeleteAllModelsConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("删除所有模型", role: .destructive) {
                    deleteAllModels()
                }
            } message: {
                Text("这只会清空当前配置的模型列表，不会删除配置组或 API Key。")
            }
        }
    }
    
    private var configurationPickerSection: some View {
        Section {
            Picker("当前配置", selection: selectedConfigurationBinding) {
                ForEach(configurations) { configuration in
                    Text(configuration.name).tag(configuration.id)
                }
            }
            
            Button {
                hideKeyboard()
                addConfiguration()
            } label: {
                Label("新增配置", systemImage: "plus")
            }
            
            Button(role: .destructive) {
                hideKeyboard()
                deleteCurrentConfiguration()
            } label: {
                Label("删除当前配置", systemImage: "trash")
            }
            .disabled(configurations.count <= 1)
        } header: {
            Text("配置组")
        }
    }
    
    private var requestSection: some View {
        Section {
            TextField("名称", text: selectedNameBinding)
                .focused($focusedField, equals: .name)
            TextField("Base URL", text: selectedBaseURLBinding)
                .focused($focusedField, equals: .baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("Endpoint", text: selectedEndpointBinding)
                .focused($focusedField, equals: .endpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("请求地址")
        } footer: {
            Text("Endpoint 默认是 chat/completions，会与 Base URL 拼成最终请求地址。")
        }
    }
    
    private var authSection: some View {
        Section {
            if showAPIKey {
                TextField("API Key", text: selectedAPIKeyBinding)
                    .focused($focusedField, equals: .apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField("API Key", text: selectedAPIKeyBinding)
                    .focused($focusedField, equals: .apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            
            Toggle("显示 API Key", isOn: $showAPIKey)
        } header: {
            Text("认证")
        } footer: {
            Text("填写 API Key 时会自动发送 Authorization: Bearer <API Key>。如果服务商使用其他认证方式，可以留空并在自定义请求头中配置。")
        }
    }
    
    private var customHeadersSection: some View {
        Section {
            DisclosureGroup("自定义请求头", isExpanded: $showCustomHeaders) {
                TextEditor(text: selectedCustomHeadersBinding)
                    .focused($focusedField, equals: .customHeaders)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } footer: {
            Text("每行一个请求头，格式为 Header-Name: value。自定义请求头会覆盖同名默认请求头。")
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
                .focused($focusedField, equals: .systemPrompt)

            TextEditor(text: selectedPromptPresetContentBinding)
                .focused($focusedField, equals: .systemPrompt)
                .frame(minHeight: 140)
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
        } header: {
            Text("提示词")
        } footer: {
            Text("当前选中的内容会作为每次对话的 system message 发送。留空则不发送提示词。")
        }
    }
    
    private var modelsSection: some View {
        Section {
            HStack {
                TextField("添加模型", text: $newModelName)
                    .focused($focusedField, equals: .newModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                Button("添加") {
                    hideKeyboard()
                    addModel()
                }
                .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Button {
                hideKeyboard()
                fetchModels()
            } label: {
                if isFetchingModels {
                    ProgressView()
                } else {
                    Label("自动获取模型", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetchingModels)

            Button(role: .destructive) {
                hideKeyboard()
                isDeleteAllModelsConfirmationPresented = true
            } label: {
                Label("删除所有模型", systemImage: "trash")
            }
            .disabled((selectedConfiguration?.models.isEmpty ?? true) || isFetchingModels)
            
            if let modelFetchMessage {
                Text(modelFetchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(selectedConfiguration?.models ?? []) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(model.supportsReasoning ? "支持推理" : "不支持推理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.supportsImages ? "支持图片" : "仅文字")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        CheckboxButton("推理", isOn: supportsReasoningBinding(for: model.name))
                        CheckboxButton("图片", isOn: supportsImagesBinding(for: model.name))
                    }
                    .fixedSize()
                    
                    Button(role: .destructive) {
                        deleteModel(model.name)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled((selectedConfiguration?.models.count ?? 0) <= 1)
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("自动获取会根据 Base URL 推断 /models 地址，适用于 OpenAI-compatible 服务；获取结果需要确认后才会加入当前配置。")
        }
    }

    private var modelImportSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button("全选") {
                        selectedFetchedModelNames = Set(fetchedModels.map(\.name))
                    }
                    .disabled(fetchedModels.isEmpty)

                    Button("清空选择") {
                        selectedFetchedModelNames.removeAll()
                    }
                    .disabled(selectedFetchedModelNames.isEmpty)
                }

                Section {
                    ForEach(fetchedModels) { model in
                        Button {
                            toggleFetchedModelSelection(model.name)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CheckboxIndicator(isOn: selectedFetchedModelNames.contains(model.name))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    HStack(spacing: 8) {
                                        Text(model.supportsReasoning ? "支持推理" : "不支持推理")
                                        Text(model.supportsImages ? "支持图片" : "仅文字")
                                        if selectedConfiguration?.models.contains(where: { $0.name == model.name }) == true {
                                            Text("已在当前配置中")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("可导入模型")
                } footer: {
                    Text("导入已存在的模型会更新它的推理与图片能力标记。")
                }
            }
            .navigationTitle("选择模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isModelImportSheetPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        importSelectedFetchedModels()
                    }
                    .disabled(selectedFetchedModelNames.isEmpty)
                }
            }
        }
    }
    
    private var selectedConfigurationBinding: Binding<UUID> {
        Binding(
            get: {
                ensureSelection()
                return selectedConfigurationID ?? configurations[0].id
            },
            set: { newValue in
                selectedConfigurationID = newValue
                AIConfigurationStore.saveSelectedConfigurationID(newValue)
                saveCurrentState()
            }
        )
    }
    
    private var selectedNameBinding: Binding<String> {
        binding(\.name)
    }
    
    private var selectedBaseURLBinding: Binding<String> {
        binding(\.baseURL)
    }
    
    private var selectedEndpointBinding: Binding<String> {
        binding(\.endpoint)
    }
    
    private var selectedAPIKeyBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.apiKey ?? "" },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration.apiKey = newValue
                    KeychainService.saveAPIKey(newValue, for: configuration.id)
                }
            }
        )
    }
    
    private var selectedCustomHeadersBinding: Binding<String> {
        binding(\.customHeaders)
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
                updateSelectedConfiguration { configuration in
                    configuration.updateSelectedPromptName(newValue)
                }
            }
        )
    }

    private var selectedPromptPresetContentBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.selectedPromptPreset?.content ?? "" },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration.updateSelectedPromptContent(newValue)
                }
            }
        )
    }
    
    private func binding(_ keyPath: WritableKeyPath<AIConfiguration, String>) -> Binding<String> {
        Binding(
            get: { selectedConfiguration?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration[keyPath: keyPath] = newValue
                }
            }
        )
    }
    
    private func ensureSelection() {
        if configurations.isEmpty {
            configurations = [AIConfiguration()]
        }
        
        if selectedConfigurationID == nil || !configurations.contains(where: { $0.id == selectedConfigurationID }) {
            selectedConfigurationID = configurations[0].id
            AIConfigurationStore.saveSelectedConfigurationID(configurations[0].id)
        }
    }
    
    private func updateSelectedConfiguration(_ update: (inout AIConfiguration) -> Void) {
        ensureSelection()
        guard let selectedIndex else { return }
        update(&configurations[selectedIndex])
        configurations[selectedIndex].updatedAt = Date()
        saveCurrentState()
    }
    
    private func saveCurrentState() {
        ensureSelection()
        AIConfigurationStore.saveConfigurations(configurations)
        if let selectedConfigurationID {
            AIConfigurationStore.saveSelectedConfigurationID(selectedConfigurationID)
        }
    }

    private func hideKeyboard() {
        focusedField = nil
        KeyboardDismissal.dismissNowAndDeferred()
    }
    
    private func addConfiguration() {
        var configuration = AIConfiguration()
        configuration.name = "配置 \(configurations.count + 1)"
        configurations.append(configuration)
        selectedConfigurationID = configuration.id
        newModelName = ""
        modelFetchMessage = nil
        fetchedModels = []
        selectedFetchedModelNames.removeAll()
        saveCurrentState()
    }
    
    private func deleteCurrentConfiguration() {
        guard configurations.count > 1,
              let selectedIndex else { return }
        let removedConfiguration = configurations.remove(at: selectedIndex)
        KeychainService.deleteAPIKey(for: removedConfiguration.id)
        selectedConfigurationID = configurations[0].id
        saveCurrentState()
    }
    
    private func addModel() {
        let model = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        
        updateSelectedConfiguration { configuration in
            if !configuration.models.contains(where: { $0.name == model }) {
                configuration.models.append(AIModelConfiguration(name: model))
            }
            configuration.selectedModel = model
        }
        
        newModelName = ""
    }
    
    private func deleteModel(_ model: String) {
        updateSelectedConfiguration { configuration in
            guard configuration.models.count > 1 else { return }
            configuration.models.removeAll { $0.name == model }
            if !configuration.models.contains(where: { $0.name == configuration.selectedModel }) {
                configuration.selectedModel = configuration.models.first?.name ?? ""
            }
        }
    }

    private func deleteAllModels() {
        updateSelectedConfiguration { configuration in
            configuration.models.removeAll()
            configuration.selectedModel = ""
        }
        modelFetchMessage = "已删除当前配置下的所有模型。"
    }
    
    private func supportsReasoningBinding(for model: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedConfiguration?.models.first { $0.name == model }?.supportsReasoning == true
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    configuration.models[index].supportsReasoning = newValue
                }
            }
        )
    }
    
    private func supportsImagesBinding(for model: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedConfiguration?.models.first { $0.name == model }?.supportsImages == true
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    configuration.models[index].supportsImages = newValue
                }
            }
        )
    }
    
    private func fetchModels() {
        guard let configuration = selectedConfiguration else { return }
        isFetchingModels = true
        modelFetchMessage = nil
        fetchedModels = []
        selectedFetchedModelNames.removeAll()
        
        aiService.fetchModels(
            baseURL: configuration.baseURL,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders
        ) { result in
            isFetchingModels = false
            
            switch result {
            case .success(let models):
                guard !models.isEmpty else {
                    modelFetchMessage = "没有获取到模型。"
                    return
                }
                let uniqueFetchedModels = uniqueModels(from: models)
                fetchedModels = uniqueFetchedModels
                let reasoningModelCount = uniqueFetchedModels.filter(\.supportsReasoning).count
                let imageModelCount = uniqueFetchedModels.filter(\.supportsImages).count
                modelFetchMessage = "已获取 \(fetchedModels.count) 个模型，识别到 \(reasoningModelCount) 个支持推理、\(imageModelCount) 个支持图片，请选择要导入的模型。"
                isModelImportSheetPresented = true
            case .failure(let error):
                modelFetchMessage = error.localizedDescription
            }
        }
    }

    private func toggleFetchedModelSelection(_ model: String) {
        if selectedFetchedModelNames.contains(model) {
            selectedFetchedModelNames.remove(model)
        } else {
            selectedFetchedModelNames.insert(model)
        }
    }

    private func importSelectedFetchedModels() {
        let selectedModels = fetchedModels.filter { selectedFetchedModelNames.contains($0.name) }
        guard !selectedModels.isEmpty else { return }

        updateSelectedConfiguration { configuration in
            for model in selectedModels {
                if let index = configuration.models.firstIndex(where: { $0.name == model.name }) {
                    configuration.models[index] = model
                } else {
                    configuration.models.append(model)
                }
            }

            if configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.selectedModel = selectedModels[0].name
            }
        }

        modelFetchMessage = "已导入 \(selectedModels.count) 个模型。"
        selectedFetchedModelNames.removeAll()
        isModelImportSheetPresented = false
    }

    private func uniqueModels(from models: [AIModelConfiguration]) -> [AIModelConfiguration] {
        var seenNames = Set<String>()
        return models.filter { model in
            seenNames.insert(model.name).inserted
        }
    }
}

private struct CheckboxButton: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            } icon: {
                CheckboxIndicator(isOn: isOn)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "已选中" : "未选中")
    }
}

private struct CheckboxIndicator: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
    }
}

#Preview {
    AIConfigurationView()
}
