import Foundation

extension Notification.Name {
    nonisolated static let aiProviderKeyStateDidChange = Notification.Name("AIProviderKeyStateDidChange")
}

nonisolated final class AIProviderKeyStateStore: @unchecked Sendable {
    static let shared = AIProviderKeyStateStore()

    struct State: Codable, Equatable, Sendable {
        var currentKeyID: UUID?
        var failures: [UUID: AIProviderKeyFailureRecord]

        init(currentKeyID: UUID? = nil, failures: [UUID: AIProviderKeyFailureRecord] = [:]) {
            self.currentKeyID = currentKeyID
            self.failures = failures
        }
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey: String
    // Keep completed requests holding an old credential snapshot from recreating state
    // after that provider or key was removed.
    private var deletedConfigurationIDs = Set<UUID>()
    private var deletedKeyIDs = [UUID: Set<UUID>]()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "aiProviderKeyRuntimeState"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func state(for configurationID: UUID) -> State {
        lock.lock()
        defer { lock.unlock() }
        guard !deletedConfigurationIDs.contains(configurationID) else { return State() }
        return readStatesLocked()[configurationID] ?? State()
    }

    func currentKeyID(for configurationID: UUID, availableKeyIDs: [UUID]) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard !deletedConfigurationIDs.contains(configurationID) else { return nil }

        let removedKeyIDs = deletedKeyIDs[configurationID] ?? []
        let activeKeyIDs = availableKeyIDs.filter { !removedKeyIDs.contains($0) }
        let storedKeyID = readStatesLocked()[configurationID]?.currentKeyID
        if let storedKeyID, activeKeyIDs.contains(storedKeyID) {
            return storedKeyID
        }
        return activeKeyIDs.first
    }

    func setCurrentKeyID(_ keyID: UUID?, for configurationID: UUID) {
        updateState(for: configurationID, keyID: keyID) { state in
            state.currentKeyID = keyID
        }
    }

    func recordFailure(
        _ failure: AIProviderKeyFailureRecord,
        for keyID: UUID,
        configurationID: UUID
    ) {
        updateState(for: configurationID, keyID: keyID) { state in
            state.failures[keyID] = failure
        }
    }

    func clearFailure(for keyID: UUID, configurationID: UUID) {
        updateState(for: configurationID, keyID: keyID) { state in
            state.failures.removeValue(forKey: keyID)
        }
    }

    func removeKeys(_ keyIDs: Set<UUID>, for configurationID: UUID) {
        guard !keyIDs.isEmpty else { return }
        lock.lock()
        guard !deletedConfigurationIDs.contains(configurationID) else {
            lock.unlock()
            return
        }

        deletedKeyIDs[configurationID, default: []].formUnion(keyIDs)
        var states = readStatesLocked()
        let originalState = states[configurationID] ?? State()
        var updatedState = originalState
        for keyID in keyIDs {
            updatedState.failures.removeValue(forKey: keyID)
        }
        if keyIDs.contains(updatedState.currentKeyID ?? UUID()) {
            updatedState.currentKeyID = nil
        }

        let didChange = updatedState != originalState
        if didChange {
            if updatedState.currentKeyID == nil, updatedState.failures.isEmpty {
                states.removeValue(forKey: configurationID)
            } else {
                states[configurationID] = updatedState
            }
            writeStatesLocked(states)
        }
        lock.unlock()

        if didChange {
            postChange(for: configurationID)
        }
    }

    func reconcile(configurationID: UUID, availableKeyIDs: [UUID]) {
        let allowedIDs = Set(availableKeyIDs)
        lock.lock()
        deletedConfigurationIDs.remove(configurationID)
        if var removedKeyIDs = deletedKeyIDs[configurationID] {
            removedKeyIDs.subtract(allowedIDs)
            if removedKeyIDs.isEmpty {
                deletedKeyIDs.removeValue(forKey: configurationID)
            } else {
                deletedKeyIDs[configurationID] = removedKeyIDs
            }
        }

        var states = readStatesLocked()
        let originalState = states[configurationID] ?? State()
        var updatedState = originalState
        updatedState.failures = updatedState.failures.filter { allowedIDs.contains($0.key) }
        if let currentKeyID = updatedState.currentKeyID, !allowedIDs.contains(currentKeyID) {
            updatedState.currentKeyID = availableKeyIDs.first
        } else if updatedState.currentKeyID == nil {
            updatedState.currentKeyID = availableKeyIDs.first
        }

        let didChange = updatedState != originalState
        if didChange {
            if updatedState.currentKeyID == nil, updatedState.failures.isEmpty {
                states.removeValue(forKey: configurationID)
            } else {
                states[configurationID] = updatedState
            }
            writeStatesLocked(states)
        }
        lock.unlock()

        if didChange {
            postChange(for: configurationID)
        }
    }

    func removeState(for configurationID: UUID) {
        lock.lock()
        deletedConfigurationIDs.insert(configurationID)
        deletedKeyIDs.removeValue(forKey: configurationID)
        var states = readStatesLocked()
        let didChange = states.removeValue(forKey: configurationID) != nil
        if didChange {
            writeStatesLocked(states)
        }
        lock.unlock()
        if didChange {
            postChange(for: configurationID)
        }
    }

    private func updateState(
        for configurationID: UUID,
        keyID: UUID? = nil,
        update: (inout State) -> Void
    ) {
        lock.lock()
        let isDeletedKey = keyID.map {
            deletedKeyIDs[configurationID]?.contains($0) == true
        } ?? false
        guard !deletedConfigurationIDs.contains(configurationID), !isDeletedKey else {
            lock.unlock()
            return
        }
        var states = readStatesLocked()
        let originalState = states[configurationID] ?? State()
        var updatedState = originalState
        update(&updatedState)

        let didChange = updatedState != originalState
        if didChange {
            if updatedState.currentKeyID == nil, updatedState.failures.isEmpty {
                states.removeValue(forKey: configurationID)
            } else {
                states[configurationID] = updatedState
            }
            writeStatesLocked(states)
        }
        lock.unlock()

        if didChange {
            postChange(for: configurationID)
        }
    }

    private func readStatesLocked() -> [UUID: State] {
        guard let data = defaults.data(forKey: storageKey),
              let states = try? JSONDecoder().decode([UUID: State].self, from: data) else {
            return [:]
        }
        return states
    }

    private func writeStatesLocked(_ states: [UUID: State]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func postChange(for configurationID: UUID) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .aiProviderKeyStateDidChange,
                object: nil,
                userInfo: ["configurationID": configurationID]
            )
        }
    }
}
