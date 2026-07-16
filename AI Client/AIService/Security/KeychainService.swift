import Foundation
import Security

nonisolated enum KeychainService {
    private static let apiKeyService = "AIClient.APIKey"
    private static let agentSecretService = "AIClient.AgentSecret"
    private static let headerSecretServicePrefix = "AIClient.HeaderSecret."

    static func readAPIKey(for keyID: UUID) -> String {
        readAPIKeyResult(for: keyID).value
    }

    static func readAPIKeyResult(for keyID: UUID) -> AIProviderKeySecretReadResult {
        readSecretResult(service: apiKeyService, account: keyID.uuidString)
    }

    @discardableResult
    static func saveAPIKey(_ apiKey: String, for keyID: UUID) -> Bool {
        saveSecret(apiKey, service: apiKeyService, account: keyID.uuidString)
    }

    @discardableResult
    static func deleteAPIKey(for keyID: UUID) -> Bool {
        deleteSecret(service: apiKeyService, account: keyID.uuidString)
    }

    @discardableResult
    static func deleteAPIKeys<S: Sequence>(for keyIDs: S) -> Bool where S.Element == UUID {
        var didDeleteAll = true
        for keyID in keyIDs {
            if !deleteAPIKey(for: keyID) {
                didDeleteAll = false
            }
        }
        return didDeleteAll
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

    /// Returns every sensitive custom-header secret for a provider. `nil` means the
    /// Keychain could not be read, which is different from a provider with no headers.
    static func headerSecretValues(for configurationID: UUID) -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: headerSecretService(for: configurationID),
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else { return nil }

        let dictionaries: [[String: Any]]
        if let values = items as? [[String: Any]] {
            dictionaries = values
        } else if let value = items as? [String: Any] {
            dictionaries = [value]
        } else {
            return nil
        }

        var secrets = [String: String]()
        for dictionary in dictionaries {
            guard let account = dictionary[kSecAttrAccount as String] as? String,
                  let data = dictionary[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            secrets[account] = value
        }
        return secrets
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
        var didDeleteAll = true
        for account in accounts where !retainedAccounts.contains(account) {
            if !deleteSecret(service: headerSecretService(for: configurationID), account: account) {
                didDeleteAll = false
            }
        }
        return didDeleteAll
    }

    /// Best-effort replacement used only to restore a failed configuration save.
    @discardableResult
    static func restoreHeaderSecrets(
        _ secrets: [String: String],
        for configurationID: UUID
    ) -> Bool {
        var didRestoreAll = true
        for (headerName, value) in secrets {
            if !saveHeaderSecret(value, for: configurationID, headerName: headerName) {
                didRestoreAll = false
            }
        }
        guard didRestoreAll else { return false }

        return deleteHeaderSecrets(
            for: configurationID,
            excluding: Set(secrets.keys)
        )
    }

    private static func readSecret(service: String, account: String) -> String {
        readSecretResult(service: service, account: account).value
    }

    private static func readSecretResult(
        service: String,
        account: String
    ) -> AIProviderKeySecretReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .missing
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return .failure
        }

        return .value(value)
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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
