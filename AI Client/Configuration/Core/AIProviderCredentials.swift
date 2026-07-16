import Foundation

nonisolated enum AIProviderKeySecretReadResult: Equatable, Sendable {
    case value(String)
    case missing
    case failure

    var value: String {
        guard case .value(let value) = self else { return "" }
        return value
    }
}

extension CodingUserInfoKey {
    nonisolated static let aiProviderKeySecretStorage = CodingUserInfoKey(rawValue: "aiProviderKeySecretStorage")!
}

nonisolated protocol AIProviderKeySecretStoring: Sendable {
    func readAPIKey(for keyID: UUID) -> AIProviderKeySecretReadResult

    @discardableResult
    func saveAPIKey(_ value: String, for keyID: UUID) -> Bool

    @discardableResult
    func deleteAPIKey(for keyID: UUID) -> Bool
}

nonisolated struct KeychainAIProviderKeySecretStorage: AIProviderKeySecretStoring {
    func readAPIKey(for keyID: UUID) -> AIProviderKeySecretReadResult {
        KeychainService.readAPIKeyResult(for: keyID)
    }

    @discardableResult
    func saveAPIKey(_ value: String, for keyID: UUID) -> Bool {
        KeychainService.saveAPIKey(value, for: keyID)
    }

    @discardableResult
    func deleteAPIKey(for keyID: UUID) -> Bool {
        KeychainService.deleteAPIKey(for: keyID)
    }
}

nonisolated final class InMemoryAIProviderKeySecretStorage: AIProviderKeySecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String]
    private var failingKeyIDs = Set<UUID>()
    private var failingReadKeyIDs = Set<UUID>()

    init(values: [UUID: String] = [:]) {
        self.values = values
    }

    func readAPIKey(for keyID: UUID) -> AIProviderKeySecretReadResult {
        lock.lock()
        defer { lock.unlock() }
        guard !failingReadKeyIDs.contains(keyID) else { return .failure }
        guard let value = values[keyID] else { return .missing }
        return .value(value)
    }

    @discardableResult
    func saveAPIKey(_ value: String, for keyID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !failingKeyIDs.contains(keyID) else { return false }
        if value.isEmpty {
            values.removeValue(forKey: keyID)
        } else {
            values[keyID] = value
        }
        return true
    }

    @discardableResult
    func deleteAPIKey(for keyID: UUID) -> Bool {
        saveAPIKey("", for: keyID)
    }

    func setWriteFailure(_ shouldFail: Bool, for keyID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail {
            failingKeyIDs.insert(keyID)
        } else {
            failingKeyIDs.remove(keyID)
        }
    }

    func setReadFailure(_ shouldFail: Bool, for keyID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail {
            failingReadKeyIDs.insert(keyID)
        } else {
            failingReadKeyIDs.remove(keyID)
        }
    }
}

nonisolated struct AIProviderAPIKey: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }

    var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var maskedSuffix: String {
        let secret = trimmedValue
        guard !secret.isEmpty else { return "••••" }
        return "••••" + secret.suffix(4)
    }
}

nonisolated enum AIProviderAPIKeyValidationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case duplicateName
    case emptySecret
    case keyNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return AppLocalizations.string("providerKey.validation.emptyName", defaultValue: "Enter a name for this API key.")
        case .duplicateName:
            return AppLocalizations.string("providerKey.validation.duplicateName", defaultValue: "API key names must be unique within this provider.")
        case .emptySecret:
            return AppLocalizations.string("providerKey.validation.emptySecret", defaultValue: "Enter an API key.")
        case .keyNotFound:
            return AppLocalizations.string("providerKey.validation.notFound", defaultValue: "The API key no longer exists.")
        }
    }
}

nonisolated struct AIProviderCredential: Equatable, Sendable {
    enum Identity: Equatable, Sendable {
        case apiKey(UUID)
        case anonymous

        var keyID: UUID? {
            guard case .apiKey(let keyID) = self else { return nil }
            return keyID
        }
    }

    let identity: Identity
    let secret: String

    init(identity: Identity, secret: String) {
        self.identity = identity
        self.secret = secret
    }

    var keyID: UUID? {
        identity.keyID
    }
}

nonisolated struct AIProviderCredentialSet: Equatable, Sendable {
    let configurationID: UUID
    let currentKeyID: UUID?
    let credentials: [AIProviderCredential]

    init(
        configurationID: UUID,
        currentKeyID: UUID?,
        apiKeys: [AIProviderAPIKey]
    ) {
        let usableKeys = apiKeys.filter { !$0.trimmedValue.isEmpty }
        guard !usableKeys.isEmpty else {
            self.configurationID = configurationID
            self.currentKeyID = nil
            self.credentials = [AIProviderCredential(identity: .anonymous, secret: "")]
            return
        }

        let startIndex = usableKeys.firstIndex(where: { $0.id == currentKeyID }) ?? usableKeys.startIndex
        let orderedKeys = Array(usableKeys[startIndex...]) + Array(usableKeys[..<startIndex])
        self.configurationID = configurationID
        self.currentKeyID = orderedKeys.first?.id
        self.credentials = orderedKeys.map {
            AIProviderCredential(identity: .apiKey($0.id), secret: $0.trimmedValue)
        }
    }

    static func legacy(apiKey: String) -> AIProviderCredentialSet {
        AIProviderCredentialSet(
            configurationID: UUID(),
            currentKeyID: nil,
            credentials: [AIProviderCredential(identity: .anonymous, secret: apiKey)]
        )
    }

    private init(
        configurationID: UUID,
        currentKeyID: UUID?,
        credentials: [AIProviderCredential]
    ) {
        self.configurationID = configurationID
        self.currentKeyID = currentKeyID
        self.credentials = credentials
    }

    var hasAPIKeys: Bool {
        credentials.contains { $0.keyID != nil }
    }
}

nonisolated enum AIProviderKeyFailureCategory: String, Codable, Sendable {
    case authentication
    case rateLimited
    case invalidAPIKey

    var title: String {
        switch self {
        case .authentication:
            return AppLocalizations.string("providerKey.failure.authentication", defaultValue: "Authentication failed")
        case .rateLimited:
            return AppLocalizations.string("providerKey.failure.rateLimited", defaultValue: "Rate limited")
        case .invalidAPIKey:
            return AppLocalizations.string("providerKey.failure.invalidAPIKey", defaultValue: "Invalid API key")
        }
    }
}

nonisolated struct AIProviderKeyFailureRecord: Codable, Equatable, Sendable {
    let category: AIProviderKeyFailureCategory
    let statusCode: Int?
    let summary: String
    let date: Date
}

nonisolated struct AIProviderHTTPFailure: LocalizedError, Equatable, Sendable {
    let statusCode: Int
    let responseBody: String
    let category: AIProviderKeyFailureCategory?

    init(statusCode: Int, responseBody: String, apiFormat: AIAPIFormat) {
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.category = Self.failureCategory(
            statusCode: statusCode,
            responseBody: responseBody,
            apiFormat: apiFormat
        )
    }

    var isCredentialFailure: Bool {
        category != nil
    }

    var errorDescription: String? {
        AppLocalizations.format(
            "providerKey.failure.http",
            defaultValue: "Request failed with HTTP status %d.",
            arguments: [statusCode]
        )
    }

    private static func failureCategory(
        statusCode: Int,
        responseBody: String,
        apiFormat: AIAPIFormat
    ) -> AIProviderKeyFailureCategory? {
        switch statusCode {
        case 401, 403:
            return .authentication
        case 429:
            return .rateLimited
        case 400 where apiFormat == .vertexAIExpress && hasStructuredGoogleCredentialSignal(in: responseBody):
            return .invalidAPIKey
        default:
            return nil
        }
    }

    private static func hasStructuredGoogleCredentialSignal(in responseBody: String) -> Bool {
        guard let data = responseBody.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let error = object as? [String: Any] else {
            return false
        }

        return containsCredentialSignal(in: error)
    }

    private static func containsCredentialSignal(in object: Any) -> Bool {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
                if ["status", "reason", "code", "errorcode"].contains(normalizedKey),
                   let signal = value as? String,
                   ["API_KEY_INVALID", "UNAUTHENTICATED"].contains(signal.uppercased()) {
                    return true
                }
                if containsCredentialSignal(in: value) {
                    return true
                }
            }
        } else if let array = object as? [Any] {
            return array.contains { containsCredentialSignal(in: $0) }
        }
        return false
    }
}

nonisolated enum AIProviderFailureSanitizer {
    static func summary(
        from responseBody: String,
        credentials: [AIProviderCredential],
        customHeaders: String,
        maximumLength: Int = 500
    ) -> String {
        var result = responseBody
        let values = credentials.map(\.secret)
            + CustomHeaderSecurity.sensitiveHeaderValues(from: customHeaders)

        for value in Set(values).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: value, with: "[REDACTED]")
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                result = result.replacingOccurrences(of: encoded, with: "[REDACTED]")
            }
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(trimmed.prefix(max(1, maximumLength)))
        return bounded.isEmpty
            ? AppLocalizations.string("providerKey.failure.noSummary", defaultValue: "No response body")
            : bounded
    }
}

nonisolated struct AIProviderAllKeysFailedError: LocalizedError, Sendable {
    let attemptCount: Int
    let lastFailure: AIProviderKeyFailureRecord

    var errorDescription: String? {
        AppLocalizations.format(
            "providerKey.failure.allUnavailable",
            defaultValue: "All %d API keys are unavailable. Last error: %@",
            arguments: [attemptCount, lastFailure.summary]
        )
    }
}
