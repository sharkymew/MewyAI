import Foundation
import XCTest
@testable import MewyAI

@MainActor
final class AIProviderFailoverTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AIProviderFailoverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCredentialSetStartsWithCurrentKey() {
        let configurationID = UUID()
        let first = AIProviderAPIKey(name: "Key 1", value: "first-secret")
        let second = AIProviderAPIKey(name: "Key 2", value: "second-secret")
        let third = AIProviderAPIKey(name: "Key 3", value: "third-secret")

        let credentialSet = AIProviderCredentialSet(
            configurationID: configurationID,
            currentKeyID: second.id,
            apiKeys: [first, second, third]
        )

        XCTAssertEqual(credentialSet.currentKeyID, second.id)
        XCTAssertEqual(
            credentialSet.credentials.compactMap(\.keyID),
            [second.id, third.id, first.id]
        )
    }

    func test401RotatesToNextKey() async throws {
        try await assertCredentialFailureRotates(
            statusCode: 401,
            expectedCategory: .authentication
        )
    }

    func test403RotatesToNextKey() async throws {
        try await assertCredentialFailureRotates(
            statusCode: 403,
            expectedCategory: .authentication
        )
    }

    func test429RotatesToNextKey() async throws {
        try await assertCredentialFailureRotates(
            statusCode: 429,
            expectedCategory: .rateLimited
        )
    }

    func testNonCredentialFailureDoesNotRotate() async {
        let fixture = makeFixture()
        let stateStore = makeStateStore()
        let recorder = CredentialAttemptRecorder()
        let executor = AIProviderFailoverExecutor(stateStore: stateStore)

        do {
            _ = try await executor.execute(
                credentialSet: fixture.credentialSet,
                customHeaders: ""
            ) { credential in
                guard let keyID = credential.keyID else { throw CredentialAttemptError.missingKey }
                await recorder.append(keyID)
                throw AIProviderHTTPFailure(
                    statusCode: 500,
                    responseBody: "temporary provider error",
                    apiFormat: .openAIChatCompletions
                )
            } as UUID
            XCTFail("A non-credential HTTP failure should be returned immediately")
        } catch let failure as AIProviderHTTPFailure {
            XCTAssertEqual(failure.statusCode, 500)
            XCTAssertNil(failure.category)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let attempts = await recorder.values()
        XCTAssertEqual(attempts, [fixture.keyIDs[0]])
        XCTAssertTrue(stateStore.state(for: fixture.configurationID).failures.isEmpty)
    }

    func testSuccessfulRequestClearsExistingFailureAndPromotesKey() async throws {
        let fixture = makeFixture()
        let stateStore = makeStateStore()
        let oldFailure = AIProviderKeyFailureRecord(
            category: .rateLimited,
            statusCode: 429,
            summary: "previous failure",
            date: Date(timeIntervalSince1970: 1)
        )
        stateStore.recordFailure(
            oldFailure,
            for: fixture.keyIDs[0],
            configurationID: fixture.configurationID
        )

        let executor = AIProviderFailoverExecutor(stateStore: stateStore)
        let value = try await executor.execute(
            credentialSet: fixture.credentialSet,
            customHeaders: ""
        ) { credential in
            guard let keyID = credential.keyID else { throw CredentialAttemptError.missingKey }
            return keyID
        }

        XCTAssertEqual(value, fixture.keyIDs[0])
        let state = stateStore.state(for: fixture.configurationID)
        XCTAssertEqual(state.currentKeyID, fixture.keyIDs[0])
        XCTAssertTrue(state.failures.isEmpty)
    }

    func testFailureRecordsRedactSecretsBeforePersisting() async throws {
        let firstSecret = "first-secret-should-not-persist"
        let headerSecret = "header-secret-should-not-persist"
        let fixture = makeFixture(values: [firstSecret, "second-secret"])
        let stateStore = makeStateStore()
        let executor = AIProviderFailoverExecutor(stateStore: stateStore)
        let customHeaders = "X-API-Key: \(headerSecret)"

        let value = try await executor.execute(
            credentialSet: fixture.credentialSet,
            customHeaders: customHeaders
        ) { credential in
            guard let keyID = credential.keyID else { throw CredentialAttemptError.missingKey }
            if keyID == fixture.keyIDs[0] {
                throw AIProviderHTTPFailure(
                    statusCode: 401,
                    responseBody: "Rejected \(firstSecret) with \(headerSecret)",
                    apiFormat: .openAIChatCompletions
                )
            }
            return "ok"
        }

        XCTAssertEqual(value, "ok")
        let failure = try XCTUnwrap(
            stateStore.state(for: fixture.configurationID).failures[fixture.keyIDs[0]]
        )
        XCTAssertEqual(failure.category, .authentication)
        XCTAssertTrue(failure.summary.contains("[REDACTED]"))
        XCTAssertFalse(failure.summary.contains(firstSecret))
        XCTAssertFalse(failure.summary.contains(headerSecret))

        let data = try XCTUnwrap(defaults.data(forKey: storageKey()))
        let persistedState = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(persistedState.contains(firstSecret))
        XCTAssertFalse(persistedState.contains(headerSecret))
    }

    func testAllCredentialFailuresTryEachKeyOnceAndRedactFinalError() async {
        let firstSecret = "first-secret-should-not-appear"
        let secondSecret = "second-secret-should-not-appear"
        let fixture = makeFixture(values: [firstSecret, secondSecret])
        let stateStore = makeStateStore(suffix: "all-failed")
        let recorder = CredentialAttemptRecorder()
        let executor = AIProviderFailoverExecutor(stateStore: stateStore)

        do {
            let _: String = try await executor.execute(
                credentialSet: fixture.credentialSet,
                customHeaders: ""
            ) { credential in
                guard let keyID = credential.keyID else { throw CredentialAttemptError.missingKey }
                await recorder.append(keyID)
                throw AIProviderHTTPFailure(
                    statusCode: 429,
                    responseBody: "Rejected \(credential.secret)",
                    apiFormat: .openAIChatCompletions
                )
            }
            XCTFail("Expected all credential attempts to fail")
        } catch let error as AIProviderAllKeysFailedError {
            XCTAssertEqual(error.attemptCount, fixture.keyIDs.count)
            XCTAssertEqual(error.lastFailure.category, .rateLimited)
            XCTAssertFalse(error.localizedDescription.contains(firstSecret))
            XCTAssertFalse(error.localizedDescription.contains(secondSecret))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let attempts = await recorder.values()
        XCTAssertEqual(attempts, fixture.keyIDs)
        XCTAssertEqual(stateStore.state(for: fixture.configurationID).failures.count, fixture.keyIDs.count)
    }

    func testAPIKeyCodableStoresMetadataOnly() throws {
        let secret = "api-key-should-not-appear-in-json"
        let key = AIProviderAPIKey(name: "Primary", value: secret)

        let data = try JSONEncoder().encode(key)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(AIProviderAPIKey.self, from: data)

        XCTAssertFalse(json.contains(secret))
        XCTAssertEqual(decoded.id, key.id)
        XCTAssertEqual(decoded.name, key.name)
        XCTAssertEqual(decoded.value, "")
    }

    func testRemovingCurrentKeyDefersRuntimeStateChangeUntilSave() {
        let configurationID = UUID()
        let first = AIProviderAPIKey(name: "Key 1", value: "first-secret")
        let second = AIProviderAPIKey(name: "Key 2", value: "second-secret")
        let third = AIProviderAPIKey(name: "Key 3", value: "third-secret")
        let stateStore = makeStateStore(suffix: "remove-current")
        stateStore.setCurrentKeyID(second.id, for: configurationID)

        var configuration = AIConfiguration(
            id: configurationID,
            apiKeys: [first, second, third]
        )
        let followingKeyID = configuration.followingAPIKeyID(afterRemoving: second.id)
        let removedKey = configuration.removeAPIKey(id: second.id)

        XCTAssertEqual(removedKey?.id, second.id)
        XCTAssertEqual(configuration.apiKeys.map(\.id), [first.id, third.id])
        XCTAssertEqual(followingKeyID, third.id)
        XCTAssertEqual(stateStore.state(for: configurationID).currentKeyID, second.id)
    }

    func testRemovedProviderIgnoresLateCredentialStateUpdates() {
        let configurationID = UUID()
        let keyID = UUID()
        let stateStore = makeStateStore(suffix: "removed-provider")
        let failure = AIProviderKeyFailureRecord(
            category: .authentication,
            statusCode: 401,
            summary: "expired credential",
            date: Date()
        )

        stateStore.reconcile(configurationID: configurationID, availableKeyIDs: [keyID])
        stateStore.removeState(for: configurationID)
        stateStore.recordFailure(failure, for: keyID, configurationID: configurationID)
        stateStore.setCurrentKeyID(keyID, for: configurationID)

        XCTAssertEqual(stateStore.state(for: configurationID), .init())
    }

    func testRemovedKeyIgnoresLateCredentialStateUpdates() {
        let configurationID = UUID()
        let removedKeyID = UUID()
        let activeKeyID = UUID()
        let stateStore = makeStateStore(suffix: "removed-key")
        let activeFailure = AIProviderKeyFailureRecord(
            category: .rateLimited,
            statusCode: 429,
            summary: "retry later",
            date: Date()
        )
        let staleFailure = AIProviderKeyFailureRecord(
            category: .authentication,
            statusCode: 401,
            summary: "stale request",
            date: Date()
        )

        stateStore.reconcile(
            configurationID: configurationID,
            availableKeyIDs: [removedKeyID, activeKeyID]
        )
        stateStore.setCurrentKeyID(activeKeyID, for: configurationID)
        stateStore.recordFailure(activeFailure, for: activeKeyID, configurationID: configurationID)
        stateStore.removeKeys([removedKeyID], for: configurationID)
        stateStore.recordFailure(staleFailure, for: removedKeyID, configurationID: configurationID)
        stateStore.setCurrentKeyID(removedKeyID, for: configurationID)

        let state = stateStore.state(for: configurationID)
        XCTAssertEqual(state.currentKeyID, activeKeyID)
        XCTAssertEqual(state.failures, [activeKeyID: activeFailure])
    }

    func testLegacyConfigurationMigratesToOneMetadataOnlyKey() throws {
        let configurationID = UUID()
        let legacySecret = "legacy-secret"
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: legacySecret
        )
        legacyPayload.removeValue(forKey: "credentialSchemaVersion")
        legacyPayload.removeValue(forKey: "apiKeys")

        let storage = InMemoryAIProviderKeySecretStorage()
        let configuration = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: storage
        )

        XCTAssertEqual(configuration.credentialSchemaVersion, AIConfiguration.currentCredentialSchemaVersion)
        XCTAssertEqual(configuration.apiKeys.count, 1)
        XCTAssertEqual(configuration.apiKeys.first?.id, configurationID)
        XCTAssertEqual(configuration.apiKeys.first?.name, "Key 1")
        XCTAssertEqual(configuration.apiKeys.first?.value, legacySecret)
        XCTAssertTrue(configuration.persistSecureFields(
            secretStorage: storage,
            persistsSensitiveHeaders: false
        ))
        XCTAssertEqual(storage.readAPIKey(for: configurationID).value, legacySecret)

        let encoded = try JSONEncoder().encode(configuration)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedText.contains(legacySecret))

        let reloadedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let reloaded = try decodeConfiguration(from: reloadedPayload, secretStorage: storage)
        XCTAssertEqual(reloaded.apiKeys.count, 1)
        XCTAssertEqual(reloaded.apiKeys.first?.id, configurationID)
        XCTAssertEqual(reloaded.apiKeys.first?.value, legacySecret)
    }

    func testFailedMigrationWriteLeavesLegacyPayloadUsable() throws {
        let configurationID = UUID()
        let legacySecret = "legacy-secret"
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: legacySecret
        )
        legacyPayload.removeValue(forKey: "credentialSchemaVersion")
        legacyPayload.removeValue(forKey: "apiKeys")

        let storage = InMemoryAIProviderKeySecretStorage()
        storage.setWriteFailure(true, for: configurationID)
        let firstDecode = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: storage
        )

        XCTAssertFalse(firstDecode.persistSecureFields(
            secretStorage: storage,
            persistsSensitiveHeaders: false
        ))
        XCTAssertEqual(storage.readAPIKey(for: configurationID), .missing)

        let secondDecode = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: storage
        )
        XCTAssertEqual(secondDecode.apiKeys.first?.value, legacySecret)
        XCTAssertEqual(secondDecode.apiKeys.first?.id, configurationID)
    }

    func testKeychainReadFailureStillUsesLegacyJSONUntilMigrationSucceeds() throws {
        let configurationID = UUID()
        let legacySecret = "legacy-secret"
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: legacySecret
        )
        legacyPayload.removeValue(forKey: "credentialSchemaVersion")
        legacyPayload.removeValue(forKey: "apiKeys")

        let storage = InMemoryAIProviderKeySecretStorage()
        storage.setReadFailure(true, for: configurationID)

        let configuration = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: storage
        )

        XCTAssertEqual(configuration.apiKeys.first?.id, configurationID)
        XCTAssertEqual(configuration.apiKeys.first?.value, legacySecret)
    }

    func testKeychainReadFailureWithoutLegacyKeyKeepsEmptyKeyList() throws {
        let configurationID = UUID()
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: ""
        )
        legacyPayload.removeValue(forKey: "credentialSchemaVersion")
        legacyPayload.removeValue(forKey: "apiKeys")

        let storage = InMemoryAIProviderKeySecretStorage()
        storage.setReadFailure(true, for: configurationID)
        let configuration = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: storage
        )

        XCTAssertTrue(configuration.apiKeys.isEmpty)
    }

    func testIncompleteCredentialSchemaStillMigratesLegacyAPIKey() throws {
        let configurationID = UUID()
        let legacySecret = "legacy-secret"
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: legacySecret
        )
        legacyPayload["credentialSchemaVersion"] = 0
        legacyPayload.removeValue(forKey: "apiKeys")

        let configuration = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: InMemoryAIProviderKeySecretStorage()
        )

        XCTAssertEqual(configuration.credentialSchemaVersion, AIConfiguration.currentCredentialSchemaVersion)
        XCTAssertEqual(configuration.apiKeys.map(\.id), [configurationID])
        XCTAssertEqual(configuration.apiKeys.first?.value, legacySecret)
    }

    func testMissingAPIKeysInCurrentCredentialSchemaStillMigratesLegacyAPIKey() throws {
        let configurationID = UUID()
        let legacySecret = "legacy-secret"
        var legacyPayload = try configurationPayload(
            id: configurationID,
            apiKey: legacySecret
        )
        legacyPayload["credentialSchemaVersion"] = AIConfiguration.currentCredentialSchemaVersion
        legacyPayload.removeValue(forKey: "apiKeys")

        let configuration = try decodeConfiguration(
            from: legacyPayload,
            secretStorage: InMemoryAIProviderKeySecretStorage()
        )

        XCTAssertEqual(configuration.apiKeys.map(\.id), [configurationID])
        XCTAssertEqual(configuration.apiKeys.first?.value, legacySecret)
    }

    func testExplicitEmptyKeyArrayDoesNotReviveLegacyAPIKey() throws {
        let configurationID = UUID()
        var payload = try configurationPayload(
            id: configurationID,
            apiKey: "legacy-secret"
        )
        payload["credentialSchemaVersion"] = AIConfiguration.currentCredentialSchemaVersion
        payload["apiKeys"] = []

        let configuration = try decodeConfiguration(
            from: payload,
            secretStorage: InMemoryAIProviderKeySecretStorage()
        )

        XCTAssertTrue(configuration.apiKeys.isEmpty)
    }

    func testFailedMultiKeySaveRestoresPreviouslyWrittenSecret() throws {
        let first = AIProviderAPIKey(name: "Key 1", value: "old-first")
        let second = AIProviderAPIKey(name: "Key 2", value: "old-second")
        let configurationID = UUID()
        let storage = InMemoryAIProviderKeySecretStorage()
        let stateStore = makeStateStore(suffix: "transaction")
        let original = AIConfiguration(
            id: configurationID,
            name: "Original",
            apiKeys: [first, second]
        )

        XCTAssertTrue(saveConfigurations(
            [original],
            secretStorage: storage,
            stateStore: stateStore
        ))

        var updated = original
        updated.name = "Changed"
        updated.apiKeys[0].value = "new-first"
        updated.apiKeys[1].value = "new-second"
        storage.setWriteFailure(true, for: second.id)

        XCTAssertFalse(saveConfigurations(
            [updated],
            secretStorage: storage,
            stateStore: stateStore
        ))
        XCTAssertEqual(storage.readAPIKey(for: first.id).value, "old-first")
        XCTAssertEqual(storage.readAPIKey(for: second.id).value, "old-second")
        XCTAssertEqual(storedConfigurationName(), "Original")
    }

    func testFailedKeyDeletionLeavesMetadataAndRuntimeStateUntouched() throws {
        let first = AIProviderAPIKey(name: "Key 1", value: "first-secret")
        let second = AIProviderAPIKey(name: "Key 2", value: "second-secret")
        let configurationID = UUID()
        let storage = InMemoryAIProviderKeySecretStorage()
        let stateStore = makeStateStore(suffix: "delete-failure")
        let original = AIConfiguration(
            id: configurationID,
            name: "Original",
            apiKeys: [first, second]
        )

        XCTAssertTrue(saveConfigurations(
            [original],
            secretStorage: storage,
            stateStore: stateStore
        ))
        let failure = AIProviderKeyFailureRecord(
            category: .rateLimited,
            statusCode: 429,
            summary: "retry later",
            date: Date()
        )
        stateStore.setCurrentKeyID(second.id, for: configurationID)
        stateStore.recordFailure(failure, for: second.id, configurationID: configurationID)

        var updated = original
        updated.name = "Changed"
        XCTAssertNotNil(updated.removeAPIKey(id: second.id))
        storage.setWriteFailure(true, for: second.id)

        XCTAssertFalse(saveConfigurations(
            [updated],
            secretStorage: storage,
            stateStore: stateStore
        ))
        XCTAssertEqual(storedConfigurationName(), "Original")
        XCTAssertEqual(stateStore.state(for: configurationID).currentKeyID, second.id)
        XCTAssertEqual(stateStore.state(for: configurationID).failures[second.id], failure)
        XCTAssertEqual(storage.readAPIKey(for: second.id).value, "second-secret")
    }

    private func assertCredentialFailureRotates(
        statusCode: Int,
        expectedCategory: AIProviderKeyFailureCategory
    ) async throws {
        let fixture = makeFixture()
        let stateStore = makeStateStore(suffix: "status-\(statusCode)")
        let recorder = CredentialAttemptRecorder()
        let executor = AIProviderFailoverExecutor(stateStore: stateStore)

        let value = try await executor.execute(
            credentialSet: fixture.credentialSet,
            customHeaders: ""
        ) { credential in
            guard let keyID = credential.keyID else { throw CredentialAttemptError.missingKey }
            await recorder.append(keyID)
            if keyID == fixture.keyIDs[0] {
                throw AIProviderHTTPFailure(
                    statusCode: statusCode,
                    responseBody: "credential rejected",
                    apiFormat: .openAIChatCompletions
                )
            }
            return keyID
        }

        XCTAssertEqual(value, fixture.keyIDs[1])
        let attempts = await recorder.values()
        XCTAssertEqual(attempts, fixture.keyIDs)

        let state = stateStore.state(for: fixture.configurationID)
        XCTAssertEqual(state.currentKeyID, fixture.keyIDs[1])
        XCTAssertEqual(state.failures[fixture.keyIDs[0]]?.category, expectedCategory)
        XCTAssertEqual(state.failures[fixture.keyIDs[0]]?.statusCode, statusCode)
    }

    private func makeFixture(
        values: [String] = ["first-secret", "second-secret"]
    ) -> CredentialFixture {
        let keys = values.enumerated().map { index, value in
            AIProviderAPIKey(name: "Key \(index + 1)", value: value)
        }
        let configurationID = UUID()
        return CredentialFixture(
            configurationID: configurationID,
            keyIDs: keys.map(\.id),
            credentialSet: AIProviderCredentialSet(
                configurationID: configurationID,
                currentKeyID: keys.first?.id,
                apiKeys: keys
            )
        )
    }

    private func makeStateStore(suffix: String = "default") -> AIProviderKeyStateStore {
        AIProviderKeyStateStore(
            defaults: defaults,
            storageKey: storageKey(suffix: suffix)
        )
    }

    private func storageKey(suffix: String = "default") -> String {
        "provider-state-\(suffix)"
    }

    private func configurationPayload(
        id: UUID,
        apiKey: String
    ) throws -> [String: Any] {
        let configuration = AIConfiguration(id: id, apiKey: apiKey)
        let data = try JSONEncoder().encode(configuration)
        guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialAttemptError.invalidPayload
        }
        payload["apiKey"] = apiKey
        return payload
    }

    private func decodeConfiguration(
        from payload: [String: Any],
        secretStorage: any AIProviderKeySecretStoring
    ) throws -> AIConfiguration {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.userInfo[.aiProviderKeySecretStorage] = secretStorage
        return try decoder.decode(AIConfiguration.self, from: data)
    }

    private func saveConfigurations(
        _ configurations: [AIConfiguration],
        secretStorage: any AIProviderKeySecretStoring,
        stateStore: AIProviderKeyStateStore
    ) -> Bool {
        AIConfigurationStore.saveConfigurations(
            configurations,
            secretStorage: secretStorage,
            defaults: defaults,
            stateStore: stateStore
        )
    }

    private func storedConfigurationName() -> String? {
        guard let data = defaults.data(forKey: "aiConfigurations"),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return payload.first?["name"] as? String
    }
}

private struct CredentialFixture {
    let configurationID: UUID
    let keyIDs: [UUID]
    let credentialSet: AIProviderCredentialSet
}

private enum CredentialAttemptError: Error {
    case missingKey
    case invalidPayload
}

private actor CredentialAttemptRecorder {
    private var attemptedKeyIDs = [UUID]()

    func append(_ keyID: UUID) {
        attemptedKeyIDs.append(keyID)
    }

    func values() -> [UUID] {
        attemptedKeyIDs
    }
}
