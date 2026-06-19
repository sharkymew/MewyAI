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

    var nextTitle: String?
    var nextImageDescription: String?
    var titleRequests = [TitleRequest]()
    var memoryRequests = [MemoryRequest]()
    var imageDescriptionRequests = [ImageDescriptionRequest]()
    private var pendingMemoryCompletion: (([ChatMemoryOperation]?) -> Void)?

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
