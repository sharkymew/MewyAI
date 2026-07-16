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
            return AppLocalizations.string("reasoning.effort.low", defaultValue: "Low")
        case .medium:
            return AppLocalizations.string("reasoning.effort.medium", defaultValue: "Medium")
        case .high:
            return AppLocalizations.string("reasoning.effort.high", defaultValue: "High")
        case .max:
            return AppLocalizations.string("reasoning.effort.max", defaultValue: "Max")
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
            return AppLocalizations.string(
                "apiFormat.openAIChatCompletions.requestFooter",
                defaultValue: "Chat Completions combines Endpoint with Base URL to form the final request URL. The default endpoint is chat/completions."
            )
        case .openAIResponses:
            return AppLocalizations.string(
                "apiFormat.openAIResponses.requestFooter",
                defaultValue: "Responses API uses responses as the default endpoint. Model parameters are sent using Responses field names."
            )
        case .anthropicMessages:
            return AppLocalizations.string(
                "apiFormat.anthropicMessages.requestFooter",
                defaultValue: "Anthropic Messages uses v1/messages as the default endpoint, sends the API Key as x-api-key, and automatically adds anthropic-version. Max Tokens only applies to the current configuration."
            )
        case .vertexAIExpress:
            return AppLocalizations.string(
                "apiFormat.vertexAIExpress.requestFooter",
                defaultValue: "Vertex Express uses a {model} placeholder in the default endpoint and replaces it with the current model ID before sending."
            )
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

    static func containsSensitiveHeader(_ headers: String) -> Bool {
        parsedHeaders(from: headers).contains { header in
            isSensitiveHeaderName(header.name) && !header.value.isEmpty
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
    private static let defaultDeepSeekV4ProName = "deepseek-v4-pro"
    private static let defaultDeepSeekV4ProAlias = "V4 Pro"

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
    var inputPricePerMillionTokens: Double?
    var outputPricePerMillionTokens: Double?
    var priceCurrencyCode: String?

    var hasAlias: Bool {
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayName: String {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAlias.isEmpty ? name : trimmedAlias
    }

    nonisolated var hasPricing: Bool {
        inputPricePerMillionTokens != nil || outputPricePerMillionTokens != nil
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
        maxOutputTokens: Int? = nil,
        inputPricePerMillionTokens: Double? = nil,
        outputPricePerMillionTokens: Double? = nil,
        priceCurrencyCode: String? = nil
    ) {
        self.name = name
        self.alias = Self.normalizedAlias(alias, for: name)
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
        self.supportsTools = supportsTools ?? Self.defaultToolsSupport(for: name)
        self.temperature = temperature
        self.topP = topP
        self.contextWindowTokens = contextWindowTokens
        self.maxOutputTokens = maxOutputTokens
        self.inputPricePerMillionTokens = inputPricePerMillionTokens
        self.outputPricePerMillionTokens = outputPricePerMillionTokens
        self.priceCurrencyCode = priceCurrencyCode
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
        case inputPricePerMillionTokens
        case outputPricePerMillionTokens
        case priceCurrencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        alias = Self.normalizedAlias(try container.decodeIfPresent(String.self, forKey: .alias) ?? "", for: name)
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages) ?? false
        supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools)
            ?? Self.defaultToolsSupport(for: name)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        inputPricePerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .inputPricePerMillionTokens)
        outputPricePerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .outputPricePerMillionTokens)
        priceCurrencyCode = try container.decodeIfPresent(String.self, forKey: .priceCurrencyCode)
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
        try container.encodeIfPresent(inputPricePerMillionTokens, forKey: .inputPricePerMillionTokens)
        try container.encodeIfPresent(outputPricePerMillionTokens, forKey: .outputPricePerMillionTokens)
        try container.encodeIfPresent(priceCurrencyCode, forKey: .priceCurrencyCode)
    }

    static func defaultToolsSupport(for modelName: String) -> Bool {
        modelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("deepseek-v4-")
    }

    private static func normalizedAlias(_ alias: String, for modelName: String) -> String {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAlias.isEmpty else { return alias }

        let normalizedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModelName == defaultDeepSeekV4ProName ? defaultDeepSeekV4ProAlias : ""
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
            return AppLocalizations.string("provider.zhipu.displayName", defaultValue: "Zhipu Open Platform")
        case .siliconFlow:
            return AppLocalizations.string("provider.siliconFlow.displayName", defaultValue: "SiliconFlow")
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

    var defaultEmbeddingConfiguration: AIEmbeddingConfiguration? {
        switch self {
        case .anthropicMessages:
            return nil
        case .vertexAIExpress:
            return AIEmbeddingConfiguration(
                apiFormat: .vertexPredict,
                baseURL: baseURL
            )
        case .openAIChatCompletions, .openAIResponses, .zhipu, .siliconFlow, .openRouter, .minimax, .zAI:
            return AIEmbeddingConfiguration(
                apiFormat: .openAICompatible,
                baseURL: baseURL
            )
        }
    }

    func makeConfiguration() -> AIConfiguration {
        AIConfiguration(
            name: displayName,
            baseURL: baseURL,
            endpoint: endpoint,
            apiFormat: apiFormat,
            models: [],
            selectedModel: "",
            embeddingConfiguration: defaultEmbeddingConfiguration
        )
    }
}

struct AIConfiguration: Identifiable, Codable, Equatable {
    static var defaultSystemPrompt: String {
        AppLocalizations.string(
            "prompt.defaultSystem",
            defaultValue: "You are a friendly and helpful AI assistant."
        )
    }

    static let defaultAnthropicMaxTokens = 4096
    static let currentCredentialSchemaVersion = 1

    var id: UUID
    var name: String
    var baseURL: String
    var endpoint: String
    var apiFormat: AIAPIFormat
    var anthropicMaxTokens: Int
    var credentialSchemaVersion: Int
    var apiKeys: [AIProviderAPIKey]
    var customHeaders: String
    var systemPrompt: String
    var promptPresets: [AIPromptPreset]
    var selectedPromptPresetID: UUID
    var models: [AIModelConfiguration]
    var selectedModel: String
    var reasoningEnabled: Bool
    var reasoningEffort: ReasoningEffort
    var generatesImageContextDescriptions: Bool
    var embeddingConfiguration: AIEmbeddingConfiguration?
    var updatedAt: Date

    nonisolated var apiKey: String {
        get {
            guard let currentAPIKeyID else { return "" }
            return apiKeys.first(where: { $0.id == currentAPIKeyID })?.value ?? ""
        }
        set {
            let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentAPIKeyID,
               let index = apiKeys.firstIndex(where: { $0.id == currentAPIKeyID }) {
                if trimmedValue.isEmpty {
                    apiKeys.remove(at: index)
                } else {
                    apiKeys[index].value = trimmedValue
                }
                return
            }

            guard !trimmedValue.isEmpty else { return }
            let keyID = apiKeys.isEmpty ? id : UUID()
            let key = AIProviderAPIKey(
                id: keyID,
                name: Self.defaultAPIKeyName(index: apiKeys.count + 1),
                value: trimmedValue
            )
            apiKeys.append(key)
        }
    }

    nonisolated var currentAPIKeyID: UUID? {
        AIProviderKeyStateStore.shared.currentKeyID(
            for: id,
            availableKeyIDs: apiKeys.map(\.id)
        )
    }

    var currentAPIKeyName: String? {
        guard let currentAPIKeyID else { return nil }
        return apiKeys.first(where: { $0.id == currentAPIKeyID })?.name
    }

    var apiKeyCount: Int {
        apiKeys.count
    }

    func credentialSet(
        stateStore: AIProviderKeyStateStore = .shared
    ) -> AIProviderCredentialSet {
        let availableKeyIDs = apiKeys.map(\.id)
        let currentKeyID = stateStore.currentKeyID(for: id, availableKeyIDs: availableKeyIDs)
        return AIProviderCredentialSet(
            configurationID: id,
            currentKeyID: currentKeyID,
            apiKeys: apiKeys
        )
    }

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
        return trimmedModel.isEmpty
            ? AppLocalizations.string("configuration.noSelectedModel", defaultValue: "No model selected")
            : trimmedModel
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
        name: String = AppLocalizations.string("configuration.defaultName", defaultValue: "Default Configuration"),
        baseURL: String = "https://api.deepseek.com",
        endpoint: String = "chat/completions",
        apiFormat: AIAPIFormat = .openAIChatCompletions,
        anthropicMaxTokens: Int = AIConfiguration.defaultAnthropicMaxTokens,
        apiKey: String = "",
        apiKeys: [AIProviderAPIKey]? = nil,
        customHeaders: String = "",
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        promptPresets: [AIPromptPreset]? = nil,
        selectedPromptPresetID: UUID? = nil,
        models: [AIModelConfiguration] = [AIModelConfiguration(name: "deepseek-v4-pro", supportsTools: true)],
        selectedModel: String = "deepseek-v4-pro",
        reasoningEnabled: Bool = true,
        reasoningEffort: ReasoningEffort = .medium,
        generatesImageContextDescriptions: Bool = true,
        embeddingConfiguration: AIEmbeddingConfiguration? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.endpoint = endpoint
        self.apiFormat = apiFormat
        self.anthropicMaxTokens = max(1, anthropicMaxTokens)
        self.credentialSchemaVersion = Self.currentCredentialSchemaVersion
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKeys = apiKeys ?? (trimmedAPIKey.isEmpty
            ? []
            : [AIProviderAPIKey(
                id: id,
                name: Self.defaultAPIKeyName(index: 1),
                value: trimmedAPIKey
            )])
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
        self.embeddingConfiguration = embeddingConfiguration
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case endpoint
        case apiFormat
        case anthropicMaxTokens
        case credentialSchemaVersion
        case apiKeys
        case customHeaders
        case systemPrompt
        case promptPresets
        case selectedPromptPresetID
        case models
        case selectedModel
        case reasoningEnabled
        case reasoningEffort
        case generatesImageContextDescriptions
        case embeddingConfiguration
        case updatedAt
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? AppLocalizations.string("configuration.defaultName", defaultValue: "Default Configuration")
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
        reasoningEnabled = try container.decodeIfPresent(Bool.self, forKey: .reasoningEnabled) ?? true
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        generatesImageContextDescriptions = try container.decodeIfPresent(
            Bool.self,
            forKey: .generatesImageContextDescriptions
        ) ?? true
        embeddingConfiguration = try container.decodeIfPresent(
            AIEmbeddingConfiguration.self,
            forKey: .embeddingConfiguration
        )

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

        let secretStorage = decoder.userInfo[.aiProviderKeySecretStorage] as? any AIProviderKeySecretStoring
            ?? KeychainAIProviderKeySecretStorage()
        let storedCredentialSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .credentialSchemaVersion
        ) ?? 0
        let decodedAPIKeys = try container.decodeIfPresent([AIProviderAPIKey].self, forKey: .apiKeys)
        let usesKeyedCredentialSchema = storedCredentialSchemaVersion >= Self.currentCredentialSchemaVersion
            && decodedAPIKeys != nil
        credentialSchemaVersion = Self.currentCredentialSchemaVersion

        if usesKeyedCredentialSchema, let decodedAPIKeys {
            apiKeys = decodedAPIKeys.map { key in
                var key = key
                key.value = secretStorage.readAPIKey(for: key.id).value
                return key
            }
        } else {
            let legacyAPIKey = (try? decoder.container(keyedBy: LegacyCodingKeys.self))
                .flatMap { try? $0.decodeIfPresent(String.self, forKey: .apiKey) }
                ?? ""
            let legacyReadResult = secretStorage.readAPIKey(for: id)
            let resolvedLegacyKey = legacyReadResult.value.isEmpty
                ? legacyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                : legacyReadResult.value

            apiKeys = resolvedLegacyKey.isEmpty
                ? []
                : [AIProviderAPIKey(
                    id: id,
                    name: Self.defaultAPIKeyName(index: 1),
                    value: resolvedLegacyKey
                )]
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
        try container.encode(credentialSchemaVersion, forKey: .credentialSchemaVersion)
        try container.encode(apiKeys, forKey: .apiKeys)
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
        try container.encodeIfPresent(embeddingConfiguration, forKey: .embeddingConfiguration)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    func persistSecureFields(
        secretStorage: any AIProviderKeySecretStoring = KeychainAIProviderKeySecretStorage(),
        persistsSensitiveHeaders: Bool = true
    ) -> Bool {
        let didPersistAPIKeys = apiKeys.allSatisfy { key in
            let value = key.trimmedValue
            return value.isEmpty || secretStorage.saveAPIKey(value, for: key.id)
        }
        let didPersistHeaders = !persistsSensitiveHeaders || CustomHeaderSecurity.persistSensitiveHeaders(
            customHeaders,
            configurationID: id
        )
        return didPersistAPIKeys && didPersistHeaders
    }

    mutating func addAPIKey(
        name: String,
        value: String
    ) throws {
        let normalizedName = try validatedAPIKeyName(name)
        let normalizedValue = try validatedAPIKeyValue(value)
        let key = AIProviderAPIKey(
            name: normalizedName,
            value: normalizedValue
        )
        apiKeys.append(key)
    }

    mutating func updateAPIKey(
        id keyID: UUID,
        name: String,
        value: String
    ) throws {
        guard let index = apiKeys.firstIndex(where: { $0.id == keyID }) else {
            throw AIProviderAPIKeyValidationError.keyNotFound
        }
        let normalizedName = try validatedAPIKeyName(name, excluding: keyID)
        let normalizedValue = try validatedAPIKeyValue(value)
        apiKeys[index].name = normalizedName
        apiKeys[index].value = normalizedValue
    }

    @discardableResult
    nonisolated mutating func removeAPIKey(id keyID: UUID) -> AIProviderAPIKey? {
        guard let index = apiKeys.firstIndex(where: { $0.id == keyID }) else { return nil }
        return apiKeys.remove(at: index)
    }

    nonisolated func followingAPIKeyID(afterRemoving keyID: UUID) -> UUID? {
        guard let index = apiKeys.firstIndex(where: { $0.id == keyID }),
              apiKeys.count > 1 else {
            return nil
        }
        return apiKeys.indices.contains(index + 1)
            ? apiKeys[index + 1].id
            : apiKeys.first?.id
    }

    private func validatedAPIKeyName(
        _ name: String,
        excluding excludedKeyID: UUID? = nil
    ) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw AIProviderAPIKeyValidationError.emptyName
        }
        let containsDuplicate = apiKeys.contains { key in
            guard key.id != excludedKeyID else { return false }
            return key.name.compare(
                normalizedName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
        guard !containsDuplicate else {
            throw AIProviderAPIKeyValidationError.duplicateName
        }
        return normalizedName
    }

    private func validatedAPIKeyValue(_ value: String) throws -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            throw AIProviderAPIKeyValidationError.emptySecret
        }
        return normalizedValue
    }

    nonisolated static func defaultAPIKeyName(index: Int) -> String {
        AppLocalizations.format(
            "providerKey.defaultName",
            defaultValue: "Key %d",
            arguments: [max(1, index)]
        )
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
    static let saveCapturedPhotosToLibraryKey = "saveCapturedPhotosToPhotoLibrary"
    static let defaultSaveCapturedPhotosToLibrary = false
    private static var fallbackConfigurationName: String {
        AppLocalizations.string("configuration.unnamed", defaultValue: "Unnamed Configuration")
    }

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
        for configuration in configurations {
            AIProviderKeyStateStore.shared.reconcile(
                configurationID: configuration.id,
                availableKeyIDs: configuration.apiKeys.map(\.id)
            )
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
    static func saveConfigurations(
        _ configurations: [AIConfiguration],
        secretStorage: any AIProviderKeySecretStoring = KeychainAIProviderKeySecretStorage(),
        defaults: UserDefaults = .standard,
        stateStore: AIProviderKeyStateStore = .shared
    ) -> Bool {
        let previousCredentials = storedConfigurationCredentials(defaults: defaults)
        guard let data = try? JSONEncoder().encode(configurations),
              let secureFieldsSnapshot = SecureFieldsSnapshot.capture(
                  previousCredentials: previousCredentials,
                  configurations: configurations,
                  secretStorage: secretStorage
              ) else {
            return false
        }
        let headerConfigurationIDs = configurationIDsWithSensitiveHeaders(
            previousCredentials: previousCredentials,
            configurations: configurations
        )

        guard configurations.allSatisfy({
            $0.persistSecureFields(
                secretStorage: secretStorage,
                persistsSensitiveHeaders: headerConfigurationIDs.contains($0.id)
            )
        }),
              deleteRemovedCredentials(
                  previousCredentials: previousCredentials,
                  configurations: configurations,
                  secretStorage: secretStorage
              ) else {
            _ = secureFieldsSnapshot.restore(secretStorage: secretStorage)
            return false
        }

        defaults.set(data, forKey: configurationsKey)
        finalizeCredentialState(
            previousCredentials: previousCredentials,
            configurations: configurations,
            stateStore: stateStore
        )
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
                normalizedDefaultPreset.name = AppLocalizations.string("promptPreset.defaultName", defaultValue: "Default Prompt")
            }
            appendIfNeeded(normalizedDefaultPreset)
        } else {
            appendIfNeeded(AIPromptPreset(
                name: AppLocalizations.string("promptPreset.defaultName", defaultValue: "Default Prompt"),
                content: AIConfiguration.defaultSystemPrompt
            ))
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
            name: AppLocalizations.string("configuration.defaultName", defaultValue: "Default Configuration"),
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
            let needsCredentialMigration = (configuration.credentialSchemaVersion ?? 0)
                < AIConfiguration.currentCredentialSchemaVersion
            return needsCredentialMigration
                || hasLegacyAPIKey
                || CustomHeaderSecurity.containsPersistableSensitiveHeader(configuration.customHeaders ?? "")
        }
    }

    private static func storedConfigurationCredentials(
        defaults: UserDefaults = .standard
    ) -> [StoredConfigurationCredentials] {
        guard let data = defaults.data(forKey: configurationsKey),
              let credentials = try? JSONDecoder().decode([StoredConfigurationCredentials].self, from: data) else {
            return []
        }
        return credentials
    }

    private static func deleteRemovedCredentials(
        previousCredentials: [StoredConfigurationCredentials],
        configurations: [AIConfiguration],
        secretStorage: any AIProviderKeySecretStoring
    ) -> Bool {
        let currentConfigurationsByID = Dictionary(
            configurations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var didDeleteAll = true

        for previous in previousCredentials {
            guard let configurationID = previous.id else { continue }
            guard let currentConfiguration = currentConfigurationsByID[configurationID] else {
                for keyID in previous.keyIDs {
                    if !secretStorage.deleteAPIKey(for: keyID) {
                        didDeleteAll = false
                    }
                }
                if previous.hasSensitiveHeaders,
                   !KeychainService.deleteHeaderSecrets(for: configurationID) {
                    didDeleteAll = false
                }
                continue
            }

            let currentKeyIDs = Set(currentConfiguration.apiKeys.map(\.id))
            let removedKeyIDs = previous.keyIDs.subtracting(currentKeyIDs)
            for keyID in removedKeyIDs {
                if !secretStorage.deleteAPIKey(for: keyID) {
                    didDeleteAll = false
                }
            }
        }

        return didDeleteAll
    }

    private static func configurationIDsWithSensitiveHeaders(
        previousCredentials: [StoredConfigurationCredentials],
        configurations: [AIConfiguration]
    ) -> Set<UUID> {
        var configurationIDs = Set(
            configurations
                .filter { CustomHeaderSecurity.containsSensitiveHeader($0.customHeaders) }
                .map(\.id)
        )
        for credentials in previousCredentials where credentials.hasSensitiveHeaders {
            if let configurationID = credentials.id {
                configurationIDs.insert(configurationID)
            }
        }
        return configurationIDs
    }

    private static func finalizeCredentialState(
        previousCredentials: [StoredConfigurationCredentials],
        configurations: [AIConfiguration],
        stateStore: AIProviderKeyStateStore
    ) {
        let currentConfigurationsByID = Dictionary(
            configurations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for previous in previousCredentials {
            guard let configurationID = previous.id else { continue }
            guard let currentConfiguration = currentConfigurationsByID[configurationID] else {
                stateStore.removeState(for: configurationID)
                continue
            }

            let currentKeyIDs = Set(currentConfiguration.apiKeys.map(\.id))
            stateStore.removeKeys(previous.keyIDs.subtracting(currentKeyIDs), for: configurationID)
        }

        for configuration in configurations {
            stateStore.reconcile(
                configurationID: configuration.id,
                availableKeyIDs: configuration.apiKeys.map(\.id)
            )
        }
    }

    private struct SecureFieldsSnapshot {
        let apiKeyResults: [UUID: AIProviderKeySecretReadResult]
        let headerSecrets: [UUID: [String: String]]

        static func capture(
            previousCredentials: [StoredConfigurationCredentials],
            configurations: [AIConfiguration],
            secretStorage: any AIProviderKeySecretStoring
        ) -> SecureFieldsSnapshot? {
            var keyIDs = Set(configurations.flatMap { $0.apiKeys.map(\.id) })
            for credentials in previousCredentials {
                keyIDs.formUnion(credentials.keyIDs)
            }

            var apiKeyResults = [UUID: AIProviderKeySecretReadResult]()
            for keyID in keyIDs {
                let result = secretStorage.readAPIKey(for: keyID)
                guard result != .failure else { return nil }
                apiKeyResults[keyID] = result
            }

            let configurationIDs = AIConfigurationStore.configurationIDsWithSensitiveHeaders(
                previousCredentials: previousCredentials,
                configurations: configurations
            )
            var headerSecrets = [UUID: [String: String]]()
            for configurationID in configurationIDs {
                guard let values = KeychainService.headerSecretValues(for: configurationID) else {
                    return nil
                }
                headerSecrets[configurationID] = values
            }

            return SecureFieldsSnapshot(
                apiKeyResults: apiKeyResults,
                headerSecrets: headerSecrets
            )
        }

        @discardableResult
        func restore(secretStorage: any AIProviderKeySecretStoring) -> Bool {
            var didRestoreAll = true
            for (keyID, result) in apiKeyResults {
                let didRestore: Bool
                switch result {
                case .value(let value):
                    didRestore = secretStorage.saveAPIKey(value, for: keyID)
                case .missing:
                    didRestore = secretStorage.deleteAPIKey(for: keyID)
                case .failure:
                    didRestore = false
                }
                if !didRestore {
                    didRestoreAll = false
                }
            }

            for (configurationID, secrets) in headerSecrets {
                if !KeychainService.restoreHeaderSecrets(secrets, for: configurationID) {
                    didRestoreAll = false
                }
            }
            return didRestoreAll
        }
    }

    private struct StoredConfigurationSecrets: Decodable {
        let apiKey: String?
        let customHeaders: String?
        let credentialSchemaVersion: Int?
    }

    private struct StoredConfigurationCredentials: Decodable {
        struct StoredAPIKey: Decodable {
            let id: UUID?
        }

        let id: UUID?
        let apiKeys: [StoredAPIKey]?
        let customHeaders: String?

        var hasSensitiveHeaders: Bool {
            CustomHeaderSecurity.containsSensitiveHeader(customHeaders ?? "")
        }

        var keyIDs: Set<UUID> {
            if let apiKeys {
                return Set(apiKeys.compactMap(\.id))
            }
            return id.map { [$0] } ?? []
        }
    }
}
