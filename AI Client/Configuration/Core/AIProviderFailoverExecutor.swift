import Foundation

nonisolated struct AIProviderFailoverExecutor {
    private let stateStore: AIProviderKeyStateStore

    init(stateStore: AIProviderKeyStateStore = .shared) {
        self.stateStore = stateStore
    }

    func execute<Value>(
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        operation: (AIProviderCredential) async throws -> Value
    ) async throws -> Value {
        var lastFailure: AIProviderKeyFailureRecord?
        var failedKeyCount = 0

        for credential in credentialSet.credentials {
            do {
                let value = try await operation(credential)
                if let keyID = credential.keyID {
                    stateStore.clearFailure(for: keyID, configurationID: credentialSet.configurationID)
                    stateStore.setCurrentKeyID(keyID, for: credentialSet.configurationID)
                }
                return value
            } catch let failure as AIProviderHTTPFailure {
                guard failure.isCredentialFailure,
                      let keyID = credential.keyID else {
                    throw failure
                }

                let record = AIProviderKeyFailureRecord(
                    category: failure.category ?? .authentication,
                    statusCode: failure.statusCode,
                    summary: AIProviderFailureSanitizer.summary(
                        from: failure.responseBody,
                        credentials: credentialSet.credentials,
                        customHeaders: customHeaders
                    ),
                    date: Date()
                )
                stateStore.recordFailure(record, for: keyID, configurationID: credentialSet.configurationID)
                lastFailure = record
                failedKeyCount += 1
            }
        }

        if let lastFailure, failedKeyCount > 0 {
            throw AIProviderAllKeysFailedError(
                attemptCount: failedKeyCount,
                lastFailure: lastFailure
            )
        }

        throw AIServiceError.requestFailed(AppLocalizations.string(
            "providerKey.failure.noCredentials",
            defaultValue: "No API key is available for this request."
        ))
    }
}
