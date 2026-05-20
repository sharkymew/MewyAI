import Foundation

struct AIConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var endpoint: String
    var apiKey: String
    var customHeaders: String
    var models: [String]
    var selectedModel: String
    var updatedAt: Date
    
    var requestURLString: String {
        Self.join(baseURL: baseURL, endpoint: endpoint)
    }
    
    init(
        id: UUID = UUID(),
        name: String = "默认配置",
        baseURL: String = "https://api.deepseek.com",
        endpoint: String = "chat/completions",
        apiKey: String = "",
        customHeaders: String = "",
        models: [String] = ["deepseek-v4-pro"],
        selectedModel: String = "deepseek-v4-pro",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.models = models
        self.selectedModel = selectedModel
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case endpoint
        case apiKey
        case customHeaders
        case models
        case selectedModel
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "默认配置"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        customHeaders = try container.decodeIfPresent(String.self, forKey: .customHeaders) ?? ""
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? ["deepseek-v4-pro"]
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? models.first ?? "deepseek-v4-pro"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        
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
            models: ["deepseek-v4-pro"],
            selectedModel: "deepseek-v4-pro"
        )
    }
}
