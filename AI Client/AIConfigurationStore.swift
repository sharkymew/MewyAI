import Foundation

struct AIConfiguration: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "默认配置"
    var baseURL: String = "https://api.deepseek.com/chat/completions"
    var apiKey: String = ""
    var customHeaders: String = ""
    var models: [String] = ["deepseek-v4-pro"]
    var selectedModel: String = "deepseek-v4-pro"
    var updatedAt: Date = Date()
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
        let baseURL = defaults.string(forKey: "baseURL") ?? "https://api.deepseek.com/chat/completions"
        let apiKey = defaults.string(forKey: "apiKey") ?? ""
        let customHeaders = defaults.string(forKey: "customHeaders") ?? ""
        
        return AIConfiguration(
            name: "默认配置",
            baseURL: baseURL,
            apiKey: apiKey,
            customHeaders: customHeaders,
            models: ["deepseek-v4-pro"],
            selectedModel: "deepseek-v4-pro"
        )
    }
}
