import Foundation

@MainActor
protocol ChatSessionAuxiliaryAIServicing: AnyObject {
    func generateConversationTitle(
        messages: [ChatMessage],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    )

    func extractMemoryUpdates(
        memoryEntries: [ChatMemoryEntry],
        userText: String,
        assistantText: String,
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping ([ChatMemoryOperation]?) -> Void
    )

    func summarizeMemoryHistoryBatch(
        memoryEntries: [ChatMemoryEntry],
        batch: ChatMemoryHistoryBatch,
        batchCount: Int,
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistoryBatchSummary?) -> Void
    )

    func mergeMemoryHistorySummaries(
        memoryEntries: [ChatMemoryEntry],
        batchSummaries: [ChatMemoryHistoryBatchSummary],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistorySummaryResult?) -> Void
    )

    func generateImageContextDescription(
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    )

    func generateConversationTitle(
        messages: [ChatMessage],
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    )

    func extractMemoryUpdates(
        memoryEntries: [ChatMemoryEntry],
        userText: String,
        assistantText: String,
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping ([ChatMemoryOperation]?) -> Void
    )

    func summarizeMemoryHistoryBatch(
        memoryEntries: [ChatMemoryEntry],
        batch: ChatMemoryHistoryBatch,
        batchCount: Int,
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistoryBatchSummary?) -> Void
    )

    func mergeMemoryHistorySummaries(
        memoryEntries: [ChatMemoryEntry],
        batchSummaries: [ChatMemoryHistoryBatchSummary],
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistorySummaryResult?) -> Void
    )

    func generateImageContextDescription(
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    )
}

extension ChatAuxiliaryAIService: ChatSessionAuxiliaryAIServicing {}

protocol ChatMemoryEntryStoring {
    func loadEntries() -> [ChatMemoryEntry]

    @discardableResult
    func saveEntries(_ entries: [ChatMemoryEntry]) -> Bool
}

struct PersistentChatMemoryEntryStore: ChatMemoryEntryStoring {
    func loadEntries() -> [ChatMemoryEntry] {
        ChatMemoryStore.loadEntries()
    }

    @discardableResult
    func saveEntries(_ entries: [ChatMemoryEntry]) -> Bool {
        ChatMemoryStore.saveEntries(entries)
    }
}

protocol ChatMemoryHistorySummaryStoring {
    func loadSnapshot() -> ChatMemoryHistorySummarySnapshot

    @discardableResult
    func saveSnapshot(_ snapshot: ChatMemoryHistorySummarySnapshot) -> Bool
}

struct PersistentChatMemoryHistorySummaryStore: ChatMemoryHistorySummaryStoring {
    func loadSnapshot() -> ChatMemoryHistorySummarySnapshot {
        ChatMemoryHistorySummaryStore.loadSnapshot()
    }

    @discardableResult
    func saveSnapshot(_ snapshot: ChatMemoryHistorySummarySnapshot) -> Bool {
        ChatMemoryHistorySummaryStore.saveSnapshot(snapshot)
    }
}

nonisolated final class ChatSessionPostProcessor {
    private struct AuxiliaryRequestConfiguration {
        private let configuration: AIConfiguration
        let baseURL: String
        let apiFormat: AIAPIFormat
        let customHeaders: String
        let model: String
        let modelParameters: AIModelConfiguration?
        let anthropicMaxTokens: Int
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?

        @MainActor
        var credentialSet: AIProviderCredentialSet {
            configuration.credentialSet()
        }

        @MainActor
        init?(configuration: AIConfiguration) {
            let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { return nil }

            self.configuration = configuration
            baseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            apiFormat = configuration.apiFormat
            customHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
            self.model = model
            modelParameters = configuration.selectedModelConfiguration
            anthropicMaxTokens = configuration.anthropicMaxTokens
            reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
            reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil
        }
    }

    private struct HistorySummaryWorkItem {
        let conversation: AIConversation
        let fingerprint: String
        let batches: [ChatMemoryHistoryBatch]
    }

    private let auxiliaryAIService: ChatSessionAuxiliaryAIServicing
    private let memoryStore: ChatMemoryEntryStoring
    private let historySummaryStore: ChatMemoryHistorySummaryStoring
    private var memoryExtractionConversationIDs = Set<UUID>()
    private var historySummaryUpdateKeys = Set<String>()

    @MainActor
    var activeHistorySummaryUpdateCount: Int {
        historySummaryUpdateKeys.count
    }

    @MainActor
    init() {
        self.auxiliaryAIService = ChatAuxiliaryAIService()
        self.memoryStore = PersistentChatMemoryEntryStore()
        self.historySummaryStore = PersistentChatMemoryHistorySummaryStore()
    }

    @MainActor
    init(
        auxiliaryAIService: ChatSessionAuxiliaryAIServicing,
        memoryStore: ChatMemoryEntryStoring
    ) {
        self.auxiliaryAIService = auxiliaryAIService
        self.memoryStore = memoryStore
        self.historySummaryStore = PersistentChatMemoryHistorySummaryStore()
    }

    @MainActor
    init(
        auxiliaryAIService: ChatSessionAuxiliaryAIServicing,
        memoryStore: ChatMemoryEntryStoring,
        historySummaryStore: ChatMemoryHistorySummaryStoring
    ) {
        self.auxiliaryAIService = auxiliaryAIService
        self.memoryStore = memoryStore
        self.historySummaryStore = historySummaryStore
    }

    @discardableResult
    @MainActor
    func generateImageContextDescriptionIfNeeded(
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        onDescriptionGenerated: @escaping @MainActor (String) -> Void
    ) -> Bool {
        return generateImageContextDescriptionIfNeeded(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            apiFormat: apiFormat,
            credentialSet: .legacy(apiKey: apiKey),
            customHeaders: customHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            onDescriptionGenerated: onDescriptionGenerated
        )
    }

    @discardableResult
    @MainActor
    func generateImageContextDescriptionIfNeeded(
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        onDescriptionGenerated: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard !imageAttachments.isEmpty else { return false }

        auxiliaryAIService.generateImageContextDescription(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            apiFormat: apiFormat,
            credentialSet: credentialSet,
            customHeaders: customHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ) { [weak self] description in
            Task { @MainActor in
                guard self != nil,
                      let description else {
                    return
                }

                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedDescription.isEmpty else { return }
                onDescriptionGenerated(trimmedDescription)
            }
        }

        return true
    }

    @discardableResult
    @MainActor
    func updateHistorySummaryIfNeeded(
        for conversation: AIConversation,
        configuration: AIConfiguration,
        isMemoryEnabled: @escaping @MainActor () -> Bool,
        privateConversationID: UUID?,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        guard isMemoryEnabled(),
              conversation.id != privateConversationID,
              let requestConfiguration = AuxiliaryRequestConfiguration(configuration: configuration) else {
            return false
        }

        let fingerprint = ChatMemoryHistoryBatchBuilder.fingerprint(for: conversation)
        let snapshot = historySummaryStore.loadSnapshot()
        guard !snapshot.conversationSummaries.contains(where: {
            $0.conversationID == conversation.id && $0.fingerprint == fingerprint
        }) else {
            return false
        }

        let batches = ChatMemoryHistoryBatchBuilder.makeBatches(for: conversation)
        guard !batches.isEmpty else { return false }

        let updateKey = "\(conversation.id.uuidString):\(fingerprint)"
        guard !historySummaryUpdateKeys.contains(updateKey) else { return false }

        historySummaryUpdateKeys.insert(updateKey)
        ChatMemoryHistorySummaryStore.setUpdateInProgress(true)
        onPendingCountChanged()

        summarizeHistoryBatch(
            at: 0,
            batches: batches,
            batchSummaries: [],
            memorySnapshot: memoryStore.loadEntries(),
            conversation: conversation,
            fingerprint: fingerprint,
            requestConfiguration: requestConfiguration,
            updateKey: updateKey,
            onPendingCountChanged: onPendingCountChanged
        )

        return true
    }

    @discardableResult
    @MainActor
    func updateMissingHistorySummariesIfNeeded(
        for conversations: [AIConversation],
        loadConversation: @MainActor (UUID) -> AIConversation? = { ConversationStore.loadConversation(id: $0) },
        configuration: AIConfiguration,
        isMemoryEnabled: @escaping @MainActor () -> Bool,
        privateConversationID: UUID?,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) -> Bool {
        guard isMemoryEnabled(),
              let requestConfiguration = AuxiliaryRequestConfiguration(configuration: configuration) else {
            return false
        }

        let updateKey = "history-summary-backfill"
        guard !historySummaryUpdateKeys.contains(updateKey) else { return false }

        let workItems = historySummaryWorkItems(
            from: conversations,
            loadConversation: loadConversation,
            privateConversationID: privateConversationID
        )
        guard !workItems.isEmpty else { return false }

        historySummaryUpdateKeys.insert(updateKey)
        ChatMemoryHistorySummaryStore.setUpdateInProgress(true)
        onPendingCountChanged()

        summarizeHistoryBackfillItem(
            at: 0,
            workItems: workItems,
            conversationSummaries: [],
            memorySnapshot: memoryStore.loadEntries(),
            requestConfiguration: requestConfiguration,
            isMemoryEnabled: isMemoryEnabled,
            updateKey: updateKey,
            onPendingCountChanged: onPendingCountChanged
        )

        return true
    }

    @discardableResult
    @MainActor
    func generateTitleIfNeeded(
        for conversation: AIConversation,
        configuration: AIConfiguration,
        privateConversationID: UUID?,
        onTitleGenerated: @escaping @MainActor (_ conversationID: UUID, _ title: String) -> Void
    ) -> Bool {
        guard conversation.id != privateConversationID,
              !conversation.hasGeneratedTitle,
              conversation.messages.contains(where: { $0.role == "assistant" && !$0.content.isEmpty }),
              let requestConfiguration = AuxiliaryRequestConfiguration(configuration: configuration) else {
            return false
        }

        let conversationID = conversation.id
        auxiliaryAIService.generateConversationTitle(
            messages: conversation.messages,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] title in
            Task { @MainActor in
                guard self != nil,
                      let title,
                      !title.isEmpty else {
                    return
                }

                onTitleGenerated(conversationID, title)
            }
        }

        return true
    }

    @discardableResult
    @MainActor
    func extractMemoriesIfNeeded(
        for conversation: AIConversation,
        configuration: AIConfiguration,
        isMemoryEnabled: @escaping @MainActor () -> Bool,
        privateConversationID: UUID?
    ) -> Bool {
        guard isMemoryEnabled(),
              conversation.id != privateConversationID,
              !memoryExtractionConversationIDs.contains(conversation.id),
              let requestConfiguration = AuxiliaryRequestConfiguration(configuration: configuration),
              let extractionSource = Self.memoryExtractionSource(from: conversation.messages) else {
            return false
        }

        let memorySnapshot = memoryStore.loadEntries()
        let snapshotIDs = memorySnapshot.map(\.id)
        let conversationID = conversation.id
        memoryExtractionConversationIDs.insert(conversationID)

        auxiliaryAIService.extractMemoryUpdates(
            memoryEntries: memorySnapshot,
            userText: extractionSource.userText,
            assistantText: extractionSource.assistantText,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] operations in
            Task { @MainActor in
                guard let self else { return }
                self.memoryExtractionConversationIDs.remove(conversationID)

                guard isMemoryEnabled(),
                      let operations,
                      !operations.isEmpty else {
                    return
                }

                let currentEntries = self.memoryStore.loadEntries()
                let updatedEntries = ChatMemoryStore.applying(
                    operations,
                    to: currentEntries,
                    snapshotIDs: snapshotIDs,
                    sourceConversationID: conversationID
                )
                if updatedEntries != currentEntries {
                    self.memoryStore.saveEntries(updatedEntries)
                }
            }
        }

        return true
    }

    private static func memoryExtractionSource(from messages: [ChatMessage]) -> (userText: String, assistantText: String)? {
        guard let assistantIndex = messages.lastIndex(where: {
            $0.role == "assistant" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return nil
        }

        let assistantText = messages[assistantIndex].content
        let userText = messages[..<assistantIndex]
            .last(where: { $0.role == "user" })?
            .content ?? ""
        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return (userText, assistantText)
    }

    @MainActor
    private func historySummaryWorkItems(
        from conversations: [AIConversation],
        loadConversation: @MainActor (UUID) -> AIConversation?,
        privateConversationID: UUID?
    ) -> [HistorySummaryWorkItem] {
        let snapshot = historySummaryStore.loadSnapshot()
        return conversations
            .filter { $0.id != privateConversationID }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .compactMap { conversation -> HistorySummaryWorkItem? in
                let loadedConversation = conversation.isIndexOnly
                    ? loadConversation(conversation.id) ?? conversation
                    : conversation
                let fingerprint = ChatMemoryHistoryBatchBuilder.fingerprint(for: loadedConversation)
                guard !snapshot.conversationSummaries.contains(where: {
                    $0.conversationID == loadedConversation.id && $0.fingerprint == fingerprint
                }) else {
                    return nil
                }

                let updateKey = "\(loadedConversation.id.uuidString):\(fingerprint)"
                guard !historySummaryUpdateKeys.contains(updateKey) else { return nil }

                let batches = ChatMemoryHistoryBatchBuilder.makeBatches(for: loadedConversation)
                guard !batches.isEmpty else { return nil }

                return HistorySummaryWorkItem(
                    conversation: loadedConversation,
                    fingerprint: fingerprint,
                    batches: batches
                )
            }
    }

    @MainActor
    private func summarizeHistoryBackfillItem(
        at index: Int,
        workItems: [HistorySummaryWorkItem],
        conversationSummaries: [ChatMemoryHistoryConversationSummary],
        memorySnapshot: [ChatMemoryEntry],
        requestConfiguration: AuxiliaryRequestConfiguration,
        isMemoryEnabled: @escaping @MainActor () -> Bool,
        updateKey: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        guard isMemoryEnabled() else {
            finishHistorySummaryUpdate(
                updateKey,
                onPendingCountChanged: onPendingCountChanged
            )
            return
        }

        guard index < workItems.count else {
            mergeHistoryBackfillSummaries(
                conversationSummaries,
                memorySnapshot: memorySnapshot,
                requestConfiguration: requestConfiguration,
                updateKey: updateKey,
                onPendingCountChanged: onPendingCountChanged
            )
            return
        }

        let workItem = workItems[index]
        summarizeHistoryBackfillBatch(
            at: 0,
            workItem: workItem,
            batchSummaries: [],
            memorySnapshot: memorySnapshot,
            requestConfiguration: requestConfiguration
        ) { [weak self] batchSummaries in
            guard let self else { return }
            var nextConversationSummaries = conversationSummaries
            if !batchSummaries.isEmpty {
                nextConversationSummaries.append(ChatMemoryHistoryConversationSummary(
                    conversationID: workItem.conversation.id,
                    fingerprint: workItem.fingerprint,
                    updatedAt: workItem.conversation.updatedAt,
                    batchSummaries: batchSummaries
                ))
            }

            self.summarizeHistoryBackfillItem(
                at: index + 1,
                workItems: workItems,
                conversationSummaries: nextConversationSummaries,
                memorySnapshot: memorySnapshot,
                requestConfiguration: requestConfiguration,
                isMemoryEnabled: isMemoryEnabled,
                updateKey: updateKey,
                onPendingCountChanged: onPendingCountChanged
            )
        }
    }

    @MainActor
    private func summarizeHistoryBackfillBatch(
        at index: Int,
        workItem: HistorySummaryWorkItem,
        batchSummaries: [ChatMemoryHistoryBatchSummary],
        memorySnapshot: [ChatMemoryEntry],
        requestConfiguration: AuxiliaryRequestConfiguration,
        completion: @escaping @MainActor ([ChatMemoryHistoryBatchSummary]) -> Void
    ) {
        guard index < workItem.batches.count else {
            completion(batchSummaries)
            return
        }

        auxiliaryAIService.summarizeMemoryHistoryBatch(
            memoryEntries: memorySnapshot,
            batch: workItem.batches[index],
            batchCount: workItem.batches.count,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] summary in
            Task { @MainActor in
                guard let self else { return }
                guard let summary else {
                    completion([])
                    return
                }

                self.summarizeHistoryBackfillBatch(
                    at: index + 1,
                    workItem: workItem,
                    batchSummaries: batchSummaries + [summary],
                    memorySnapshot: memorySnapshot,
                    requestConfiguration: requestConfiguration,
                    completion: completion
                )
            }
        }
    }

    @MainActor
    private func mergeHistoryBackfillSummaries(
        _ conversationSummaries: [ChatMemoryHistoryConversationSummary],
        memorySnapshot: [ChatMemoryEntry],
        requestConfiguration: AuxiliaryRequestConfiguration,
        updateKey: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        guard !conversationSummaries.isEmpty else {
            finishHistorySummaryUpdate(
                updateKey,
                onPendingCountChanged: onPendingCountChanged
            )
            return
        }

        var nextSnapshot = historySummaryStore.loadSnapshot()
        let summarizedConversationIDs = Set(conversationSummaries.map(\.conversationID))
        nextSnapshot.conversationSummaries.removeAll {
            summarizedConversationIDs.contains($0.conversationID)
        }
        nextSnapshot.conversationSummaries.append(contentsOf: conversationSummaries)

        auxiliaryAIService.mergeMemoryHistorySummaries(
            memoryEntries: memorySnapshot,
            batchSummaries: nextSnapshot.allBatchSummaries,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    nextSnapshot.result = result
                    nextSnapshot.memorySnapshotEntries = memorySnapshot
                    nextSnapshot.updatedAt = Date()
                    self.historySummaryStore.saveSnapshot(nextSnapshot)
                }
                self.finishHistorySummaryUpdate(
                    updateKey,
                    onPendingCountChanged: onPendingCountChanged
                )
            }
        }
    }

    @MainActor
    private func summarizeHistoryBatch(
        at index: Int,
        batches: [ChatMemoryHistoryBatch],
        batchSummaries: [ChatMemoryHistoryBatchSummary],
        memorySnapshot: [ChatMemoryEntry],
        conversation: AIConversation,
        fingerprint: String,
        requestConfiguration: AuxiliaryRequestConfiguration,
        updateKey: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        guard index < batches.count else {
            mergeHistorySummaries(
                batchSummaries,
                memorySnapshot: memorySnapshot,
                conversation: conversation,
                fingerprint: fingerprint,
                requestConfiguration: requestConfiguration,
                updateKey: updateKey,
                onPendingCountChanged: onPendingCountChanged
            )
            return
        }

        auxiliaryAIService.summarizeMemoryHistoryBatch(
            memoryEntries: memorySnapshot,
            batch: batches[index],
            batchCount: batches.count,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] summary in
            Task { @MainActor in
                guard let self else { return }
                guard let summary else {
                    self.finishHistorySummaryUpdate(
                        updateKey,
                        onPendingCountChanged: onPendingCountChanged
                    )
                    return
                }

                self.summarizeHistoryBatch(
                    at: index + 1,
                    batches: batches,
                    batchSummaries: batchSummaries + [summary],
                    memorySnapshot: memorySnapshot,
                    conversation: conversation,
                    fingerprint: fingerprint,
                    requestConfiguration: requestConfiguration,
                    updateKey: updateKey,
                    onPendingCountChanged: onPendingCountChanged
                )
            }
        }
    }

    @MainActor
    private func mergeHistorySummaries(
        _ batchSummaries: [ChatMemoryHistoryBatchSummary],
        memorySnapshot: [ChatMemoryEntry],
        conversation: AIConversation,
        fingerprint: String,
        requestConfiguration: AuxiliaryRequestConfiguration,
        updateKey: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        var nextSnapshot = historySummaryStore.loadSnapshot()
        nextSnapshot.conversationSummaries.removeAll { $0.conversationID == conversation.id }
        nextSnapshot.conversationSummaries.append(ChatMemoryHistoryConversationSummary(
            conversationID: conversation.id,
            fingerprint: fingerprint,
            updatedAt: conversation.updatedAt,
            batchSummaries: batchSummaries
        ))

        auxiliaryAIService.mergeMemoryHistorySummaries(
            memoryEntries: memorySnapshot,
            batchSummaries: nextSnapshot.allBatchSummaries,
            baseURL: requestConfiguration.baseURL,
            apiFormat: requestConfiguration.apiFormat,
            credentialSet: requestConfiguration.credentialSet,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            reasoningEnabled: requestConfiguration.reasoningEnabled,
            reasoningEffort: requestConfiguration.reasoningEffort
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    nextSnapshot.result = result
                    nextSnapshot.memorySnapshotEntries = memorySnapshot
                    nextSnapshot.updatedAt = Date()
                    self.historySummaryStore.saveSnapshot(nextSnapshot)
                }
                self.finishHistorySummaryUpdate(
                    updateKey,
                    onPendingCountChanged: onPendingCountChanged
                )
            }
        }
    }

    @MainActor
    private func finishHistorySummaryUpdate(
        _ updateKey: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        guard historySummaryUpdateKeys.remove(updateKey) != nil else { return }
        ChatMemoryHistorySummaryStore.setUpdateInProgress(!historySummaryUpdateKeys.isEmpty)
        onPendingCountChanged()
    }
}
