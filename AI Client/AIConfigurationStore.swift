import Foundation

enum ReasoningEffort: String, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        case .max:
            return "极高"
        }
    }
}

enum AIAPIFormat: String, CaseIterable, Codable, Identifiable {
    case openAIChatCompletions
    case openAIResponses
    case anthropicMessages
    case vertexAIExpress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIChatCompletions:
            return "Chat Completions"
        case .openAIResponses:
            return "OpenAI Responses"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .vertexAIExpress:
            return "Google Vertex AI Express"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAIChatCompletions:
            return "https://api.deepseek.com"
        case .openAIResponses:
            return "https://api.openai.com/v1"
        case .anthropicMessages:
            return "https://api.anthropic.com"
        case .vertexAIExpress:
            return "https://aiplatform.googleapis.com"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAIChatCompletions:
            return "chat/completions"
        case .openAIResponses:
            return "responses"
        case .anthropicMessages:
            return "v1/messages"
        case .vertexAIExpress:
            return "v1/publishers/google/models/{model}:generateContent"
        }
    }

    var requestFooterText: String {
        switch self {
        case .openAIChatCompletions:
            return "Chat Completions 会把 Endpoint 与 Base URL 拼成最终请求地址，默认 endpoint 是 chat/completions。"
        case .openAIResponses:
            return "Responses API 默认 endpoint 是 responses，模型参数会按 Responses 字段名发送。"
        case .anthropicMessages:
            return "Anthropic Messages 默认 endpoint 是 v1/messages，默认认证使用 x-api-key；模型名以 [1m] 结尾时会按 1M 上下文发送但实际 model 会去掉该后缀。开启 Claude Code 伪装后，所有模型都会改用 Bearer，并自动附加 beta=true、1M context、Claude Code headers 和请求体字段。Max Tokens 仅对当前配置生效。"
        case .vertexAIExpress:
            return "Vertex Express 默认 endpoint 使用 {model} 占位符，发送时会替换为当前模型 ID。"
        }
    }
}

nonisolated enum CustomHeaderSecurity {
    static let keychainPlaceholder = "__AI_CLIENT_KEYCHAIN_SECRET__"

    private static let forbiddenRequestHeaderNames: Set<String> = [
        "connection",
        "content-length",
        "cookie",
        "host",
        "proxy-authorization",
        "set-cookie",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade"
    ]

    static func resolvedHeaders(_ storedHeaders: String, configurationID: UUID) -> String {
        transformLines(in: storedHeaders) { header in
            guard isSensitiveHeaderName(header.name),
                  header.value == keychainPlaceholder else {
                return header.original
            }

            let secret = KeychainService.readHeaderSecret(
                for: configurationID,
                headerName: header.name
            )
            guard !secret.isEmpty else { return header.original }
            return "\(header.name): \(secret)"
        }
    }

    static func encodedHeaders(_ headers: String) -> String {
        transformLines(in: headers) { header in
            guard isSensitiveHeaderName(header.name), !header.value.isEmpty else {
                return header.original
            }
            return "\(header.name): \(keychainPlaceholder)"
        }
    }

    static func persistSensitiveHeaders(_ headers: String, configurationID: UUID) -> Bool {
        var retainedHeaderNames = Set<String>()
        var didPersistAllSecrets = true
        for header in parsedHeaders(from: headers) where isSensitiveHeaderName(header.name) {
            let normalizedName = normalizedHeaderName(header.name)
            guard !header.value.isEmpty else { continue }
            retainedHeaderNames.insert(normalizedName)

            guard header.value != keychainPlaceholder else { continue }
            let didSave = KeychainService.saveHeaderSecret(
                header.value,
                for: configurationID,
                headerName: header.name
            )
            didPersistAllSecrets = didPersistAllSecrets && didSave
        }

        let didDeleteRemovedSecrets = KeychainService.deleteHeaderSecrets(
            for: configurationID,
            excluding: retainedHeaderNames
        )
        return didPersistAllSecrets && didDeleteRemovedSecrets
    }

    static func containsPersistableSensitiveHeader(_ headers: String) -> Bool {
        parsedHeaders(from: headers).contains { header in
            isSensitiveHeaderName(header.name)
                && !header.value.isEmpty
                && header.value != keychainPlaceholder
        }
    }

    private static func normalizedHeaderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func requestHeaders(from headers: String) -> [(name: String, value: String)] {
        parsedHeaders(from: headers).compactMap { header in
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isAllowedRequestHeaderName(name),
                  !value.isEmpty,
                  value != keychainPlaceholder,
                  !value.contains("\r"),
                  !value.contains("\n") else {
                return nil
            }
            return (name: name, value: value)
        }
    }

    static func sensitiveHeaderValues(from headers: String) -> [String] {
        parsedHeaders(from: headers).compactMap { header in
            let value = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSensitiveHeaderName(header.name),
                  !value.isEmpty,
                  value != keychainPlaceholder else {
                return nil
            }
            return value
        }
    }

    static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "authorization"
            || normalized == "proxy-authorization"
            || normalized == "cookie"
            || normalized.contains("api-key")
            || normalized.contains("apikey")
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.hasSuffix("-key")
    }

    private static func isAllowedRequestHeaderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !forbiddenRequestHeaderNames.contains(normalized),
              !normalized.isEmpty else {
            return false
        }

        let allowedScalars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~")
        return name.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }

    private static func transformLines(
        in headers: String,
        transform: (ParsedHeader) -> String
    ) -> String {
        headers
            .components(separatedBy: .newlines)
            .map { line in
                guard let header = ParsedHeader(line) else { return line }
                return transform(header)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func parsedHeaders(from headers: String) -> [ParsedHeader] {
        headers
            .components(separatedBy: .newlines)
            .compactMap(ParsedHeader.init)
    }

    private struct ParsedHeader {
        let original: String
        let name: String
        let value: String

        init?(_ line: String) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty,
                  let separatorIndex = trimmedLine.firstIndex(of: ":") else {
                return nil
            }

            let name = trimmedLine[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmedLine[trimmedLine.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            original = trimmedLine
            self.name = String(name)
            self.value = String(value)
        }
    }
}

struct AIModelConfiguration: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var alias: String
    var supportsReasoning: Bool
    var supportsImages: Bool
    var supportsTools: Bool
    var temperature: Double?
    var topP: Double?
    var contextWindowTokens: Int?
    var maxOutputTokens: Int?

    var hasAlias: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayName: String {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAlias.isEmpty ? name : trimmedAlias
    }

    init(
        name: String,
        alias: String = "",
        supportsReasoning: Bool = false,
        supportsImages: Bool = false,
        supportsTools: Bool? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        contextWindowTokens: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.name = name
        self.alias = alias
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
        self.supportsTools = supportsTools ?? Self.defaultToolsSupport(for: name)
        self.temperature = temperature
        self.topP = topP
        self.contextWindowTokens = contextWindowTokens
        self.maxOutputTokens = maxOutputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case alias
        case supportsReasoning
        case supportsImages
        case supportsTools
        case temperature
        case topP
        case contextWindowTokens
        case maxOutputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        alias = try container.decodeIfPresent(String.self, forKey: .alias) ?? ""
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages) ?? false
        supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools)
            ?? Self.defaultToolsSupport(for: name)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(alias, forKey: .alias)
        try container.encode(supportsReasoning, forKey: .supportsReasoning)
        try container.encode(supportsImages, forKey: .supportsImages)
        try container.encode(supportsTools, forKey: .supportsTools)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(contextWindowTokens, forKey: .contextWindowTokens)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
    }

    static func defaultToolsSupport(for modelName: String) -> Bool {
        modelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("deepseek-v4-")
    }
}

enum BuiltInAIProvider: String, CaseIterable, Identifiable {
    case openAIChatCompletions
    case openAIResponses
    case anthropicMessages
    case vertexAIExpress
    case zhipu
    case siliconFlow
    case openRouter
    case minimax
    case zAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIChatCompletions:
            return "OpenAI (Chat Completions)"
        case .openAIResponses:
            return "OpenAI (Responses)"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .vertexAIExpress:
            return "Google Vertex AI (Express Mode)"
        case .zhipu:
            return "智谱开放平台"
        case .siliconFlow:
            return "硅基流动"
        case .openRouter:
            return "OpenRouter"
        case .minimax:
            return "MiniMax"
        case .zAI:
            return "Z.AI"
        }
    }

    var menuSortKey: String {
        switch self {
        case .openAIChatCompletions:
            return "openai-chat-completions"
        case .openAIResponses:
            return "openai-responses"
        case .anthropicMessages:
            return "anthropic-messages"
        case .vertexAIExpress:
            return "google-vertex-ai-express"
        case .zhipu:
            return "zhipu-kaifang-pingtai"
        case .siliconFlow:
            return "guiji-liudong"
        case .openRouter:
            return "openrouter"
        case .minimax:
            return "minimax"
        case .zAI:
            return "z-ai"
        }
    }

    var isDefaultConfigurationTemplate: Bool {
        switch self {
        case .openAIChatCompletions, .openAIResponses, .anthropicMessages, .vertexAIExpress:
            return true
        case .zhipu, .siliconFlow, .openRouter, .minimax, .zAI:
            return false
        }
    }

    var baseURL: String {
        switch self {
        case .openAIChatCompletions:
            return "https://api.openai.com/v1"
        case .openAIResponses:
            return AIAPIFormat.openAIResponses.defaultBaseURL
        case .anthropicMessages:
            return AIAPIFormat.anthropicMessages.defaultBaseURL
        case .vertexAIExpress:
            return AIAPIFormat.vertexAIExpress.defaultBaseURL
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .siliconFlow:
            return "https://api.siliconflow.cn/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .minimax:
            return "https://api.minimaxi.com/v1"
        case .zAI:
            return "https://api.z.ai/api/paas/v4"
        }
    }

    var endpoint: String {
        apiFormat.defaultEndpoint
    }

    var apiFormat: AIAPIFormat {
        switch self {
        case .openAIChatCompletions:
            return .openAIChatCompletions
        case .openAIResponses:
            return .openAIResponses
        case .anthropicMessages:
            return .anthropicMessages
        case .vertexAIExpress:
            return .vertexAIExpress
        case .zhipu, .siliconFlow, .openRouter, .minimax, .zAI:
            return .openAIChatCompletions
        }
    }

    func makeConfiguration() -> AIConfiguration {
        AIConfiguration(
            name: displayName,
            baseURL: baseURL,
            endpoint: endpoint,
            apiFormat: apiFormat,
            models: [],
            selectedModel: ""
        )
    }
}

struct AIConfiguration: Identifiable, Codable, Equatable {
    static let defaultSystemPrompt = "你是一个友好且有帮助的AI助手。"
    static let defaultAnthropicMaxTokens = 4096

    var id: UUID
    var name: String
    var baseURL: String
    var endpoint: String
    var apiFormat: AIAPIFormat
    var anthropicMaxTokens: Int
    var anthropicClaudeCodeImpersonationEnabled: Bool
    var apiKey: String
    var customHeaders: String
    var systemPrompt: String
    var promptPresets: [AIPromptPreset]
    var selectedPromptPresetID: UUID
    var models: [AIModelConfiguration]
    var selectedModel: String
    var reasoningEnabled: Bool
    var reasoningEffort: ReasoningEffort
    var generatesImageContextDescriptions: Bool
    var updatedAt: Date

    var requestURLString: String {
        Self.join(baseURL: baseURL, endpoint: endpoint)
    }

    var selectedModelConfiguration: AIModelConfiguration? {
        models.first { $0.name == selectedModel }
    }

    var selectedModelDisplayName: String {
        if let selectedModelConfiguration {
            return selectedModelConfiguration.displayName
        }

        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? "未选择模型" : trimmedModel
    }

    var selectedModelSupportsReasoning: Bool {
        selectedModelConfiguration?.supportsReasoning == true
    }

    var selectedModelSupportsImages: Bool {
        selectedModelConfiguration?.supportsImages == true
    }

    var selectedModelSupportsTools: Bool {
        selectedModelConfiguration?.supportsTools == true
    }

    var selectedPromptPreset: AIPromptPreset? {
        promptPresets.first { $0.id == selectedPromptPresetID } ?? promptPresets.first
    }

    init(
        id: UUID = UUID(),
        name: String = "默认配置",
        baseURL: String = "https://api.deepseek.com",
        endpoint: String = "chat/completions",
        apiFormat: AIAPIFormat = .openAIChatCompletions,
        anthropicMaxTokens: Int = AIConfiguration.defaultAnthropicMaxTokens,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        apiKey: String = "",
        customHeaders: String = "",
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        promptPresets: [AIPromptPreset]? = nil,
        selectedPromptPresetID: UUID? = nil,
        models: [AIModelConfiguration] = [AIModelConfiguration(name: "deepseek-v4-pro", supportsTools: true)],
        selectedModel: String = "deepseek-v4-pro",
        reasoningEnabled: Bool = true,
        reasoningEffort: ReasoningEffort = .medium,
        generatesImageContextDescriptions: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.endpoint = endpoint
        self.apiFormat = apiFormat
        self.anthropicMaxTokens = max(1, anthropicMaxTokens)
        self.anthropicClaudeCodeImpersonationEnabled = anthropicClaudeCodeImpersonationEnabled
        self.apiKey = apiKey
        if !apiKey.isEmpty {
            KeychainService.saveAPIKey(apiKey, for: id)
        }
        self.customHeaders = customHeaders
        let promptSelection = Self.normalizedPromptSelection(
            promptPresets: promptPresets,
            selectedPromptPresetID: selectedPromptPresetID,
            fallbackSystemPrompt: systemPrompt
        )
        self.systemPrompt = promptSelection.systemPrompt
        self.promptPresets = promptSelection.presets
        self.selectedPromptPresetID = promptSelection.selectedID
        self.models = models
        self.selectedModel = selectedModel
        self.reasoningEnabled = reasoningEnabled
        self.reasoningEffort = reasoningEffort
        self.generatesImageContextDescriptions = generatesImageContextDescriptions
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case endpoint
        case apiFormat
        case anthropicMaxTokens
        case anthropicClaudeCodeImpersonationEnabled
        case customHeaders
        case systemPrompt
        case promptPresets
        case selectedPromptPresetID
        case models
        case selectedModel
        case reasoningEnabled
        case reasoningEffort
        case generatesImageContextDescriptions
        case updatedAt
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "默认配置"
        customHeaders = try container.decodeIfPresent(String.self, forKey: .customHeaders) ?? ""
        let decodedSystemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.defaultSystemPrompt
        let decodedPromptPresets = try container.decodeIfPresent([AIPromptPreset].self, forKey: .promptPresets)
        let decodedSelectedPromptID = try container.decodeIfPresent(UUID.self, forKey: .selectedPromptPresetID)
        let promptSelection = Self.normalizedPromptSelection(
            promptPresets: decodedPromptPresets,
            selectedPromptPresetID: decodedSelectedPromptID,
            fallbackSystemPrompt: decodedSystemPrompt
        )
        systemPrompt = promptSelection.systemPrompt
        promptPresets = promptSelection.presets
        selectedPromptPresetID = promptSelection.selectedID
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        apiFormat = try container.decodeIfPresent(AIAPIFormat.self, forKey: .apiFormat) ?? .openAIChatCompletions
        let decodedAnthropicMaxTokens = try container.decodeIfPresent(Int.self, forKey: .anthropicMaxTokens)
            ?? Self.defaultAnthropicMaxTokens
        anthropicMaxTokens = max(1, decodedAnthropicMaxTokens)
        anthropicClaudeCodeImpersonationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .anthropicClaudeCodeImpersonationEnabled
        ) ?? false
        reasoningEnabled = try container.decodeIfPresent(Bool.self, forKey: .reasoningEnabled) ?? true
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        generatesImageContextDescriptions = try container.decodeIfPresent(
            Bool.self,
            forKey: .generatesImageContextDescriptions
        ) ?? true

        if container.contains(.models),
           let decodedModels = try? container.decode([AIModelConfiguration].self, forKey: .models) {
            models = decodedModels
        } else if container.contains(.models),
                  let legacyModels = try? container.decode([String].self, forKey: .models) {
            models = legacyModels.map { AIModelConfiguration(name: $0) }
        } else {
            models = [AIModelConfiguration(name: "deepseek-v4-pro", supportsTools: true)]
        }

        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? models.first?.name ?? ""
        var containsSelectedModel = false
        for model in models where model.name == selectedModel {
            containsSelectedModel = true
        }
        if !containsSelectedModel, !selectedModel.isEmpty {
            models.insert(AIModelConfiguration(name: selectedModel), at: 0)
        }

        apiKey = KeychainService.readAPIKey(for: id)
        if apiKey.isEmpty,
           let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           let legacyAPIKey = try? legacyContainer.decodeIfPresent(String.self, forKey: .apiKey),
           !legacyAPIKey.isEmpty {
            apiKey = legacyAPIKey
            KeychainService.saveAPIKey(legacyAPIKey, for: id)
        }
        customHeaders = CustomHeaderSecurity.resolvedHeaders(customHeaders, configurationID: id)

        let decodedBaseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com"
        if let decodedEndpoint = try container.decodeIfPresent(String.self, forKey: .endpoint),
           !decodedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = decodedBaseURL
            endpoint = decodedEndpoint
        } else {
            let split = Self.splitBaseURLAndEndpoint(decodedBaseURL)
            baseURL = split.baseURL
            endpoint = split.endpoint
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(apiFormat, forKey: .apiFormat)
        try container.encode(anthropicMaxTokens, forKey: .anthropicMaxTokens)
        try container.encode(
            anthropicClaudeCodeImpersonationEnabled,
            forKey: .anthropicClaudeCodeImpersonationEnabled
        )
        try container.encode(
            CustomHeaderSecurity.encodedHeaders(customHeaders),
            forKey: .customHeaders
        )
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(promptPresets, forKey: .promptPresets)
        try container.encode(selectedPromptPresetID, forKey: .selectedPromptPresetID)
        try container.encode(models, forKey: .models)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(reasoningEnabled, forKey: .reasoningEnabled)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(generatesImageContextDescriptions, forKey: .generatesImageContextDescriptions)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    func persistSecureFields() -> Bool {
        let didPersistAPIKey = KeychainService.saveAPIKey(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            for: id
        )
        let didPersistHeaders = CustomHeaderSecurity.persistSensitiveHeaders(
            customHeaders,
            configurationID: id
        )
        return didPersistAPIKey && didPersistHeaders
    }

    static func join(baseURL: String, endpoint: String) -> String {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return trimmedBaseURL }

        return trimmedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + trimmedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func splitBaseURLAndEndpoint(_ urlString: String) -> (baseURL: String, endpoint: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownEndpoints = [
            "chat/completions",
            "responses",
            "v1/messages",
            "v1/publishers/google/models/{model}:generateContent"
        ]

        for endpoint in knownEndpoints {
            let suffix = "/" + endpoint
            if trimmedURL.hasSuffix(suffix) {
                return (String(trimmedURL.dropLast(suffix.count)), endpoint)
            }
        }
        return (trimmedURL.isEmpty ? "https://api.deepseek.com" : trimmedURL, "chat/completions")
    }
}

enum AIConfigurationStore {
    private static let configurationsKey = "aiConfigurations"
    private static let promptPresetsKey = "aiPromptPresets"
    private static let selectedConfigurationIDKey = "selectedAIConfigurationID"
    static let hapticFeedbackEnabledKey = "hapticFeedbackEnabled"
    static let defaultHapticFeedbackEnabled = true
    private static let fallbackConfigurationName = "未命名配置"

    static func loadConfigurations() -> [AIConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: configurationsKey),
              let configurations = try? JSONDecoder().decode([AIConfiguration].self, from: data),
              !configurations.isEmpty else {
            let configurations = [migratedDefaultConfiguration()]
            if saveConfigurations(configurations) {
                removeLegacySecretDefaults()
            }
            return configurations
        }

        if needsSecureStorageMigration(data),
           saveConfigurations(configurations) {
            removeLegacySecretDefaults()
        }
        return configurations
    }

    static func loadPromptPresets(configurations sourceConfigurations: [AIConfiguration]? = nil) -> [AIPromptPreset] {
        if let data = UserDefaults.standard.data(forKey: promptPresetsKey),
           let promptPresets = try? JSONDecoder().decode([AIPromptPreset].self, from: data),
           !promptPresets.isEmpty {
            let normalizedPresets = normalizedPromptPresets(promptPresets)
            if normalizedPresets != promptPresets {
                _ = savePromptPresets(normalizedPresets)
            }
            return normalizedPresets
        }

        let configurations = sourceConfigurations ?? loadConfigurations()
        let migratedPromptPresets = normalizedPromptPresets(configurations.flatMap { $0.promptPresets })
        _ = savePromptPresets(migratedPromptPresets)
        return migratedPromptPresets
    }

    @discardableResult
    static func savePromptPresets(_ promptPresets: [AIPromptPreset]) -> Bool {
        guard let data = try? JSONEncoder().encode(normalizedPromptPresets(promptPresets)) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: promptPresetsKey)
        return true
    }

    static func builtInDefaultPromptPreset(in promptPresets: inout [AIPromptPreset]) -> AIPromptPreset {
        promptPresets = normalizedPromptPresets(promptPresets)
        return promptPresets[0]
    }

    @discardableResult
    static func saveConfigurations(_ configurations: [AIConfiguration]) -> Bool {
        guard configurations.allSatisfy({ $0.persistSecureFields() }) else { return false }
        guard let data = try? JSONEncoder().encode(configurations) else { return false }
        UserDefaults.standard.set(data, forKey: configurationsKey)
        return true
    }

    static func loadSelectedConfigurationID() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: selectedConfigurationIDKey) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    static func saveSelectedConfigurationID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: selectedConfigurationIDKey)
    }

    static func selectedConfiguration(
        from configurations: [AIConfiguration],
        selectedID: UUID?
    ) -> AIConfiguration {
        if let selectedID,
           let configuration = configurations.first(where: { $0.id == selectedID }) {
            return configuration
        }

        return configurations.first ?? migratedDefaultConfiguration()
    }

    static func uniqueConfigurationName(
        _ name: String,
        among configurations: [AIConfiguration],
        excluding excludedID: UUID? = nil
    ) -> String {
        let baseName = normalizedConfigurationName(name)
        let existingNames = Set(
            configurations
                .filter { configuration in
                    guard let excludedID else { return true }
                    return configuration.id != excludedID
                }
                .map { normalizedConfigurationName($0.name) }
        )

        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        var candidate = "\(baseName)-\(suffix)"
        while existingNames.contains(candidate) {
            suffix += 1
            candidate = "\(baseName)-\(suffix)"
        }
        return candidate
    }

    private static func normalizedConfigurationName(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallbackConfigurationName : trimmedName
    }

    private static func normalizedPromptPresets(_ promptPresets: [AIPromptPreset]) -> [AIPromptPreset] {
        var normalizedPromptPresets: [AIPromptPreset] = []
        var seenIDs = Set<UUID>()
        var seenSignatures = Set<String>()

        func appendIfNeeded(_ promptPreset: AIPromptPreset) {
            guard !seenIDs.contains(promptPreset.id) else { return }
            let signature = "\(promptPreset.name)\u{0}\(promptPreset.content)"
            guard !seenSignatures.contains(signature) else { return }

            normalizedPromptPresets.append(promptPreset)
            seenIDs.insert(promptPreset.id)
            seenSignatures.insert(signature)
        }

        if let defaultPromptPreset = promptPresets.first(where: { $0.content == AIConfiguration.defaultSystemPrompt }) {
            var normalizedDefaultPreset = defaultPromptPreset
            if normalizedDefaultPreset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalizedDefaultPreset.name = "默认提示词"
            }
            appendIfNeeded(normalizedDefaultPreset)
        } else {
            appendIfNeeded(AIPromptPreset(name: "默认提示词", content: AIConfiguration.defaultSystemPrompt))
        }

        for promptPreset in promptPresets where promptPreset.content != AIConfiguration.defaultSystemPrompt {
            appendIfNeeded(promptPreset)
        }

        return normalizedPromptPresets
    }

    private static func migratedDefaultConfiguration() -> AIConfiguration {
        let defaults = UserDefaults.standard
        let legacyBaseURL = defaults.string(forKey: "baseURL") ?? "https://api.deepseek.com/chat/completions"
        let split = AIConfiguration.splitBaseURLAndEndpoint(legacyBaseURL)
        let apiKey = defaults.string(forKey: "apiKey") ?? ""
        let customHeaders = defaults.string(forKey: "customHeaders") ?? ""

        return AIConfiguration(
            name: "默认配置",
            baseURL: split.baseURL,
            endpoint: split.endpoint,
            apiKey: apiKey,
            customHeaders: customHeaders,
            models: [AIModelConfiguration(name: "deepseek-v4-pro", supportsTools: true)],
            selectedModel: "deepseek-v4-pro"
        )
    }

    private static func removeLegacySecretDefaults() {
        UserDefaults.standard.removeObject(forKey: "apiKey")
        UserDefaults.standard.removeObject(forKey: "customHeaders")
    }

    private static func needsSecureStorageMigration(_ data: Data) -> Bool {
        guard let storedConfigurations = try? JSONDecoder().decode([StoredConfigurationSecrets].self, from: data) else {
            return false
        }

        return storedConfigurations.contains { configuration in
            let hasLegacyAPIKey = configuration.apiKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            return hasLegacyAPIKey
                || CustomHeaderSecurity.containsPersistableSensitiveHeader(configuration.customHeaders ?? "")
        }
    }

    private struct StoredConfigurationSecrets: Decodable {
        let apiKey: String?
        let customHeaders: String?
    }
}
