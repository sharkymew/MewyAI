import SwiftUI
import UIKit
@preconcurrency import UserNotifications

struct AIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showAgentCapabilities = false
    @State private var showMemorySettings = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?
    @AppStorage(AIConfigurationStore.hapticFeedbackEnabledKey)
    private var isHapticFeedbackEnabled = AIConfigurationStore.defaultHapticFeedbackEnabled
    @AppStorage(ChatMemoryStore.memoryEnabledKey)
    private var isGlobalMemoryEnabled = ChatMemoryStore.defaultMemoryEnabled
    @AppStorage(ChatMemoryStore.historyRecallEnabledKey)
    private var isHistoryRecallEnabled = ChatMemoryStore.defaultHistoryRecallEnabled
    @AppStorage(AIConfigurationStore.saveCapturedPhotosToLibraryKey)
    private var isSaveCapturedPhotosToLibraryEnabled = AIConfigurationStore.defaultSaveCapturedPhotosToLibrary
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

    private var notificationAuthorizationStatusText: String {
        guard let notificationAuthorizationStatus else {
            return String(localized: "检查中")
        }

        switch notificationAuthorizationStatus {
        case .notDetermined:
            return String(localized: "尚未请求")
        case .denied:
            return String(localized: "已关闭")
        case .authorized:
            return String(localized: "已允许")
        case .provisional:
            return String(localized: "临时允许")
        case .ephemeral:
            return String(localized: "本次允许")
        @unknown default:
            return String(localized: "未知")
        }
    }

    private var notificationAuthorizationStatusColor: Color {
        guard let notificationAuthorizationStatus else {
            return .secondary
        }

        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .secondary
        @unknown default:
            return .secondary
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
                modelsSection
                customHeadersSection
                agentCapabilitiesSection
                memorySection
                interactionSection
                notificationSection
                photoCaptureSection
                imageContextSection
                acknowledgementsSection
            }
            .background(
                KeyboardDismissTapLayer {
                    hideKeyboard()
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("设置")
            .onAppear {
                ensureSelection()
                refreshNotificationAuthorizationStatus()
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshNotificationAuthorizationStatus()
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
            .sheet(isPresented: $showAgentCapabilities) {
                AgentCapabilitiesView()
            }
            .sheet(isPresented: $showMemorySettings) {
                ChatMemorySettingsView()
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

    private var memorySection: some View {
        Section {
            Toggle(String(localized: "全局记忆"), isOn: $isGlobalMemoryEnabled)
            Toggle(String(localized: "参考历史对话"), isOn: $isHistoryRecallEnabled)

            Button {
                hideKeyboard()
                showMemorySettings = true
            } label: {
                Label(String(localized: "管理记忆"), systemImage: "brain")
            }
        } header: {
            Text(String(localized: "记忆"))
        } footer: {
            Text(String(localized: "全局记忆：每次对话完成后用当前模型在后台提取值得长期记住的信息，注入到之后的所有对话。参考历史对话：让支持工具调用的模型在需要时直接搜索和查阅全部历史对话，无需先保存记忆。临时聊天不参与两者。"))
        }
    }

    private var interactionSection: some View {
        Section {
            Toggle(String(localized: "开启触感反馈"), isOn: $isHapticFeedbackEnabled)
        } header: {
            Text(String(localized: "交互"))
        } footer: {
            Text(String(localized: "关闭后，输出刷新、输出完成和手动停止都不会触发震动。"))
        }
    }

    private var photoCaptureSection: some View {
        Section {
            Toggle(String(localized: "保存拍摄的照片到相册"), isOn: $isSaveCapturedPhotosToLibraryEnabled)
        } header: {
            Text(String(localized: "拍照"))
        } footer: {
            Text(String(localized: "在对话中拍摄的照片默认只用于发送，不写入系统相册。开启后会同时把原图保存到系统相册；在临时聊天中始终不会保存。"))
        }
    }

    private var notificationSection: some View {
        Section {
            HStack {
                Label(String(localized: "后台完成通知"), systemImage: "bell.badge")
                Spacer()
                Text(notificationAuthorizationStatusText)
                    .foregroundStyle(notificationAuthorizationStatusColor)
            }

            if notificationAuthorizationStatus == .denied {
                Button {
                    openAppNotificationSettings()
                } label: {
                    Label(String(localized: "打开系统通知设置"), systemImage: "gear")
                }
            }
        } header: {
            Text(String(localized: "通知"))
        } footer: {
            Text(String(localized: "App 在后台或非活跃状态完成普通对话后，会发送一条本机通知。临时聊天、失败或手动停止不会通知。"))
        }
    }

    private var agentCapabilitiesSection: some View {
        Section {
            Button {
                hideKeyboard()
                showAgentCapabilities = true
            } label: {
                Label("管理 Agent Skills 和 MCP", systemImage: "sparkles.square.filled.on.square")
            }
        } header: {
            Text("Agent 能力")
        } footer: {
            Text("Skills 是文本指令包；MCP 仅支持远程 HTTPS 服务器。本机不会执行 Python、shell 或本地脚本。")
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

    private var acknowledgementsSection: some View {
        Section {
            NavigationLink {
                ThirdPartyAcknowledgementsView()
            } label: {
                Label {
                    Text(AppLocalizations.string(
                        "acknowledgements.settings.title",
                        defaultValue: "Open Source Acknowledgements"
                    ))
                } icon: {
                    Image(systemName: "heart.text.square")
                }
            }
        } footer: {
            Text(AppLocalizations.string(
                "acknowledgements.settings.footer",
                defaultValue: "Lists the third-party open source projects and license information used by this app."
            ))
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

                        Text(modelCapabilitySummary(for: model))
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
                        CheckboxButton("工具", isOn: supportsToolsBinding(for: model.name))

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
                                        Text(modelReasoningCapabilityText(model.supportsReasoning))
                                        Text(modelImageCapabilityText(model.supportsImages))
                                        Text(modelToolCapabilityText(model.supportsTools))
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

                    Section {
                        TextField("输入价格 / 1M tokens（空为不计费）", text: modelOptionalDoubleBinding(
                            for: model.name,
                            keyPath: \.inputPricePerMillionTokens,
                            range: 0...Double.greatestFiniteMagnitude
                        ))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField("输出价格 / 1M tokens（空为不计费）", text: modelOptionalDoubleBinding(
                            for: model.name,
                            keyPath: \.outputPricePerMillionTokens,
                            range: 0...Double.greatestFiniteMagnitude
                        ))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Picker("货币", selection: modelPriceCurrencyBinding(for: model.name)) {
                            ForEach(ChatUsagePricing.supportedCurrencyCodes, id: \.self) { code in
                                Text("\(code) (\(ChatUsagePricing.currencySymbol(for: code)))")
                                    .tag(code)
                            }
                        }
                    } header: {
                        Text("价格")
                    } footer: {
                        Text("价格按每百万 tokens 手动维护，仅用于在会话中本地估算费用，不影响请求。")
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
            return AppLocalizations.string(
                "configuration.authFooter.bearer",
                defaultValue: "When an API Key is provided, Authorization: Bearer <API Key> is sent automatically. The API Key is stored in Keychain."
            )
        case .anthropicMessages:
            return AppLocalizations.string(
                "configuration.authFooter.anthropic",
                defaultValue: "Anthropic Messages sends the API Key as x-api-key and automatically adds anthropic-version. The API Key is stored in Keychain."
            )
        case .vertexAIExpress:
            return AppLocalizations.string(
                "configuration.authFooter.vertex",
                defaultValue: "Vertex Express adds the API Key to the request query. Error diagnostics hide the query, and the API Key is stored in Keychain."
            )
        }
    }

    private func modelCapabilitySummary(for model: AIModelConfiguration) -> String {
        [
            modelReasoningCapabilityText(model.supportsReasoning),
            modelImageCapabilityText(model.supportsImages),
            modelToolCapabilityText(model.supportsTools)
        ].joined(separator: " · ")
    }

    private func modelReasoningCapabilityText(_ isSupported: Bool) -> String {
        isSupported
            ? AppLocalizations.string("modelCapability.reasoningSupported", defaultValue: "Supports reasoning")
            : AppLocalizations.string("modelCapability.reasoningUnsupported", defaultValue: "No reasoning")
    }

    private func modelImageCapabilityText(_ isSupported: Bool) -> String {
        isSupported
            ? AppLocalizations.string("modelCapability.imagesSupported", defaultValue: "Supports images")
            : AppLocalizations.string("modelCapability.textOnly", defaultValue: "Text only")
    }

    private func modelToolCapabilityText(_ isSupported: Bool) -> String {
        isSupported
            ? AppLocalizations.string("modelCapability.toolsSupported", defaultValue: "Supports tools")
            : AppLocalizations.string("modelCapability.noTools", defaultValue: "No tools")
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

    private func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func openAppNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
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
        saveErrorMessage = didSave
            ? nil
            : AppLocalizations.string(
                "configuration.saveFailed",
                defaultValue: "Failed to save configuration. Check Keychain or local storage permissions."
            )
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
            configuration.name = AppLocalizations.format(
                "configuration.numberedName",
                defaultValue: "Configuration %d",
                arguments: [configurations.count + 1]
            )
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
                    configuration.models.append(AIModelConfiguration(
                        name: model,
                        supportsTools: AIModelConfiguration.defaultToolsSupport(for: model)
                    ))
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
        modelFetchMessage = AppLocalizations.string(
            "configuration.models.deletedAll",
            defaultValue: "Deleted all models in the current configuration."
        )
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

    private func supportsToolsBinding(for model: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedConfiguration?.models.first { $0.name == model }?.supportsTools == true
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    configuration.models[index].supportsTools = newValue
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
            parts.append(AppLocalizations.format(
                "modelParameters.temperature",
                defaultValue: "Temperature %@",
                arguments: [Self.parameterString(from: temperature)]
            ))
        }
        if let topP = model.topP {
            parts.append("top_p \(Self.parameterString(from: topP))")
        }
        if let contextWindowTokens = model.contextWindowTokens {
            parts.append(AppLocalizations.format(
                "modelParameters.context",
                defaultValue: "Context %d",
                arguments: [contextWindowTokens]
            ))
        }
        if let maxOutputTokens = model.maxOutputTokens {
            parts.append(AppLocalizations.format(
                "modelParameters.output",
                defaultValue: "Output %d",
                arguments: [maxOutputTokens]
            ))
        }
        if model.hasPricing {
            let currencySymbol = ChatUsagePricing.currencySymbol(
                for: model.priceCurrencyCode ?? ChatUsagePricing.defaultCurrencyCode
            )
            parts.append(AppLocalizations.format(
                "modelParameters.pricing",
                defaultValue: "Price %@%@/%@%@",
                arguments: [
                    currencySymbol,
                    Self.parameterString(from: model.inputPricePerMillionTokens ?? 0),
                    currencySymbol,
                    Self.parameterString(from: model.outputPricePerMillionTokens ?? 0)
                ]
            ))
        }

        return parts.isEmpty
            ? AppLocalizations.string("modelParameters.default", defaultValue: "Default")
            : parts.joined(separator: " · ")
    }

    private func modelPriceCurrencyBinding(for model: String) -> Binding<String> {
        Binding(
            get: {
                selectedConfiguration?.models.first(where: { $0.name == model })?.priceCurrencyCode
                    ?? ChatUsagePricing.defaultCurrencyCode
            },
            set: { newValue in
                updateSelectedConfiguration { configuration in
                    guard let index = configuration.models.firstIndex(where: { $0.name == model }) else { return }
                    configuration.models[index].priceCurrencyCode = newValue
                }
            }
        )
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
                    modelFetchMessage = AppLocalizations.string(
                        "configuration.models.fetchEmpty",
                        defaultValue: "No models were fetched."
                    )
                    return
                }
                let uniqueFetchedModels = uniqueModels(from: models)
                fetchedModels = uniqueFetchedModels
                let reasoningModelCount = uniqueFetchedModels.filter(\.supportsReasoning).count
                let imageModelCount = uniqueFetchedModels.filter(\.supportsImages).count
                let toolModelCount = uniqueFetchedModels.filter(\.supportsTools).count
                modelFetchMessage = AppLocalizations.format(
                    "configuration.models.fetchSuccess",
                    defaultValue: "Fetched %d models. Detected %d reasoning-capable, %d image-capable, and %d tool-capable models. Select models to import.",
                    arguments: [fetchedModels.count, reasoningModelCount, imageModelCount, toolModelCount]
                )
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
                    importedModel.inputPricePerMillionTokens = existingModel.inputPricePerMillionTokens
                    importedModel.outputPricePerMillionTokens = existingModel.outputPricePerMillionTokens
                    importedModel.priceCurrencyCode = existingModel.priceCurrencyCode
                    configuration.models[index] = importedModel
                } else {
                    configuration.models.append(model)
                }
            }

            if configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.selectedModel = selectedModels[0].name
            }
        }

        modelFetchMessage = AppLocalizations.format(
            "configuration.models.imported",
            defaultValue: "Imported %d models.",
            arguments: [selectedModels.count]
        )
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
        .accessibilityValue(isOn
            ? AppLocalizations.string("accessibility.selected", defaultValue: "Selected")
            : AppLocalizations.string("accessibility.notSelected", defaultValue: "Not selected"))
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
