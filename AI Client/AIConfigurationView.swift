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
    @FocusState private var focusedField: ConfigurationField?
    
    private let aiService = AIService()
    
    private enum ConfigurationField: Hashable {
        case name
        case baseURL
        case endpoint
        case apiKey
        case customHeaders
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
                modelsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI 配置")
            .onAppear {
                ensureSelection()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        focusedField = nil
                        saveCurrentState()
                        dismiss()
                    }
                }
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
                focusedField = nil
                addConfiguration()
            } label: {
                Label("新增配置", systemImage: "plus")
            }
            
            Button(role: .destructive) {
                focusedField = nil
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
    
    private var modelsSection: some View {
        Section {
            HStack {
                TextField("添加模型", text: $newModelName)
                    .focused($focusedField, equals: .newModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                Button("添加") {
                    focusedField = nil
                    addModel()
                }
                .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Button {
                focusedField = nil
                fetchModels()
            } label: {
                if isFetchingModels {
                    ProgressView()
                } else {
                    Label("自动获取模型", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetchingModels)
            
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: supportsReasoningBinding(for: model.name))
                        .labelsHidden()
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
            Text("自动获取会根据 Base URL 推断 /models 地址，适用于 OpenAI-compatible 服务。")
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
    
    private func addConfiguration() {
        var configuration = AIConfiguration()
        configuration.name = "配置 \(configurations.count + 1)"
        configurations.append(configuration)
        selectedConfigurationID = configuration.id
        newModelName = ""
        modelFetchMessage = nil
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
    
    private func fetchModels() {
        guard let configuration = selectedConfiguration else { return }
        isFetchingModels = true
        modelFetchMessage = nil
        
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
                updateSelectedConfiguration { configuration in
                    configuration.models = models.map { model in
                        AIModelConfiguration(
                            name: model.name,
                            supportsReasoning: model.supportsReasoning
                        )
                    }
                    if !configuration.models.contains(where: { $0.name == configuration.selectedModel }) {
                        configuration.selectedModel = configuration.models[0].name
                    }
                }
                let reasoningModelCount = models.filter(\.supportsReasoning).count
                modelFetchMessage = "已获取 \(models.count) 个模型，识别到 \(reasoningModelCount) 个支持推理。"
            case .failure(let error):
                modelFetchMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AIConfigurationView()
}
