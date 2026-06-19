import XCTest
@testable import MewyAI

@MainActor
final class ChatSessionPostProcessorTests: XCTestCase {
    func testGenerateTitleRequestsEligibleConversationAndReturnsTitle() async {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        auxiliaryService.nextTitle = "Refactor Plan"
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: FakePostProcessorMemoryStore()
        )
        let conversationID = UUID()
        let conversation = AIConversation(
            id: conversationID,
            messages: [
                ChatMessage(role: "user", content: "拆一下 ContentView"),
                ChatMessage(role: "assistant", content: "先搬独立类型，再抽 ViewModel。")
            ]
        )
        let completed = expectation(description: "title callback")
        var generatedTitle: (UUID, String)?

        XCTAssertTrue(processor.generateTitleIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            privateConversationID: nil
        ) { conversationID, title in
            generatedTitle = (conversationID, title)
            completed.fulfill()
        })

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(auxiliaryService.titleRequests.count, 1)
        XCTAssertEqual(auxiliaryService.titleRequests[0].model, "model-a")
        XCTAssertEqual(generatedTitle?.0, conversationID)
        XCTAssertEqual(generatedTitle?.1, "Refactor Plan")
    }

    func testGenerateTitleSkipsPrivateAndAlreadyGeneratedConversations() {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: FakePostProcessorMemoryStore()
        )
        let privateConversationID = UUID()
        let privateConversation = AIConversation(
            id: privateConversationID,
            messages: [
                ChatMessage(role: "user", content: "private"),
                ChatMessage(role: "assistant", content: "answer")
            ]
        )
        let titledConversation = AIConversation(
            messages: [
                ChatMessage(role: "user", content: "topic"),
                ChatMessage(role: "assistant", content: "answer")
            ],
            hasGeneratedTitle: true
        )

        XCTAssertFalse(processor.generateTitleIfNeeded(
            for: privateConversation,
            configuration: makeConfiguration(),
            privateConversationID: privateConversationID
        ) { _, _ in
            XCTFail("Private conversations should not request titles")
        })
        XCTAssertFalse(processor.generateTitleIfNeeded(
            for: titledConversation,
            configuration: makeConfiguration(),
            privateConversationID: nil
        ) { _, _ in
            XCTFail("Already titled conversations should not request titles")
        })
        XCTAssertTrue(auxiliaryService.titleRequests.isEmpty)
    }

    func testExtractMemoriesDeduplicatesInFlightRequestsAndSavesAppliedOperations() async {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let memoryStore = FakePostProcessorMemoryStore(entries: [
            ChatMemoryEntry(content: "User works on iOS apps")
        ])
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: memoryStore
        )
        let conversationID = UUID()
        let conversation = AIConversation(
            id: conversationID,
            messages: [
                ChatMessage(role: "user", content: "Remember that I prefer SwiftUI."),
                ChatMessage(role: "assistant", content: "Got it.")
            ]
        )
        let saved = expectation(description: "memory saved")
        memoryStore.onSave = {
            saved.fulfill()
        }

        XCTAssertTrue(processor.extractMemoriesIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: nil
        ))
        XCTAssertFalse(processor.extractMemoriesIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: nil
        ))
        XCTAssertEqual(auxiliaryService.memoryRequests.count, 1)

        auxiliaryService.completeMemoryExtraction(with: [
            ChatMemoryOperation(action: .add, index: nil, content: "User prefers SwiftUI")
        ])
        await fulfillment(of: [saved], timeout: 5)

        XCTAssertEqual(memoryStore.savedEntries?.map(\.content), [
            "User works on iOS apps",
            "User prefers SwiftUI"
        ])
        XCTAssertEqual(memoryStore.savedEntries?.last?.sourceConversationID, conversationID)
    }

    func testUpdateHistorySummaryProcessesChangedConversationAndSavesSnapshot() async throws {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let memoryEntry = ChatMemoryEntry(content: "User works on iOS apps")
        let memoryStore = FakePostProcessorMemoryStore(entries: [memoryEntry])
        let historySummaryStore = FakePostProcessorHistorySummaryStore()
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: memoryStore,
            historySummaryStore: historySummaryStore
        )
        let conversationID = UUID()
        let conversation = AIConversation(
            id: conversationID,
            title: "SwiftUI Preferences",
            messages: [
                ChatMessage(role: "user", content: "Please remember I prefer SwiftUI-native UI fixes."),
                ChatMessage(role: "assistant", content: "Noted.")
            ],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let mergeRequested = expectation(description: "history merge requested")
        let pendingFinished = expectation(description: "pending history update finished")
        let saved = expectation(description: "history summary snapshot saved")
        var pendingCounts = [Int]()
        auxiliaryService.onHistoryMergeRequest = {
            mergeRequested.fulfill()
        }
        historySummaryStore.onSave = {
            saved.fulfill()
        }

        XCTAssertTrue(processor.updateHistorySummaryIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: nil
        ) {
            pendingCounts.append(processor.activeHistorySummaryUpdateCount)
            if pendingCounts.count == 2 {
                pendingFinished.fulfill()
            }
        })

        XCTAssertEqual(processor.activeHistorySummaryUpdateCount, 1)
        XCTAssertEqual(auxiliaryService.historyBatchRequests.count, 1)
        XCTAssertEqual(auxiliaryService.historyBatchRequests[0].memoryEntries, [memoryEntry])
        XCTAssertEqual(auxiliaryService.historyBatchRequests[0].batchCount, 1)
        XCTAssertTrue(auxiliaryService.historyBatchRequests[0].batch.text.contains("SwiftUI-native UI fixes"))

        auxiliaryService.completeHistoryBatch(with: ChatMemoryHistoryBatchSummary(
            batchIndex: 0,
            summary: "Conversation says the user prefers SwiftUI-native UI fixes.",
            facts: ["User prefers SwiftUI-native UI fixes."]
        ))
        await fulfillment(of: [mergeRequested], timeout: 5)

        XCTAssertEqual(auxiliaryService.historyMergeRequests.count, 1)
        XCTAssertEqual(auxiliaryService.historyMergeRequests[0].memoryEntries, [memoryEntry])
        XCTAssertEqual(auxiliaryService.historyMergeRequests[0].batchSummaries.count, 1)

        let result = ChatMemoryHistorySummaryResult(
            sections: [
                ChatMemorySummarySection(
                    title: "Preferences",
                    body: "User prefers SwiftUI-native UI fixes."
                )
            ],
            operations: [
                ChatMemoryOperation(
                    action: .add,
                    index: nil,
                    content: "User prefers SwiftUI-native UI fixes."
                )
            ]
        )
        auxiliaryService.completeHistoryMerge(with: result)
        await fulfillment(of: [saved, pendingFinished], timeout: 5)

        let snapshot = try XCTUnwrap(historySummaryStore.savedSnapshot)
        XCTAssertEqual(snapshot.conversationSummaries.count, 1)
        XCTAssertEqual(snapshot.conversationSummaries[0].conversationID, conversationID)
        XCTAssertEqual(snapshot.conversationSummaries[0].fingerprint, ChatMemoryHistoryBatchBuilder.fingerprint(for: conversation))
        XCTAssertEqual(snapshot.conversationSummaries[0].batchSummaries.count, 1)
        XCTAssertEqual(snapshot.result, result)
        XCTAssertEqual(snapshot.memorySnapshotEntries, [memoryEntry])
        XCTAssertEqual(pendingCounts, [1, 0])
        XCTAssertEqual(processor.activeHistorySummaryUpdateCount, 0)
    }

    func testUpdateHistorySummarySkipsDisabledPrivateAndAlreadyProcessedConversation() {
        let conversationID = UUID()
        let conversation = AIConversation(
            id: conversationID,
            messages: [
                ChatMessage(role: "user", content: "Remember this history fact."),
                ChatMessage(role: "assistant", content: "Stored.")
            ],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let fingerprint = ChatMemoryHistoryBatchBuilder.fingerprint(for: conversation)
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let historySummaryStore = FakePostProcessorHistorySummaryStore(snapshot: ChatMemoryHistorySummarySnapshot(
            conversationSummaries: [
                ChatMemoryHistoryConversationSummary(
                    conversationID: conversationID,
                    fingerprint: fingerprint,
                    updatedAt: conversation.updatedAt,
                    batchSummaries: [
                        ChatMemoryHistoryBatchSummary(
                            batchIndex: 1,
                            summary: "Already processed.",
                            facts: []
                        )
                    ]
                )
            ]
        ))
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: FakePostProcessorMemoryStore(),
            historySummaryStore: historySummaryStore
        )

        XCTAssertFalse(processor.updateHistorySummaryIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { false },
            privateConversationID: nil
        ) {
            XCTFail("Disabled memory should not change pending state")
        })
        XCTAssertFalse(processor.updateHistorySummaryIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: conversationID
        ) {
            XCTFail("Private conversations should not update history summary")
        })
        XCTAssertFalse(processor.updateHistorySummaryIfNeeded(
            for: conversation,
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: nil
        ) {
            XCTFail("Unchanged conversations should not update history summary")
        })
        XCTAssertTrue(auxiliaryService.historyBatchRequests.isEmpty)
        XCTAssertTrue(auxiliaryService.historyMergeRequests.isEmpty)
    }

    func testUpdateMissingHistorySummariesBackfillsExistingConversationsAndMergesOnce() async throws {
        ChatMemoryHistorySummaryStore.setUpdateInProgress(false)
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let memoryEntry = ChatMemoryEntry(content: "User works on iOS apps")
        let memoryStore = FakePostProcessorMemoryStore(entries: [memoryEntry])
        let alreadyProcessed = AIConversation(
            messages: [
                ChatMessage(role: "user", content: "already summarized"),
                ChatMessage(role: "assistant", content: "done")
            ],
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        let alreadyProcessedSummary = ChatMemoryHistoryConversationSummary(
            conversationID: alreadyProcessed.id,
            fingerprint: ChatMemoryHistoryBatchBuilder.fingerprint(for: alreadyProcessed),
            updatedAt: alreadyProcessed.updatedAt,
            batchSummaries: [
                ChatMemoryHistoryBatchSummary(
                    batchIndex: 1,
                    summary: "Existing summary.",
                    facts: ["Existing fact."]
                )
            ]
        )
        let historySummaryStore = FakePostProcessorHistorySummaryStore(snapshot: ChatMemoryHistorySummarySnapshot(
            conversationSummaries: [alreadyProcessedSummary]
        ))
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: memoryStore,
            historySummaryStore: historySummaryStore
        )
        let indexOnlyID = UUID()
        let indexOnlyConversation = AIConversation(
            id: indexOnlyID,
            title: "Index Only",
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 300),
            indexedMessageCount: 2
        )
        let loadedConversation = AIConversation(
            id: indexOnlyID,
            title: "Index Only",
            messages: [
                ChatMessage(role: "user", content: "I want history summaries to backfill existing chats."),
                ChatMessage(role: "assistant", content: "Understood.")
            ],
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let secondConversation = AIConversation(
            title: "Second",
            messages: [
                ChatMessage(role: "user", content: "I prefer incremental updates."),
                ChatMessage(role: "assistant", content: "Noted.")
            ],
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let secondBatchRequested = expectation(description: "second backfill batch requested")
        let mergeRequested = expectation(description: "backfill merge requested")
        let saved = expectation(description: "backfill snapshot saved")
        let pendingFinished = expectation(description: "backfill pending finished")
        var pendingCounts = [Int]()
        auxiliaryService.onHistoryBatchRequest = {
            if auxiliaryService.historyBatchRequests.count == 2 {
                secondBatchRequested.fulfill()
            }
        }
        auxiliaryService.onHistoryMergeRequest = {
            mergeRequested.fulfill()
        }
        historySummaryStore.onSave = {
            saved.fulfill()
        }

        XCTAssertTrue(processor.updateMissingHistorySummariesIfNeeded(
            for: [alreadyProcessed, secondConversation, indexOnlyConversation],
            loadConversation: { id in id == indexOnlyID ? loadedConversation : nil },
            configuration: makeConfiguration(),
            isMemoryEnabled: { true },
            privateConversationID: nil
        ) {
            pendingCounts.append(processor.activeHistorySummaryUpdateCount)
            if pendingCounts.count == 2 {
                pendingFinished.fulfill()
            }
        })

        XCTAssertTrue(ChatMemoryHistorySummaryStore.isUpdateInProgress)
        XCTAssertEqual(processor.activeHistorySummaryUpdateCount, 1)
        XCTAssertEqual(auxiliaryService.historyBatchRequests.count, 1)
        XCTAssertTrue(auxiliaryService.historyBatchRequests[0].batch.text.contains("backfill existing chats"))

        auxiliaryService.completeHistoryBatch(with: ChatMemoryHistoryBatchSummary(
            batchIndex: 0,
            summary: "Loaded index-only conversation summary.",
            facts: ["User wants existing chats backfilled."]
        ))
        await fulfillment(of: [secondBatchRequested], timeout: 5)

        XCTAssertEqual(auxiliaryService.historyBatchRequests.count, 2)
        XCTAssertTrue(auxiliaryService.historyBatchRequests[1].batch.text.contains("incremental updates"))

        auxiliaryService.completeHistoryBatch(with: ChatMemoryHistoryBatchSummary(
            batchIndex: 0,
            summary: "Second conversation summary.",
            facts: ["User prefers incremental updates."]
        ))
        await fulfillment(of: [mergeRequested], timeout: 5)

        XCTAssertEqual(auxiliaryService.historyMergeRequests.count, 1)
        XCTAssertEqual(auxiliaryService.historyMergeRequests[0].batchSummaries.count, 3)

        let result = ChatMemoryHistorySummaryResult(
            sections: [
                ChatMemorySummarySection(
                    title: "History",
                    body: "Existing chats were backfilled incrementally."
                )
            ],
            operations: []
        )
        auxiliaryService.completeHistoryMerge(with: result)
        await fulfillment(of: [saved, pendingFinished], timeout: 5)

        let snapshot = try XCTUnwrap(historySummaryStore.savedSnapshot)
        XCTAssertEqual(Set(snapshot.conversationSummaries.map(\.conversationID)), Set([
            alreadyProcessed.id,
            indexOnlyID,
            secondConversation.id
        ]))
        XCTAssertEqual(snapshot.result, result)
        XCTAssertEqual(snapshot.memorySnapshotEntries, [memoryEntry])
        XCTAssertEqual(pendingCounts, [1, 0])
        XCTAssertEqual(processor.activeHistorySummaryUpdateCount, 0)
        XCTAssertFalse(ChatMemoryHistorySummaryStore.isUpdateInProgress)
    }

    func testGenerateImageContextDescriptionRequestsDescriptionAndTrimsResult() async {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        auxiliaryService.nextImageDescription = "  screenshot with settings panel  "
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: FakePostProcessorMemoryStore()
        )
        let attachment = ChatImageAttachment(dataURL: "data:image/png;base64,abc")
        let completed = expectation(description: "image description generated")
        var generatedDescription: String?

        XCTAssertTrue(processor.generateImageContextDescriptionIfNeeded(
            imageAttachments: [attachment],
            baseURL: "https://example.com/chat/completions",
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "model-a",
            modelParameters: nil,
            anthropicMaxTokens: 1234,
            anthropicClaudeCodeImpersonationEnabled: false,
            reasoningEnabled: true,
            reasoningEffort: .high
        ) { description in
            generatedDescription = description
            completed.fulfill()
        })

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(auxiliaryService.imageDescriptionRequests.count, 1)
        XCTAssertEqual(auxiliaryService.imageDescriptionRequests[0].imageAttachments, [attachment])
        XCTAssertEqual(auxiliaryService.imageDescriptionRequests[0].model, "model-a")
        XCTAssertEqual(generatedDescription, "screenshot with settings panel")
    }

    func testGenerateImageContextDescriptionSkipsEmptyAttachments() {
        let auxiliaryService = FakePostProcessorAuxiliaryAIService()
        let processor = ChatSessionPostProcessor(
            auxiliaryAIService: auxiliaryService,
            memoryStore: FakePostProcessorMemoryStore()
        )

        XCTAssertFalse(processor.generateImageContextDescriptionIfNeeded(
            imageAttachments: [],
            baseURL: "https://example.com/chat/completions",
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "model-a",
            modelParameters: nil,
            anthropicMaxTokens: 1234,
            anthropicClaudeCodeImpersonationEnabled: false,
            reasoningEnabled: true,
            reasoningEffort: .high
        ) { _ in
            XCTFail("Empty image attachments should not request descriptions")
        })
        XCTAssertTrue(auxiliaryService.imageDescriptionRequests.isEmpty)
    }

    private func makeConfiguration(selectedModel: String = "model-a") -> AIConfiguration {
        AIConfiguration(
            baseURL: "https://example.com",
            endpoint: "chat/completions",
            apiFormat: .openAIChatCompletions,
            anthropicMaxTokens: 1234,
            customHeaders: "X-Test: 1",
            models: [
                AIModelConfiguration(name: "model-a", supportsReasoning: true)
            ],
            selectedModel: selectedModel,
            reasoningEnabled: true,
            reasoningEffort: .high
        )
    }
}

@MainActor
private final class FakePostProcessorAuxiliaryAIService: ChatSessionAuxiliaryAIServicing {
    struct TitleRequest {
        let messages: [ChatMessage]
        let baseURL: String
        let model: String
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?
    }

    struct MemoryRequest {
        let memoryEntries: [ChatMemoryEntry]
        let userText: String
        let assistantText: String
        let model: String
    }

    struct ImageDescriptionRequest {
        let imageAttachments: [ChatImageAttachment]
        let baseURL: String
        let model: String
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?
    }

    struct HistoryBatchRequest {
        let memoryEntries: [ChatMemoryEntry]
        let batch: ChatMemoryHistoryBatch
        let batchCount: Int
        let model: String
    }

    struct HistoryMergeRequest {
        let memoryEntries: [ChatMemoryEntry]
        let batchSummaries: [ChatMemoryHistoryBatchSummary]
        let model: String
    }

    var nextTitle: String?
    var nextImageDescription: String?
    var onHistoryBatchRequest: (() -> Void)?
    var onHistoryMergeRequest: (() -> Void)?
    var titleRequests = [TitleRequest]()
    var memoryRequests = [MemoryRequest]()
    var imageDescriptionRequests = [ImageDescriptionRequest]()
    var historyBatchRequests = [HistoryBatchRequest]()
    var historyMergeRequests = [HistoryMergeRequest]()
    private var pendingMemoryCompletion: (([ChatMemoryOperation]?) -> Void)?
    private var pendingHistoryBatchCompletion: ((ChatMemoryHistoryBatchSummary?) -> Void)?
    private var pendingHistoryMergeCompletion: ((ChatMemoryHistorySummaryResult?) -> Void)?

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
    ) {
        titleRequests.append(TitleRequest(
            messages: messages,
            baseURL: baseURL,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ))
        completion(nextTitle)
    }

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
    ) {
        memoryRequests.append(MemoryRequest(
            memoryEntries: memoryEntries,
            userText: userText,
            assistantText: assistantText,
            model: model
        ))
        pendingMemoryCompletion = completion
    }

    func completeMemoryExtraction(with operations: [ChatMemoryOperation]?) {
        let completion = pendingMemoryCompletion
        pendingMemoryCompletion = nil
        completion?(operations)
    }

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
        anthropicClaudeCodeImpersonationEnabled: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistoryBatchSummary?) -> Void
    ) {
        historyBatchRequests.append(HistoryBatchRequest(
            memoryEntries: memoryEntries,
            batch: batch,
            batchCount: batchCount,
            model: model
        ))
        pendingHistoryBatchCompletion = completion
        onHistoryBatchRequest?()
    }

    func completeHistoryBatch(with summary: ChatMemoryHistoryBatchSummary?) {
        let completion = pendingHistoryBatchCompletion
        pendingHistoryBatchCompletion = nil
        completion?(summary)
    }

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
        anthropicClaudeCodeImpersonationEnabled: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (ChatMemoryHistorySummaryResult?) -> Void
    ) {
        historyMergeRequests.append(HistoryMergeRequest(
            memoryEntries: memoryEntries,
            batchSummaries: batchSummaries,
            model: model
        ))
        pendingHistoryMergeCompletion = completion
        onHistoryMergeRequest?()
    }

    func completeHistoryMerge(with result: ChatMemoryHistorySummaryResult?) {
        let completion = pendingHistoryMergeCompletion
        pendingHistoryMergeCompletion = nil
        completion?(result)
    }

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
    ) {
        imageDescriptionRequests.append(ImageDescriptionRequest(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ))
        completion(nextImageDescription)
    }
}

private final class FakePostProcessorHistorySummaryStore: ChatMemoryHistorySummaryStoring {
    private var snapshot: ChatMemoryHistorySummarySnapshot
    var savedSnapshot: ChatMemoryHistorySummarySnapshot?
    var onSave: (() -> Void)?

    init(snapshot: ChatMemoryHistorySummarySnapshot = ChatMemoryHistorySummarySnapshot()) {
        self.snapshot = snapshot
    }

    func loadSnapshot() -> ChatMemoryHistorySummarySnapshot {
        savedSnapshot ?? snapshot
    }

    func saveSnapshot(_ snapshot: ChatMemoryHistorySummarySnapshot) -> Bool {
        self.snapshot = snapshot
        savedSnapshot = snapshot
        onSave?()
        return true
    }
}

private final class FakePostProcessorMemoryStore: ChatMemoryEntryStoring {
    private var entries: [ChatMemoryEntry]
    var savedEntries: [ChatMemoryEntry]?
    var onSave: (() -> Void)?

    init(entries: [ChatMemoryEntry] = []) {
        self.entries = entries
    }

    func loadEntries() -> [ChatMemoryEntry] {
        savedEntries ?? entries
    }

    func saveEntries(_ entries: [ChatMemoryEntry]) -> Bool {
        savedEntries = entries
        onSave?()
        return true
    }
}
