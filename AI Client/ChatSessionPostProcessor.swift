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
        anthropicClaudeCodeImpersonationEnabled: Bool,
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
        anthropicClaudeCodeImpersonationEnabled: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping ([ChatMemoryOperation]?) -> Void
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
        anthropicClaudeCodeImpersonationEnabled: Bool,
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

@MainActor
final class ChatSessionPostProcessor {
    private struct AuxiliaryRequestConfiguration {
        let baseURL: String
        let apiFormat: AIAPIFormat
        let apiKey: String
        let customHeaders: String
        let model: String
        let modelParameters: AIModelConfiguration?
        let anthropicMaxTokens: Int
        let anthropicClaudeCodeImpersonationEnabled: Bool
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?

        init?(configuration: AIConfiguration) {
            let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { return nil }

            baseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            apiFormat = configuration.apiFormat
            apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            customHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
            self.model = model
            modelParameters = configuration.selectedModelConfiguration
            anthropicMaxTokens = configuration.anthropicMaxTokens
            anthropicClaudeCodeImpersonationEnabled = configuration.anthropicClaudeCodeImpersonationEnabled
            reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
            reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil
        }
    }

    private let auxiliaryAIService: ChatSessionAuxiliaryAIServicing
    private let memoryStore: ChatMemoryEntryStoring
    private var memoryExtractionConversationIDs = Set<UUID>()

    init() {
        self.auxiliaryAIService = ChatAuxiliaryAIService()
        self.memoryStore = PersistentChatMemoryEntryStore()
    }

    init(
        auxiliaryAIService: ChatSessionAuxiliaryAIServicing,
        memoryStore: ChatMemoryEntryStoring
    ) {
        self.auxiliaryAIService = auxiliaryAIService
        self.memoryStore = memoryStore
    }

    @discardableResult
    func generateImageContextDescriptionIfNeeded(
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        onDescriptionGenerated: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard !imageAttachments.isEmpty else { return false }

        auxiliaryAIService.generateImageContextDescription(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            apiFormat: apiFormat,
            apiKey: apiKey,
            customHeaders: customHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
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
            apiKey: requestConfiguration.apiKey,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: requestConfiguration.anthropicClaudeCodeImpersonationEnabled,
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
            apiKey: requestConfiguration.apiKey,
            customHeaders: requestConfiguration.customHeaders,
            model: requestConfiguration.model,
            modelParameters: requestConfiguration.modelParameters,
            anthropicMaxTokens: requestConfiguration.anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: requestConfiguration.anthropicClaudeCodeImpersonationEnabled,
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
}
