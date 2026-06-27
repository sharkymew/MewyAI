import Foundation
import Security

nonisolated enum KeychainService {
    private static let apiKeyService = "AIClient.APIKey"
    private static let agentSecretService = "AIClient.AgentSecret"
    private static let headerSecretServicePrefix = "AIClient.HeaderSecret."
    private static let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    static func readAPIKey(for configurationID: UUID) -> String {
        readSecret(service: apiKeyService, account: configurationID.uuidString)
    }

    @discardableResult
    static func saveAPIKey(_ apiKey: String, for configurationID: UUID) -> Bool {
        saveSecret(apiKey, service: apiKeyService, account: configurationID.uuidString)
    }

    @discardableResult
    static func deleteAPIKey(for configurationID: UUID) -> Bool {
        deleteSecret(service: apiKeyService, account: configurationID.uuidString)
    }

    static func readAgentSecret(for id: UUID) -> String {
        readSecret(service: agentSecretService, account: id.uuidString)
    }

    @discardableResult
    static func saveAgentSecret(_ value: String, for id: UUID) -> Bool {
        saveSecret(value, service: agentSecretService, account: id.uuidString)
    }

    @discardableResult
    static func deleteAgentSecret(for id: UUID) -> Bool {
        deleteSecret(service: agentSecretService, account: id.uuidString)
    }

    static func readHeaderSecret(for configurationID: UUID, headerName: String) -> String {
        readSecret(service: headerSecretService(for: configurationID), account: normalizedHeaderName(headerName))
    }

    @discardableResult
    static func saveHeaderSecret(_ value: String, for configurationID: UUID, headerName: String) -> Bool {
        saveSecret(value, service: headerSecretService(for: configurationID), account: normalizedHeaderName(headerName))
    }

    @discardableResult
    static func deleteHeaderSecrets(for configurationID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: headerSecretService(for: configurationID)
        ]
        return isSuccessfulDeletion(SecItemDelete(query as CFDictionary))
    }

    @discardableResult
    static func deleteHeaderSecrets(for configurationID: UUID, excluding retainedAccounts: Set<String>) -> Bool {
        guard let accounts = headerSecretAccounts(for: configurationID) else { return false }
        return accounts
            .filter { !retainedAccounts.contains($0) }
            .allSatisfy {
                deleteSecret(service: headerSecretService(for: configurationID), account: $0)
            }
    }

    @discardableResult
    static func deleteAllSecrets(for configurationID: UUID) -> Bool {
        deleteAPIKey(for: configurationID) && deleteHeaderSecrets(for: configurationID)
    }

    private static func readSecret(service: String, account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }

    private static func readSecret(service: String, account: String, legacyAccount: String) -> String {
        let value = readSecret(service: service, account: account)
        if !value.isEmpty { return value }
        return readSecret(service: service, account: legacyAccount)
    }

    private static func saveSecret(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if value.isEmpty {
            return deleteSecret(service: service, account: account)
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [
                kSecValueData as String: data,
                kSecAttrAccessible as String: accessible
            ] as CFDictionary)
            return updateStatus == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func saveSecret(_ value: String, service: String, account: String, legacyAccount: String) -> Bool {
        saveSecret(value, service: service, account: account) &&
            deleteSecret(service: service, account: legacyAccount)
    }

    private static func deleteSecret(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return isSuccessfulDeletion(SecItemDelete(query as CFDictionary))
    }

    private static func headerSecretAccounts(for configurationID: UUID) -> [String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: headerSecretService(for: configurationID),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { return nil }

        if let dictionaries = items as? [[String: Any]] {
            return dictionaries.compactMap { $0[kSecAttrAccount as String] as? String }
        }

        if let dictionary = items as? [String: Any],
           let account = dictionary[kSecAttrAccount as String] as? String {
            return [account]
        }

        return []
    }

    private static func isSuccessfulDeletion(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }

    private static func headerSecretService(for configurationID: UUID) -> String {
        headerSecretServicePrefix + configurationID.uuidString
    }

    private static func normalizedHeaderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
