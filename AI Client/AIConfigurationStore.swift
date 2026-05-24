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

struct AIModelConfiguration: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var supportsReasoning: Bool
    var supportsImages: Bool
    
    init(name: String, supportsReasoning: Bool = false, supportsImages: Bool = false) {
        self.name = name
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
    }
}

struct AIConfiguration: Identifiable, Codable, Equatable {
    static let defaultSystemPrompt = "你是一个友好且有帮助的AI助手。"

    var id: UUID
    var name: String
    var baseURL: String
    var endpoint: String
    var apiKey: String
    var customHeaders: String
    var systemPrompt: String
    var promptPresets: [AIPromptPreset]
    var selectedPromptPresetID: UUID
    var models: [AIModelConfiguration]
    var selectedModel: String
    var reasoningEnabled: Bool
    var reasoningEffort: ReasoningEffort
    var updatedAt: Date
    
    var requestURLString: String {
        Self.join(baseURL: baseURL, endpoint: endpoint)
    }
    
    var selectedModelConfiguration: AIModelConfiguration? {
        models.first { $0.name == selectedModel }
    }
    
    var selectedModelSupportsReasoning: Bool {
        selectedModelConfiguration?.supportsReasoning == true
    }
    
    var selectedModelSupportsImages: Bool {
        selectedModelConfiguration?.supportsImages == true
    }

    var selectedPromptPreset: AIPromptPreset? {
        promptPresets.first { $0.id == selectedPromptPresetID } ?? promptPresets.first
    }
    
    init(
        id: UUID = UUID(),
        name: String = "默认配置",
        baseURL: String = "https://api.deepseek.com",
        endpoint: String = "chat/completions",
        apiKey: String = "",
        customHeaders: String = "",
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        promptPresets: [AIPromptPreset]? = nil,
        selectedPromptPresetID: UUID? = nil,
        models: [AIModelConfiguration] = [AIModelConfiguration(name: "deepseek-v4-pro")],
        selectedModel: String = "deepseek-v4-pro",
        reasoningEnabled: Bool = true,
        reasoningEffort: ReasoningEffort = .medium,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.endpoint = endpoint
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
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case endpoint
        case customHeaders
        case systemPrompt
        case promptPresets
        case selectedPromptPresetID
        case models
        case selectedModel
        case reasoningEnabled
        case reasoningEffort
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
        reasoningEnabled = try container.decodeIfPresent(Bool.self, forKey: .reasoningEnabled) ?? true
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        
        if container.contains(.models),
           let decodedModels = try? container.decode([AIModelConfiguration].self, forKey: .models) {
            models = decodedModels
        } else if container.contains(.models),
                  let legacyModels = try? container.decode([String].self, forKey: .models) {
            models = legacyModels.map { AIModelConfiguration(name: $0) }
        } else {
            models = [AIModelConfiguration(name: "deepseek-v4-pro")]
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
        let knownEndpoints = ["chat/completions", "responses"]
        
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
    private static let selectedConfigurationIDKey = "selectedAIConfigurationID"
    
    static func loadConfigurations() -> [AIConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: configurationsKey),
              let configurations = try? JSONDecoder().decode([AIConfiguration].self, from: data),
              !configurations.isEmpty else {
            return [migratedDefaultConfiguration()]
        }
        
        return configurations
    }
    
    static func saveConfigurations(_ configurations: [AIConfiguration]) {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        UserDefaults.standard.set(data, forKey: configurationsKey)
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
            models: [AIModelConfiguration(name: "deepseek-v4-pro")],
            selectedModel: "deepseek-v4-pro"
        )
    }
}
