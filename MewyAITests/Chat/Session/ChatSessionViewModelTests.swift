import XCTest
@testable import MewyAI

@MainActor
final class ChatSessionViewModelTests: XCTestCase {
    func testStartStreamingTurnAppendsMessagesAndRegistersGeneration() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let result = viewModel.startStreamingTurn(ChatSessionViewModel.StreamingTurnStartContext(
            conversationID: conversationID,
            userText: "hello",
            contextMessages: [],
            appendsUserMessage: true,
            systemPrompt: "system",
            usesImageAttachments: true,
            preservesReasoningContext: false,
            maxActiveConversationGenerations: 4
        ))

        guard case .success(let startResult) = result else {
            return XCTFail("Expected streaming turn to start")
        }

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, "user")
        XCTAssertEqual(viewModel.messages[0].content, "hello")
        XCTAssertEqual(viewModel.messages[1].role, "assistant")
        XCTAssertEqual(viewModel.messages[1].content, "")
        XCTAssertEqual(startResult.userMessageIDForImageContext, viewModel.messages[0].id)
        XCTAssertEqual(startResult.assistantMessageID, viewModel.messages[1].id)
        XCTAssertTrue(startResult.generation.service === startResult.service)
        XCTAssertTrue(viewModel.activeConversationGenerations[conversationID] === startResult.generation)
        XCTAssertEqual(viewModel.activeAssistantMessageID, startResult.assistantMessageID)
        XCTAssertTrue(viewModel.isGenerating)
    }

    func testStartStreamingTurnReusesExistingUserMessageIDWhenRegenerating() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let existingUserMessageID = UUID()
        let result = viewModel.startStreamingTurn(ChatSessionViewModel.StreamingTurnStartContext(
            conversationID: conversationID,
            userText: "edited",
            contextMessages: [ChatMessage(id: existingUserMessageID, role: "user", content: "edited")],
            appendsUserMessage: false,
            existingUserMessageID: existingUserMessageID,
            systemPrompt: "system",
            usesImageAttachments: true,
            preservesReasoningContext: false,
            maxActiveConversationGenerations: 4
        ))

        guard case .success(let startResult) = result else {
            return XCTFail("Expected regenerated turn to start")
        }

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].role, "assistant")
        XCTAssertEqual(startResult.userMessageIDForImageContext, existingUserMessageID)
    }

    func testStartStreamingTurnRejectsDuplicateConversationWithoutAppendingMessages() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        _ = viewModel.startStreamingTurn(ChatSessionViewModel.StreamingTurnStartContext(
            conversationID: conversationID,
            userText: "first",
            contextMessages: [],
            appendsUserMessage: true,
            systemPrompt: "system",
            usesImageAttachments: true,
            preservesReasoningContext: false,
            maxActiveConversationGenerations: 4
        ))
        let originalMessages = viewModel.messages

        let result = viewModel.startStreamingTurn(ChatSessionViewModel.StreamingTurnStartContext(
            conversationID: conversationID,
            userText: "second",
            contextMessages: [],
            appendsUserMessage: true,
            systemPrompt: "system",
            usesImageAttachments: true,
            preservesReasoningContext: false,
            maxActiveConversationGenerations: 4
        ))

        XCTAssertEqual(result.failureValue, .alreadyGenerating)
        XCTAssertEqual(viewModel.messages, originalMessages)
    }

    func testStartStreamingTurnRejectsMaxActiveGenerationsWithoutAppendingMessages() {
        let viewModel = ChatSessionViewModel()
        let existingConversationID = UUID()
        let existingAssistantMessageID = UUID()
        viewModel.activeConversationGenerations[existingConversationID] = ActiveConversationGeneration(
            conversationID: existingConversationID,
            assistantMessageID: existingAssistantMessageID,
            service: AIService()
        )

        let result = viewModel.startStreamingTurn(ChatSessionViewModel.StreamingTurnStartContext(
            conversationID: UUID(),
            userText: "blocked",
            contextMessages: [],
            appendsUserMessage: true,
            systemPrompt: "system",
            usesImageAttachments: true,
            preservesReasoningContext: false,
            maxActiveConversationGenerations: 1
        ))

        XCTAssertEqual(result.failureValue, .tooManyActiveRequests(limit: 1))
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testActiveGenerationAccessorsExposeReadOnlySummary() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )

        viewModel.activeConversationGenerations[conversationID] = generation

        XCTAssertTrue(viewModel.activeGeneration(in: conversationID) === generation)
        XCTAssertEqual(viewModel.activeConversationIDs, [conversationID])
        XCTAssertEqual(viewModel.activeConversationGenerationCount, 1)
    }

    func testVisibleAssistantDisplayStateDescribesStreamingMessage() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let otherMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.hasReasoning = true
        generation.hasContent = true
        generation.reasoningIsExpanded = true

        viewModel.beginVisibleGeneration(generation)

        let streamingState = viewModel.visibleAssistantDisplayState(for: assistantMessageID)
        XCTAssertTrue(streamingState.isStreaming)
        XCTAssertTrue(streamingState.hasStreamingReasoning)
        XCTAssertTrue(streamingState.hasStreamingContent)
        XCTAssertNotNil(streamingState.streamingContentChannel)
        XCTAssertNotNil(streamingState.streamingReasoningChannel)
        XCTAssertTrue(viewModel.shouldPublishLiveReasoningUpdate(for: assistantMessageID))
        XCTAssertNotNil(viewModel.liveContentChannel(for: assistantMessageID))
        XCTAssertNotNil(viewModel.liveReasoningChannel(for: assistantMessageID))

        generation.tokenBuffer.appendReasoning("thinking")
        XCTAssertEqual(viewModel.streamingReasoningChunksSnapshot, ["thinking"])

        let otherState = viewModel.visibleAssistantDisplayState(for: otherMessageID)
        XCTAssertFalse(otherState.isStreaming)
        XCTAssertFalse(otherState.hasStreamingReasoning)
        XCTAssertFalse(otherState.hasStreamingContent)
        XCTAssertNil(otherState.streamingContentChannel)
        XCTAssertNil(otherState.streamingReasoningChannel)
        XCTAssertFalse(viewModel.shouldPublishLiveReasoningUpdate(for: otherMessageID))
        XCTAssertNil(viewModel.liveContentChannel(for: otherMessageID))
        XCTAssertNil(viewModel.liveReasoningChannel(for: otherMessageID))
    }

    func testPrepareStreamingTurnBuildsServiceRequestAndStartsGeneration() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let imageAttachment = ChatImageAttachment(
            fileName: "cat.jpg",
            md5: "abc",
            byteCount: 12
        )
        let configuration = AIConfiguration(
            baseURL: "https://api.example.com",
            endpoint: "chat/completions",
            apiFormat: .openAIChatCompletions,
            anthropicMaxTokens: 1234,
            apiKey: "  test-key  ",
            customHeaders: "  X-Test: value  ",
            systemPrompt: "system",
            models: [
                AIModelConfiguration(
                    name: "model-a",
                    supportsReasoning: true,
                    supportsImages: true,
                    supportsTools: true,
                    maxOutputTokens: 222
                )
            ],
            selectedModel: "model-a",
            reasoningEnabled: true,
            reasoningEffort: .high,
            generatesImageContextDescriptions: true
        )

        let result = viewModel.prepareStreamingTurn(ChatSessionViewModel.StreamingTurnPreparationContext(
            conversationID: conversationID,
            userText: "hello",
            imageAttachments: [imageAttachment],
            imageContextDescription: "",
            fileAttachments: [],
            contextMessages: [],
            appendsUserMessage: true,
            existingUserMessageID: nil,
            configuration: configuration,
            systemPromptAppendix: "\nappendix",
            hasActiveMCPServers: false,
            mcpTools: [],
            recallTools: [],
            maxActiveConversationGenerations: 4
        ))

        guard case .success(let preparation) = result else {
            return XCTFail("Expected streaming turn preparation to succeed")
        }

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.content, "hello")
        XCTAssertEqual(preparation.startResult.generation.conversationID, conversationID)
        XCTAssertEqual(preparation.serviceRequest.message, "hello")
        XCTAssertEqual(preparation.serviceRequest.baseURL, "https://api.example.com/chat/completions")
        XCTAssertEqual(preparation.serviceRequest.credentialSet.credentials.first?.secret, "test-key")
        XCTAssertEqual(preparation.serviceRequest.customHeaders, "X-Test: value")
        XCTAssertEqual(preparation.serviceRequest.model, "model-a")
        XCTAssertEqual(preparation.serviceRequest.modelParameters?.maxOutputTokens, 222)
        XCTAssertEqual(preparation.serviceRequest.reasoningEnabled, true)
        XCTAssertEqual(preparation.serviceRequest.reasoningEffort, .high)
        XCTAssertTrue(preparation.serviceRequest.usesImageAttachments)
        XCTAssertTrue(preparation.shouldGenerateImageContextDescription)
    }

    func testPrepareStreamingTurnRejectsMissingBaseURLWithoutAppendingMessages() {
        let viewModel = ChatSessionViewModel()
        let result = viewModel.prepareStreamingTurn(ChatSessionViewModel.StreamingTurnPreparationContext(
            conversationID: UUID(),
            userText: "hello",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            contextMessages: [],
            appendsUserMessage: true,
            existingUserMessageID: nil,
            configuration: AIConfiguration(baseURL: "", endpoint: "", selectedModel: "model-a"),
            systemPromptAppendix: "",
            hasActiveMCPServers: false,
            mcpTools: [],
            recallTools: [],
            maxActiveConversationGenerations: 4
        ))

        XCTAssertEqual(result.preparationFailureValue, .missingBaseURL)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testPrepareStreamingTurnRejectsImageContextWithoutDescriptionForTextModel() {
        let viewModel = ChatSessionViewModel()
        let imageAttachment = ChatImageAttachment(
            fileName: "cat.jpg",
            md5: "abc",
            byteCount: 12
        )
        let configuration = AIConfiguration(
            baseURL: "https://api.example.com",
            endpoint: "chat/completions",
            models: [AIModelConfiguration(name: "text-model", supportsImages: false)],
            selectedModel: "text-model"
        )

        let result = viewModel.prepareStreamingTurn(ChatSessionViewModel.StreamingTurnPreparationContext(
            conversationID: UUID(),
            userText: "continue",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            contextMessages: [
                ChatMessage(
                    role: "user",
                    content: "image",
                    imageAttachments: [imageAttachment]
                )
            ],
            appendsUserMessage: true,
            existingUserMessageID: nil,
            configuration: configuration,
            systemPromptAppendix: "",
            hasActiveMCPServers: false,
            mcpTools: [],
            recallTools: [],
            maxActiveConversationGenerations: 4
        ))

        XCTAssertEqual(result.preparationFailureValue, .contextImageWithoutDescription)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testUpdateVisibleToolExchangesRequiresVisibleActiveGeneration() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        let exchanges = [
            ChatToolExchange(
                assistantContent: "checking",
                toolCalls: [
                    ChatToolCall(
                        id: "call-1",
                        name: "search",
                        displayName: "search",
                        argumentsJSON: "{}"
                    )
                ]
            )
        ]
        viewModel.messages = [ChatMessage(id: assistantMessageID, role: "assistant", content: "")]
        viewModel.beginVisibleGeneration(generation)

        XCTAssertTrue(viewModel.updateVisibleToolExchanges(
            exchanges,
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ))
        XCTAssertEqual(viewModel.messages[0].toolExchanges, exchanges)

        XCTAssertFalse(viewModel.updateVisibleToolExchanges(
            [],
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: UUID()
        ))
        XCTAssertEqual(viewModel.messages[0].toolExchanges, exchanges)
    }

    func testResetStreamingRoundDisplayClearsVisibleAssistantState() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.hasContent = true
        generation.hasReasoning = true
        generation.tokenBuffer.appendContent("pending")
        generation.tokenBuffer.appendReasoning("thinking")
        viewModel.messages = [
            ChatMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "old",
                contentChunks: ["old"],
                reasoningContent: "reason",
                reasoningChunks: ["reason"]
            )
        ]
        viewModel.beginVisibleGeneration(generation)
        viewModel.activeAssistantHasContent = true
        viewModel.activeAssistantHasReasoning = true
        viewModel.activeAssistantDidCollapseReasoningAfterThinking = true

        let effect = viewModel.resetStreamingRoundDisplay(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        )

        XCTAssertEqual(effect, ChatSessionViewModel.StreamingRoundResetEffect(
            isVisibleConversation: true,
            shouldResetLiveContentDisplay: true,
            shouldClearLiveReasoningDisplay: true,
            shouldInvalidateMarkdownCache: true
        ))
        XCTAssertEqual(viewModel.messages[0].content, "")
        XCTAssertEqual(viewModel.messages[0].contentChunks, [])
        XCTAssertEqual(viewModel.messages[0].reasoningContent, "")
        XCTAssertEqual(viewModel.messages[0].reasoningChunks, [])
        XCTAssertFalse(generation.hasContent)
        XCTAssertFalse(generation.hasReasoning)
        XCTAssertFalse(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(generation.tokenBuffer.hasPendingReasoningText)
        XCTAssertFalse(viewModel.activeAssistantHasContent)
        XCTAssertFalse(viewModel.activeAssistantHasReasoning)
        XCTAssertFalse(viewModel.activeAssistantDidCollapseReasoningAfterThinking)
    }

    func testResetStreamingRoundMessageDisplayClearsAssistantMessageFields() {
        let assistantMessageID = UUID()
        var messages = [
            ChatMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "old",
                contentChunks: ["old"],
                reasoningContent: "reason",
                reasoningChunks: ["reason"]
            )
        ]

        XCTAssertTrue(ChatSessionViewModel.resetStreamingRoundMessageDisplay(
            for: assistantMessageID,
            in: &messages
        ))

        XCTAssertEqual(messages[0].content, "")
        XCTAssertEqual(messages[0].contentChunks, [])
        XCTAssertEqual(messages[0].reasoningContent, "")
        XCTAssertEqual(messages[0].reasoningChunks, [])
    }

    func testVisibleAssistantCompletionUsageAndErrorMutationsStayScoped() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let configurationID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.messages = [ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")]
        viewModel.beginVisibleGeneration(generation)

        XCTAssertTrue(viewModel.synchronizeVisibleCompletedAssistantContent(
            "final",
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ))
        XCTAssertEqual(viewModel.messages[0].content, "final")
        XCTAssertFalse(viewModel.synchronizeVisibleCompletedAssistantContent(
            "ignored",
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: UUID()
        ))
        XCTAssertEqual(viewModel.messages[0].content, "final")

        let stampedUsage = ChatSessionViewModel.stampedAssistantUsage(
            ChatUsage(inputTokens: 3, outputTokens: 5),
            modelName: "  model-a  ",
            configurationID: configurationID
        )
        XCTAssertEqual(stampedUsage?.modelName, "model-a")
        XCTAssertEqual(stampedUsage?.configurationID, configurationID)
        XCTAssertNotNil(stampedUsage)

        XCTAssertTrue(viewModel.setVisibleAssistantUsage(
            stampedUsage!,
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ))
        XCTAssertEqual(viewModel.messages[0].usage, stampedUsage)

        XCTAssertTrue(viewModel.setVisibleAssistantErrorContent(
            "Request failed",
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ))
        XCTAssertEqual(viewModel.messages[0].content, "Request failed")
        XCTAssertNil(ChatSessionViewModel.stampedAssistantUsage(
            ChatUsage(),
            modelName: "model-a",
            configurationID: configurationID
        ))
    }

    func testAppendAssistantErrorAppendsMessageAndReturnsCachePayload() {
        let viewModel = ChatSessionViewModel()

        let result = viewModel.appendAssistantError("Request failed")

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].id, result.messageID)
        XCTAssertEqual(viewModel.messages[0].role, "assistant")
        XCTAssertEqual(viewModel.messages[0].content, "Request failed")
        XCTAssertEqual(result.content, "Request failed")
    }

    func testApplyReasoningCollapseAfterThinkingMutatesExpandedMessage() {
        let viewModel = ChatSessionViewModel()
        let assistantMessageID = UUID()
        viewModel.messages = [
            ChatMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "",
                isReasoningExpanded: true
            )
        ]

        XCTAssertTrue(viewModel.applyReasoningCollapseAfterThinking(
            ChatSessionViewModel.ReasoningCollapseEffect(wasReasoningExpanded: false),
            for: assistantMessageID
        ))
        XCTAssertFalse(viewModel.messages[0].isReasoningExpanded)
    }

    func testApplyReasoningCollapseAfterThinkingReportsPreviouslyExpandedLiveState() {
        let viewModel = ChatSessionViewModel()
        let assistantMessageID = UUID()
        viewModel.messages = [
            ChatMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "",
                isReasoningExpanded: false
            )
        ]

        XCTAssertTrue(viewModel.applyReasoningCollapseAfterThinking(
            ChatSessionViewModel.ReasoningCollapseEffect(wasReasoningExpanded: true),
            for: assistantMessageID
        ))
        XCTAssertFalse(viewModel.messages[0].isReasoningExpanded)
        XCTAssertFalse(viewModel.applyReasoningCollapseAfterThinking(
            ChatSessionViewModel.ReasoningCollapseEffect(wasReasoningExpanded: false),
            for: assistantMessageID
        ))
    }

    func testSynchronizeCompletedAssistantContentUpdatesOnlyWhenNeeded() {
        let assistantMessageID = UUID()
        var messages = [
            ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")
        ]

        XCTAssertTrue(ChatSessionViewModel.synchronizeCompletedAssistantContent(
            "final",
            for: assistantMessageID,
            in: &messages
        ))
        XCTAssertEqual(messages[0].content, "final")

        XCTAssertFalse(ChatSessionViewModel.synchronizeCompletedAssistantContent(
            "final",
            for: assistantMessageID,
            in: &messages
        ))
        XCTAssertFalse(ChatSessionViewModel.synchronizeCompletedAssistantContent(
            "",
            for: assistantMessageID,
            in: &messages
        ))
    }

    func testFlushVisiblePendingTokensConsumesBufferAndReportsSideEffects() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.tokenBuffer.appendReasoning("reason")
        generation.tokenBuffer.appendContent(" answer")
        generation.isFlushScheduled = true
        viewModel.messages = [ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")]
        viewModel.beginVisibleGeneration(generation)
        viewModel.isFlushScheduled = true

        let result = viewModel.flushVisiblePendingTokens(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID,
            flushesReasoning: true,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: true
        )

        XCTAssertEqual(result, ChatSessionViewModel.TokenFlushResult(
            messageWasFound: true,
            didConsumeReasoning: true,
            didConsumeContent: true,
            shouldInvalidateMarkdownCache: true,
            shouldRequestAutoScroll: true
        ))
        XCTAssertEqual(viewModel.messages[0].reasoningChunks, ["reason"])
        XCTAssertEqual(viewModel.messages[0].content, "partial answer")
        XCTAssertFalse(generation.tokenBuffer.hasPendingReasoningText)
        XCTAssertFalse(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(generation.isFlushScheduled)
        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertTrue(viewModel.activeAssistantHasContent)
    }

    func testFlushBackgroundPendingTokensUpdatesMessageAndCancelsScheduledFlush() {
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.tokenBuffer.appendReasoning("hidden")
        generation.tokenBuffer.appendContent(" done")
        generation.isFlushScheduled = true
        var messages = [ChatMessage(id: assistantMessageID, role: "assistant", content: "work")]

        let result = ChatSessionViewModel.flushBackgroundPendingTokens(
            from: generation,
            into: &messages,
            flushesReasoning: false
        )

        XCTAssertEqual(result, ChatSessionViewModel.TokenFlushResult(
            messageWasFound: true,
            didConsumeReasoning: false,
            didConsumeContent: true,
            shouldInvalidateMarkdownCache: false,
            shouldRequestAutoScroll: false
        ))
        XCTAssertEqual(messages[0].reasoningChunks, [])
        XCTAssertEqual(messages[0].content, "work done")
        XCTAssertTrue(generation.tokenBuffer.hasPendingReasoningText)
        XCTAssertFalse(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(generation.isFlushScheduled)
    }

    func testScheduleTokenFlushStoresVisibleTaskInViewModel() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.beginVisibleGeneration(generation)

        viewModel.scheduleTokenFlush(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ) { _, _ in }

        XCTAssertTrue(viewModel.isFlushScheduled)
        XCTAssertNotNil(viewModel.flushTask)
        XCTAssertFalse(generation.isFlushScheduled)

        viewModel.cancelVisibleScheduledFlush()
        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertNil(viewModel.flushTask)
    }

    func testScheduleTokenFlushStoresBackgroundTaskOnGeneration() {
        let viewModel = ChatSessionViewModel()
        let visibleConversationID = UUID()
        let backgroundConversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: backgroundConversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.activeConversationGenerations[backgroundConversationID] = generation

        viewModel.scheduleTokenFlush(
            for: assistantMessageID,
            in: backgroundConversationID,
            visibleConversationID: visibleConversationID
        ) { _, _ in }

        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertNil(viewModel.flushTask)
        XCTAssertTrue(generation.isFlushScheduled)
        XCTAssertNotNil(generation.flushTask)

        viewModel.cancelScheduledFlush(
            in: backgroundConversationID,
            visibleConversationID: visibleConversationID
        )
        XCTAssertFalse(generation.isFlushScheduled)
        XCTAssertNil(generation.flushTask)
    }

    func testCancelActiveGenerationCancelsScheduledFlushWithoutRemovingGeneration() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.beginVisibleGeneration(generation)
        viewModel.scheduleTokenFlush(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        ) { _, _ in }

        let cancellation = viewModel.cancelActiveGeneration(
            in: conversationID,
            visibleConversationID: conversationID
        )

        XCTAssertEqual(cancellation, ChatSessionViewModel.ActiveGenerationCancellation(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID
        ))
        XCTAssertNotNil(viewModel.activeConversationGenerations[conversationID])
        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertNil(viewModel.flushTask)
    }

    func testResetVisibleGenerationStateAndMarkIdleClearsVisibleStreamingState() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.hasReasoning = true
        generation.hasContent = true
        viewModel.beginVisibleGeneration(generation)
        viewModel.isFlushScheduled = true

        viewModel.resetVisibleGenerationStateAndMarkIdle()

        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.activeAssistantMessageID)
        XCTAssertFalse(viewModel.activeAssistantHasReasoning)
        XCTAssertFalse(viewModel.activeAssistantHasContent)
        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertTrue(viewModel.liveAssistantDisplays.isEmpty)
    }

    func testReplaceVisibleConversationUpdatesMessagesAndResetsStreamingState() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.messages = [ChatMessage(role: "assistant", content: "old")]
        viewModel.beginVisibleGeneration(generation)
        viewModel.isFlushScheduled = true

        let restoredMessages = [ChatMessage(role: "user", content: "restored")]
        viewModel.replaceVisibleConversation(
            messages: restoredMessages,
            systemPrompt: "system",
            usesImageAttachments: true,
            marksIdle: true
        )

        XCTAssertEqual(viewModel.messages, restoredMessages)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.activeAssistantMessageID)
        XCTAssertFalse(viewModel.isFlushScheduled)
        XCTAssertTrue(viewModel.liveAssistantDisplays.isEmpty)
    }

    func testFinishActiveGenerationRemovesVisibleGenerationAndReportsStoppedState() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.isFlushScheduled = true
        viewModel.beginVisibleGeneration(generation)

        let result = viewModel.finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID,
            marksStopped: true
        )

        XCTAssertEqual(result, ChatSessionViewModel.ActiveGenerationFinishResult(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            shouldMarkStopped: true,
            didCompleteVisibleGeneration: true
        ))
        XCTAssertNil(viewModel.activeConversationGenerations[conversationID])
        XCTAssertFalse(generation.isFlushScheduled)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.activeAssistantMessageID)
        XCTAssertNil(viewModel.liveAssistantDisplays[assistantMessageID])
    }

    func testFinishBackgroundGenerationKeepsVisibleGenerationAttached() {
        let viewModel = ChatSessionViewModel()
        let visibleConversationID = UUID()
        let visibleAssistantMessageID = UUID()
        let backgroundConversationID = UUID()
        let backgroundAssistantMessageID = UUID()
        let visibleGeneration = ActiveConversationGeneration(
            conversationID: visibleConversationID,
            assistantMessageID: visibleAssistantMessageID,
            service: AIService()
        )
        let backgroundGeneration = ActiveConversationGeneration(
            conversationID: backgroundConversationID,
            assistantMessageID: backgroundAssistantMessageID,
            service: AIService()
        )
        viewModel.beginVisibleGeneration(visibleGeneration)
        viewModel.activeConversationGenerations[backgroundConversationID] = backgroundGeneration

        let result = viewModel.finishActiveGeneration(
            for: backgroundAssistantMessageID,
            in: backgroundConversationID,
            visibleConversationID: visibleConversationID,
            marksStopped: false
        )

        XCTAssertEqual(result, ChatSessionViewModel.ActiveGenerationFinishResult(
            conversationID: backgroundConversationID,
            assistantMessageID: backgroundAssistantMessageID,
            shouldMarkStopped: false,
            didCompleteVisibleGeneration: false
        ))
        XCTAssertNil(viewModel.activeConversationGenerations[backgroundConversationID])
        XCTAssertNotNil(viewModel.activeConversationGenerations[visibleConversationID])
        XCTAssertTrue(viewModel.isGenerating)
        XCTAssertEqual(viewModel.activeAssistantMessageID, visibleAssistantMessageID)
    }

    func testVisibleTokensUpdateGenerationStateAndCollapseReasoning() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )

        viewModel.beginVisibleGeneration(generation)
        XCTAssertTrue(viewModel.setReasoningExpansion(true, for: assistantMessageID, in: conversationID))

        let shouldPublishReasoning = viewModel.receiveReasoningToken(
            "thinking",
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        )
        let contentEffect = viewModel.receiveContentToken(
            "answer",
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: conversationID
        )

        XCTAssertTrue(shouldPublishReasoning)
        XCTAssertEqual(generation.tokenBuffer.reasoningChunksSnapshot, ["thinking"])
        XCTAssertTrue(generation.tokenBuffer.hasPendingContentText)
        XCTAssertTrue(viewModel.activeAssistantHasReasoning)
        XCTAssertTrue(viewModel.activeAssistantHasContent)
        XCTAssertFalse(viewModel.activeAssistantReasoningIsExpanded)
        XCTAssertTrue(viewModel.activeAssistantDidCollapseReasoningAfterThinking)
        XCTAssertFalse(generation.reasoningIsExpanded)
        XCTAssertTrue(generation.didCollapseReasoningAfterThinking)
        XCTAssertEqual(
            contentEffect,
            ChatSessionViewModel.ContentTokenEffect(
                shouldAppendLiveContent: true,
                reasoningCollapse: .init(wasReasoningExpanded: true)
            )
        )
    }

    func testBackgroundContentTokenBuffersWithoutLiveDisplayEffect() {
        let viewModel = ChatSessionViewModel()
        let visibleConversationID = UUID()
        let backgroundConversationID = UUID()
        let assistantMessageID = UUID()
        let generation = ActiveConversationGeneration(
            conversationID: backgroundConversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.activeConversationGenerations[backgroundConversationID] = generation

        let effect = viewModel.receiveContentToken(
            "background",
            for: assistantMessageID,
            in: backgroundConversationID,
            visibleConversationID: visibleConversationID
        )

        XCTAssertEqual(
            effect,
            ChatSessionViewModel.ContentTokenEffect(
                shouldAppendLiveContent: false,
                reasoningCollapse: nil
            )
        )
        XCTAssertTrue(generation.hasContent)
        XCTAssertTrue(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(viewModel.activeAssistantHasContent)
    }

    func testClearGeneratedContentClearsAssistantMessage() {
        let viewModel = ChatSessionViewModel()
        let assistantMessageID = UUID()
        viewModel.messages = [
            ChatMessage(role: "user", content: "prompt"),
            ChatMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "answer",
                reasoningContent: "reasoning",
                toolExchanges: [
                    ChatToolExchange(
                        toolCalls: [
                            ChatToolCall(
                                id: "call-1",
                                name: "search",
                                displayName: "Search",
                                argumentsJSON: "{}"
                            )
                        ]
                    )
                ],
                usage: ChatUsage(
                    inputTokens: 1,
                    outputTokens: 2,
                    totalTokens: 3,
                    cacheReadInputTokens: 0,
                    modelName: "test-model",
                    configurationID: UUID()
                ),
                isReasoningExpanded: true
            )
        ]

        XCTAssertTrue(viewModel.clearGeneratedContent(for: assistantMessageID))

        let message = viewModel.messages[1]
        XCTAssertTrue(message.isContentCleared)
        XCTAssertEqual(message.content, "")
        XCTAssertEqual(message.reasoningContent, "")
        XCTAssertEqual(message.toolExchanges, [])
        XCTAssertNil(message.usage)
        XCTAssertFalse(message.isReasoningExpanded)
    }

    func testClearGeneratedContentRejectsUserMessage() {
        let viewModel = ChatSessionViewModel()
        let userMessageID = UUID()
        let message = ChatMessage(id: userMessageID, role: "user", content: "prompt")
        viewModel.messages = [message]

        XCTAssertFalse(viewModel.clearGeneratedContent(for: userMessageID))
        XCTAssertEqual(viewModel.messages, [message])
    }

    func testClearGeneratedContentRejectsMissingMessage() {
        let viewModel = ChatSessionViewModel()
        viewModel.messages = [ChatMessage(role: "assistant", content: "answer")]
        let originalMessages = viewModel.messages

        XCTAssertFalse(viewModel.clearGeneratedContent(for: UUID()))
        XCTAssertEqual(viewModel.messages, originalMessages)
    }

    func testClearGeneratedContentClearsVisibleLiveDisplayState() {
        let viewModel = ChatSessionViewModel()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        viewModel.messages = [
            ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")
        ]
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        viewModel.beginVisibleGeneration(generation)
        viewModel.activeAssistantHasContent = true

        XCTAssertTrue(viewModel.clearGeneratedContent(for: assistantMessageID))

        XCTAssertNil(viewModel.activeAssistantMessageID)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertFalse(viewModel.visibleAssistantDisplayState(for: assistantMessageID).isStreaming)
        XCTAssertTrue(viewModel.liveAssistantDisplays.isEmpty)
    }
}

private extension Result where Success == ChatSessionViewModel.StreamingTurnStartResult,
                               Failure == ChatSessionViewModel.StreamingTurnStartFailure {
    var failureValue: Failure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

private extension Result where Success == ChatSessionViewModel.StreamingTurnPreparation,
                               Failure == ChatSessionViewModel.StreamingTurnPreparationFailure {
    var preparationFailureValue: Failure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}
