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
    @State private var editingModelParameterName: String?
    @State private var saveErrorMessage: String?
    @AppStorage(AIConfigurationStore.hapticFeedbackEnabledKey)
    private var isHapticFeedbackEnabled = AIConfigurationStore.defaultHapticFeedbackEnabled
    @FocusState private var focusedField: ConfigurationField?
    
    private let aiService = AIService()
    
    private enum ConfigurationField: Hashable {
        case name
        case baseURL
        case endpoint
        case apiKey
        case customHeaders
        case modelAlias(String)
        case newModel
    }

    private enum AddConfigurationMenuItem: Identifiable {
        case deepSeek
        case provider(BuiltInAIProvider)

        var id: String {
            switch self {
            case .deepSeek:
                return "deepseek"
            case .provider(let provider):
                return provider.id
            }
        }

        var title: String {
            switch self {
            case .deepSeek:
                return "DeepSeek"
            case .provider(let provider):
                return provider.displayName
            }
        }

        var sortKey: String {
            switch self {
            case .deepSeek:
                return "deepseek"
            case .provider(let provider):
                return provider.menuSortKey
            }
        }
    }

    private var defaultConfigurationMenuItems: [AddConfigurationMenuItem] {
        let defaultProviders = BuiltInAIProvider.allCases
            .filter(\.isDefaultConfigurationTemplate)
            .map(AddConfigurationMenuItem.provider)
        return sortedMenuItems(defaultProviders)
    }

    private var providerMenuItems: [AddConfigurationMenuItem] {
        let providers = BuiltInAIProvider.allCases
            .filter { !$0.isDefaultConfigurationTemplate }
            .map(AddConfigurationMenuItem.provider)
        let items = [AddConfigurationMenuItem.deepSeek] + providers
        return sortedMenuItems(items)
    }

    private func sortedMenuItems(_ items: [AddConfigurationMenuItem]) -> [AddConfigurationMenuItem] {
        return items.sorted { lhs, rhs in
            lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
        }
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
                interactionSection
                imageContextSection
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
                if normalizeConfigurationNames() {
                    saveCurrentState()
                }
            }
            .onDisappear {
                commitSelectedConfigurationName()
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
            .sheet(isPresented: $isModelImportSheetPresented) {
                modelImportSheet
            }
            .sheet(isPresented: modelParameterEditorIsPresented) {
                modelParameterEditorSheet
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

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            Menu {
                Menu("默认配置") {
                    ForEach(defaultConfigurationMenuItems) { item in
                        addConfigurationButton(for: item)
                    }
                }

                ForEach(providerMenuItems) { item in
                    addConfigurationButton(for: item)
                }
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

    private func addConfigurationButton(for item: AddConfigurationMenuItem) -> some View {
        Button {
            hideKeyboard()
            switch item {
            case .deepSeek:
                addConfiguration()
            case .provider(let provider):
                addConfiguration(from: provider)
            }
        } label: {
            Text(item.title)
        }
    }
    
    private var requestSection: some View {
        Section {
            TextField("名称", text: selectedNameBinding)
                .focused($focusedField, equals: .name)
                .onSubmit {
                    commitSelectedConfigurationName()
                }
            Picker("API 类型", selection: selectedAPIFormatBinding) {
                ForEach(AIAPIFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            TextField("Base URL", text: selectedBaseURLBinding)
                .focused($focusedField, equals: .baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("Endpoint", text: selectedEndpointBinding)
                .focused($focusedField, equals: .endpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if selectedConfiguration?.apiFormat == .anthropicMessages {
                TextField("Max Tokens", text: anthropicMaxTokensBinding)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("请求地址")
        } footer: {
            Text(selectedConfiguration?.apiFormat.requestFooterText ?? AIAPIFormat.openAIChatCompletions.requestFooterText)
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
            Text(authFooterText)
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
            Text("每行一个请求头，格式为 Header-Name: value。Authorization、Token、API Key 等敏感请求头会存入钥匙串。")
        }
    }

    private var interactionSection: some View {
        Section {
            Toggle("开启触感反馈", isOn: $isHapticFeedbackEnabled)
        } header: {
            Text("交互")
        } footer: {
            Text("关闭后，输出刷新、输出完成和手动停止都不会触发震动。")
        }
    }

    private var imageContextSection: some View {
        Section {
            Toggle(
                "使用多模态模型为文字模型生成图片描述",
                isOn: generatesImageContextDescriptionsBinding
            )
        } header: {
            Text("图片描述")
        } footer: {
            Text("开启后，发送图片给支持图片的模型时，会自动生成隐藏描述并保存在对话中；以后切换到文字模型时可用这段描述代替图片上下文。")
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
                CollapsibleErrorMessageView(message: modelFetchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(selectedConfiguration?.models ?? []) { model in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name)
                            .font(.headline)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("别名")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("输入模型别名（可选）", text: modelAliasBinding(for: model.name))
                                .focused($focusedField, equals: .modelAlias(model.name))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("\(model.supportsReasoning ? "支持推理" : "不支持推理") · \(model.supportsImages ? "支持图片" : "仅文字")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            hideKeyboard()
                            editingModelParameterName = model.name
                        } label: {
                            HStack(spacing: 6) {
                                Text("详细参数")
                                Text(modelParameterSummary(for: model))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .trailing, spacing: 10) {
                        CheckboxButton("推理", isOn: supportsReasoningBinding(for: model.name))
                        CheckboxButton("图片", isOn: supportsImagesBinding(for: model.name))

                        Button(role: .destructive) {
                            deleteModel(model.name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled((selectedConfiguration?.models.count ?? 0) <= 1)
                    }
                    .fixedSize()
                    .padding(.top, 2)
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("模型参数按模型独立保存。空参数不会发送；上下文窗口仅作为模型能力信息保存。")
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

    private var modelParameterEditorIsPresented: Binding<Bool> {
        Binding(
            get: { editingModelParameterName != nil },
            set: { isPresented in
                if !isPresented {
                    editingModelParameterName = nil
                }
            }
        )
    }

    private var modelParameterEditorSheet: some View {
        NavigationStack {
            Form {
                if let modelName = editingModelParameterName,
                   let model = selectedConfiguration?.models.first(where: { $0.name == modelName }) {
                    Section {
                        Text(model.name)
                            .font(.headline)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        TextField("温度（空为默认）", text: modelOptionalDoubleBinding(
                            for: model.name,
                            keyPath: \.temperature,
                            range: 0...Double.greatestFiniteMagnitude
                        ))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField("top_p（0-1，空为默认）", text: modelOptionalDoubleBinding(
                            for: model.name,
                            keyPath: \.topP,
                            range: 0.000001...1
                        ))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField(
                            "上下文窗口 tokens（仅保存）",
                            text: modelOptionalIntBinding(for: model.name, keyPath: \.contextWindowTokens)
                        )
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField(
                            "最大输出 tokens（空为默认）",
                            text: modelOptionalIntBinding(for: model.name, keyPath: \.maxOutputTokens)
                        )
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } footer: {
                        Text("空参数不会发送；上下文窗口只作为模型能力信息保存。Anthropic 的 max_tokens 使用 provider 级设置。")
                    }
                } else {
                    Text("未找到模型。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("详细参数")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        hideKeyboard()
                        editingModelParameterName = nil
                    }
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
                commitEditedField(focusedField)
                selectedConfigurationID = newValue
                AIConfigurationStore.saveSelectedConfigurationID(newValue)
                saveCurrentState()
            }
        )
    }
    
    private var selectedNameBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.name ?? "" },
            set: { newValue in
                ensureSelection()
                guard let selectedIndex else { return }
                configurations[selectedIndex].name = newValue
            }
        )
    }
    
    private var selectedBaseURLBinding: Binding<String> {
        binding(\.baseURL)
    }
    
    private var selectedEndpointBinding: Binding<String> {
        binding(\.endpoint)
    }

    private var selectedAPIFormatBinding: Binding<AIAPIFormat> {
        Binding(
            get: { selectedConfiguration?.apiFormat ?? .openAIChatCompletions },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    let defaultEndpoints = Set(AIAPIFormat.allCases.map(\.defaultEndpoint))
                    let defaultBaseURLs = Set(AIAPIFormat.allCases.map(\.defaultBaseURL))
                    let currentEndpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                    let currentBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

                    configuration.apiFormat = newValue
                    if currentBaseURL.isEmpty || defaultBaseURLs.contains(currentBaseURL) {
                        configuration.baseURL = newValue.defaultBaseURL
                    }
                    if currentEndpoint.isEmpty || defaultEndpoints.contains(currentEndpoint) {
                        configuration.endpoint = newValue.defaultEndpoint
                    }
                }
            }
        )
    }

    private var anthropicMaxTokensBinding: Binding<String> {
        Binding(
            get: {
                "\(selectedConfiguration?.anthropicMaxTokens ?? AIConfiguration.defaultAnthropicMaxTokens)"
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedValue.isEmpty,
                          let maxTokens = Int(trimmedValue),
                          maxTokens > 0 else {
                        configuration.anthropicMaxTokens = AIConfiguration.defaultAnthropicMaxTokens
                        return
                    }
                    configuration.anthropicMaxTokens = maxTokens
                }
            }
        )
    }
    
    private var selectedAPIKeyBinding: Binding<String> {
        Binding(
            get: { selectedConfiguration?.apiKey ?? "" },
            set: { newValue in
                updateSelectedConfiguration(persists: false) { configuration in
                    configuration.apiKey = newValue
                }
            }
        )
    }
    
    private var selectedCustomHeadersBinding: Binding<String> {
        binding(\.customHeaders)
    }

    private var authFooterText: String {
        switch selectedConfiguration?.apiFormat ?? .openAIChatCompletions {
        case .openAIChatCompletions, .openAIResponses:
            return "填写 API Key 时会自动发送 Authorization: Bearer <API Key>。API Key 会存入钥匙串。"
        case .anthropicMessages:
            return "Anthropic Messages 会把 API Key 作为 x-api-key 发送，并自动附加 anthropic-version。API Key 会存入钥匙串。"
        case .vertexAIExpress:
            return "Vertex Express 会把 API Key 加到请求 query 中；错误诊断会隐藏 query，API Key 会存入钥匙串。"
        }
    }

    private var generatesImageContextDescriptionsBinding: Binding<Bool> {
        Binding(
            get: { selectedConfiguration?.generatesImageContextDescriptions ?? true },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    configuration.generatesImageContextDescriptions = newValue
                }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<AIConfiguration, String>) -> Binding<String> {
        Binding(
            get: { selectedConfiguration?[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateSelectedConfiguration(persists: false) { configuration in
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
    
    private func saveCurrentState(normalizesNames: Bool = false) {
        ensureSelection()
        if normalizesNames {
            normalizeConfigurationNames()
        }
        let didSave = AIConfigurationStore.saveConfigurations(configurations)
        saveErrorMessage = didSave ? nil : "配置保存失败，请检查钥匙串或本机存储权限。"
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

    private func commitEditedField(_ field: ConfigurationField?) {
        guard let field else { return }

        switch field {
        case .name:
            commitSelectedConfigurationName()
        case .newModel:
            break
        default:
            saveCurrentState()
        }
    }

    private func commitSelectedConfigurationName() {
        ensureSelection()
        guard let selectedIndex else { return }
        let configurationID = configurations[selectedIndex].id
        let uniqueName = AIConfigurationStore.uniqueConfigurationName(
            configurations[selectedIndex].name,
            among: configurations,
            excluding: configurationID
        )
        if configurations[selectedIndex].name != uniqueName {
            configurations[selectedIndex].name = uniqueName
            configurations[selectedIndex].updatedAt = Date()
        }
        saveCurrentState()
    }

    @discardableResult
    private func normalizeConfigurationNames() -> Bool {
        var normalizedConfigurations: [AIConfiguration] = []
        var didChange = false

        for index in configurations.indices {
            var configuration = configurations[index]
            let uniqueName = AIConfigurationStore.uniqueConfigurationName(
                configuration.name,
                among: normalizedConfigurations
            )

            if configuration.name != uniqueName {
                configuration.name = uniqueName
                configuration.updatedAt = Date()
                configurations[index] = configuration
                didChange = true
            }

            normalizedConfigurations.append(configuration)
        }

        return didChange
    }
    
    private func addConfiguration(from provider: BuiltInAIProvider? = nil) {
        var configuration = provider?.makeConfiguration() ?? AIConfiguration()
        if provider == nil {
            configuration.name = "配置 \(configurations.count + 1)"
        }
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
        KeychainService.deleteAllSecrets(for: removedConfiguration.id)
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

    private func modelAliasBinding(for model: String) -> Binding<String> {
        Binding(
            get: {
                selectedConfiguration?.models.first { $0.name == model }?.alias ?? ""
            },
            set: { newValue in
                updateSelectedConfiguration(persists: false) { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    configuration.models[index].alias = newValue
                }
            }
        )
    }

    private func modelParameterSummary(for model: AIModelConfiguration) -> String {
        var parts = [String]()
        if let temperature = model.temperature {
            parts.append("温度 \(Self.parameterString(from: temperature))")
        }
        if let topP = model.topP {
            parts.append("top_p \(Self.parameterString(from: topP))")
        }
        if let contextWindowTokens = model.contextWindowTokens {
            parts.append("上下文 \(contextWindowTokens)")
        }
        if let maxOutputTokens = model.maxOutputTokens {
            parts.append("输出 \(maxOutputTokens)")
        }

        return parts.isEmpty ? "默认" : parts.joined(separator: " · ")
    }

    private func modelOptionalDoubleBinding(
        for model: String,
        keyPath: WritableKeyPath<AIModelConfiguration, Double?>,
        range: ClosedRange<Double>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = selectedConfiguration?.models.first(where: { $0.name == model })?[keyPath: keyPath] else {
                    return ""
                }
                return Self.parameterString(from: value)
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedValue.isEmpty else {
                        configuration.models[index][keyPath: keyPath] = nil
                        return
                    }
                    guard let value = Double(trimmedValue),
                          value.isFinite,
                          range.contains(value) else {
                        return
                    }
                    configuration.models[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func modelOptionalIntBinding(
        for model: String,
        keyPath: WritableKeyPath<AIModelConfiguration, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = selectedConfiguration?.models.first(where: { $0.name == model })?[keyPath: keyPath] else {
                    return ""
                }
                return "\(value)"
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedValue.isEmpty else {
                        configuration.models[index][keyPath: keyPath] = nil
                        return
                    }
                    guard let value = Int(trimmedValue), value > 0 else { return }
                    configuration.models[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private static func parameterString(from value: Double) -> String {
        let formatted = String(format: "%.4f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
    
    private func fetchModels() {
        guard let configuration = selectedConfiguration else { return }
        isFetchingModels = true
        modelFetchMessage = nil
        fetchedModels = []
        selectedFetchedModelNames.removeAll()
        
        aiService.fetchModels(
            baseURL: configuration.requestURLString,
            apiFormat: configuration.apiFormat,
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
                    var importedModel = model
                    let existingModel = configuration.models[index]
                    importedModel.alias = existingModel.alias
                    importedModel.temperature = existingModel.temperature
                    importedModel.topP = existingModel.topP
                    importedModel.contextWindowTokens = existingModel.contextWindowTokens
                    importedModel.maxOutputTokens = existingModel.maxOutputTokens
                    configuration.models[index] = importedModel
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
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
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
