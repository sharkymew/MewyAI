import Foundation
import Observation

@MainActor
@Observable
final class ChatSessionViewModel {
    struct ReasoningCollapseEffect: Equatable {
        let wasReasoningExpanded: Bool
    }

    struct ContentTokenEffect: Equatable {
        let shouldAppendLiveContent: Bool
        let reasoningCollapse: ReasoningCollapseEffect?
    }

    struct StreamingRoundResetEffect: Equatable {
        let isVisibleConversation: Bool
        let shouldResetLiveContentDisplay: Bool
        let shouldClearLiveReasoningDisplay: Bool
        let shouldInvalidateMarkdownCache: Bool
    }

    struct TokenFlushResult: Equatable {
        let messageWasFound: Bool
        let didConsumeReasoning: Bool
        let didConsumeContent: Bool
        let shouldInvalidateMarkdownCache: Bool
        let shouldRequestAutoScroll: Bool
    }

    struct AssistantErrorAppendResult: Equatable {
        let messageID: UUID
        let content: String
    }

    struct VisibleAssistantDisplayState {
        let isStreaming: Bool
        let hasStreamingReasoning: Bool
        let hasStreamingContent: Bool
        let streamingContentChannel: StreamingTextUpdateChannel?
        let streamingReasoningChannel: StreamingTextUpdateChannel?
    }

    struct ActiveGenerationCancellation: Equatable {
        let conversationID: UUID
        let assistantMessageID: UUID
    }

    struct ActiveGenerationFinishResult: Equatable {
        let conversationID: UUID
        let assistantMessageID: UUID
        let shouldMarkStopped: Bool
        let didCompleteVisibleGeneration: Bool
    }

    struct StreamingTurnStartContext {
        let conversationID: UUID
        let userText: String
        let imageAttachments: [ChatImageAttachment]
        let imageContextDescription: String
        let fileAttachments: [ChatFileAttachment]
        let contextMessages: [ChatMessage]
        let appendsUserMessage: Bool
        let existingUserMessageID: UUID?
        let systemPrompt: String
        let usesImageAttachments: Bool
        let preservesReasoningContext: Bool
        let maxActiveConversationGenerations: Int

        init(
            conversationID: UUID,
            userText: String,
            imageAttachments: [ChatImageAttachment] = [],
            imageContextDescription: String = "",
            fileAttachments: [ChatFileAttachment] = [],
            contextMessages: [ChatMessage],
            appendsUserMessage: Bool,
            existingUserMessageID: UUID? = nil,
            systemPrompt: String,
            usesImageAttachments: Bool,
            preservesReasoningContext: Bool,
            maxActiveConversationGenerations: Int
        ) {
            self.conversationID = conversationID
            self.userText = userText
            self.imageAttachments = imageAttachments
            self.imageContextDescription = imageContextDescription
            self.fileAttachments = fileAttachments
            self.contextMessages = contextMessages
            self.appendsUserMessage = appendsUserMessage
            self.existingUserMessageID = existingUserMessageID
            self.systemPrompt = systemPrompt
            self.usesImageAttachments = usesImageAttachments
            self.preservesReasoningContext = preservesReasoningContext
            self.maxActiveConversationGenerations = maxActiveConversationGenerations
        }
    }

    enum StreamingTurnStartFailure: Error, Equatable {
        case alreadyGenerating
        case tooManyActiveRequests(limit: Int)
    }

    struct StreamingTurnStartResult {
        let service: AIService
        let generation: ActiveConversationGeneration
        let assistantMessageID: UUID
        let userMessageIDForImageContext: UUID?
    }

    struct StreamingServiceRequest {
        let message: String
        let imageAttachments: [ChatImageAttachment]
        let imageContextDescription: String
        let fileAttachments: [ChatFileAttachment]
        let baseURL: String
        let apiFormat: AIAPIFormat
        let credentialSet: AIProviderCredentialSet
        let customHeaders: String
        let model: String
        let modelParameters: AIModelConfiguration?
        let anthropicMaxTokens: Int
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?
        let usesImageAttachments: Bool
        let agentTools: [AgentToolDefinition]
    }

    struct StreamingEventHandlers {
        let toolExecutor: (@MainActor (AgentToolCallRequest) async -> AgentToolCallResult)?
        let onToolExchangesUpdated: @MainActor @Sendable ([ChatToolExchange]) -> Void
        let onToolRoundReset: @MainActor @Sendable () -> Void
        let isReasoningDisplayActive: @MainActor @Sendable () -> Bool
        let onReasoningToken: @MainActor @Sendable (String) -> Void
        let onContentToken: @MainActor @Sendable (String) -> Void
        let onComplete: @MainActor @Sendable (_ contentText: String, _ usage: ChatUsage?) -> Void
        let onError: @MainActor @Sendable (String) -> Void
    }

    struct StreamingTurnPreparationContext {
        let conversationID: UUID?
        let userText: String
        let imageAttachments: [ChatImageAttachment]
        let imageContextDescription: String
        let fileAttachments: [ChatFileAttachment]
        let contextMessages: [ChatMessage]
        let appendsUserMessage: Bool
        let existingUserMessageID: UUID?
        let configuration: AIConfiguration
        let systemPromptAppendix: String
        let hasActiveMCPServers: Bool
        let mcpTools: [AgentToolDefinition]
        let recallTools: [AgentToolDefinition]
        let knowledgeTools: [AgentToolDefinition]
        let maxActiveConversationGenerations: Int

        init(
            conversationID: UUID?,
            userText: String,
            imageAttachments: [ChatImageAttachment],
            imageContextDescription: String,
            fileAttachments: [ChatFileAttachment],
            contextMessages: [ChatMessage],
            appendsUserMessage: Bool,
            existingUserMessageID: UUID?,
            configuration: AIConfiguration,
            systemPromptAppendix: String,
            hasActiveMCPServers: Bool,
            mcpTools: [AgentToolDefinition],
            recallTools: [AgentToolDefinition],
            knowledgeTools: [AgentToolDefinition] = [],
            maxActiveConversationGenerations: Int
        ) {
            self.conversationID = conversationID
            self.userText = userText
            self.imageAttachments = imageAttachments
            self.imageContextDescription = imageContextDescription
            self.fileAttachments = fileAttachments
            self.contextMessages = contextMessages
            self.appendsUserMessage = appendsUserMessage
            self.existingUserMessageID = existingUserMessageID
            self.configuration = configuration
            self.systemPromptAppendix = systemPromptAppendix
            self.hasActiveMCPServers = hasActiveMCPServers
            self.mcpTools = mcpTools
            self.recallTools = recallTools
            self.knowledgeTools = knowledgeTools
            self.maxActiveConversationGenerations = maxActiveConversationGenerations
        }
    }

    enum StreamingTurnPreparationFailure: Error, Equatable {
        case emptyMessage
        case vertexMCPUnsupported
        case modelToolsUnsupported
        case noMCPTools
        case imageWithoutDescription
        case contextImageWithoutDescription
        case missingBaseURL
        case missingModel
        case missingConversation
        case alreadyGenerating
        case tooManyActiveRequests(limit: Int)
    }

    struct StreamingTurnPreparation {
        let startResult: StreamingTurnStartResult
        let serviceRequest: StreamingServiceRequest
        let shouldGenerateImageContextDescription: Bool
    }

    @ObservationIgnored
    let aiService = AIService()

    var messages: [ChatMessage] = []
    var pendingToolApproval: PendingToolApproval?
    var isGenerating = false
    var streamingTokenBuffer = StreamingTokenBuffer()
    var activeAssistantHasReasoning = false
    var activeAssistantHasContent = false
    var activeAssistantReasoningIsExpanded = false
    var activeAssistantDidCollapseReasoningAfterThinking = false
    var liveAssistantDisplays: [UUID: AssistantLiveDisplay] = [:]
    var isFlushScheduled = false
    var activeConversationGenerations: [UUID: ActiveConversationGeneration] = [:]
    var activeAssistantMessageID: UUID?

    @ObservationIgnored
    var toolApprovalContinuation: CheckedContinuation<Bool, Never>?

    @ObservationIgnored
    var flushTask: Task<Void, Never>?

    func requestToolApproval(toolName: String, arguments: String) async -> Bool {
        await withCheckedContinuation { continuation in
            toolApprovalContinuation?.resume(returning: false)
            toolApprovalContinuation = continuation
            pendingToolApproval = PendingToolApproval(toolName: toolName, arguments: arguments)
        }
    }

    func resolveToolApproval(_ isAllowed: Bool) {
        let continuation = toolApprovalContinuation
        toolApprovalContinuation = nil
        pendingToolApproval = nil
        continuation?.resume(returning: isAllowed)
    }

    func startStreamingTurn(
        _ context: StreamingTurnStartContext
    ) -> Result<StreamingTurnStartResult, StreamingTurnStartFailure> {
        guard activeConversationGenerations[context.conversationID] == nil else {
            return .failure(.alreadyGenerating)
        }

        guard activeConversationGenerations.count < context.maxActiveConversationGenerations else {
            return .failure(.tooManyActiveRequests(limit: context.maxActiveConversationGenerations))
        }

        let requestService = AIService()
        requestService.resetConversation(
            with: context.contextMessages,
            systemPrompt: context.systemPrompt,
            usesImageAttachments: context.usesImageAttachments,
            preservesReasoningContext: context.preservesReasoningContext
        )
        prepareForVisibleGenerationStart()

        var userMessageIDForImageContext = context.existingUserMessageID
        if context.appendsUserMessage {
            let userMessage = ChatMessage(
                role: "user",
                content: context.userText,
                imageAttachments: context.imageAttachments,
                imageContextDescription: context.imageContextDescription,
                fileAttachments: context.fileAttachments
            )
            messages.append(userMessage)
            userMessageIDForImageContext = userMessage.id
        }

        let assistantMessage = ChatMessage(role: "assistant", content: "")
        messages.append(assistantMessage)

        let generation = ActiveConversationGeneration(
            conversationID: context.conversationID,
            assistantMessageID: assistantMessage.id,
            service: requestService
        )
        beginVisibleGeneration(generation)

        return .success(StreamingTurnStartResult(
            service: requestService,
            generation: generation,
            assistantMessageID: assistantMessage.id,
            userMessageIDForImageContext: userMessageIDForImageContext
        ))
    }

    func prepareStreamingTurn(
        _ context: StreamingTurnPreparationContext
    ) -> Result<StreamingTurnPreparation, StreamingTurnPreparationFailure> {
        let configuration = context.configuration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiFormat = configuration.apiFormat
        let credentialSet = configuration.credentialSet()
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelParameters = configuration.selectedModelConfiguration
        let anthropicMaxTokens = configuration.anthropicMaxTokens
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil
        let usesImageAttachments = configuration.selectedModelSupportsImages
        let agentTools = context.mcpTools + context.recallTools + context.knowledgeTools

        guard !context.userText.isEmpty || !context.imageAttachments.isEmpty || !context.fileAttachments.isEmpty else {
            return .failure(.emptyMessage)
        }

        guard !context.hasActiveMCPServers || configuration.apiFormat != .vertexAIExpress else {
            return .failure(.vertexMCPUnsupported)
        }

        guard !context.hasActiveMCPServers || configuration.selectedModelSupportsTools else {
            return .failure(.modelToolsUnsupported)
        }

        guard !context.hasActiveMCPServers || !context.mcpTools.isEmpty else {
            return .failure(.noMCPTools)
        }

        guard context.imageAttachments.isEmpty
                || usesImageAttachments
                || !context.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.imageWithoutDescription)
        }

        guard usesImageAttachments || !Self.containsImageWithoutContextDescription(in: context.contextMessages) else {
            return .failure(.contextImageWithoutDescription)
        }

        guard !trimmedBaseURL.isEmpty else {
            return .failure(.missingBaseURL)
        }

        guard !model.isEmpty else {
            return .failure(.missingModel)
        }

        guard let conversationID = context.conversationID else {
            return .failure(.missingConversation)
        }

        let effectiveSystemPrompt = configuration.systemPrompt + context.systemPromptAppendix
        let preservesReasoningContext = AIService.usesDeepSeekReasoningContext(
            apiFormat: apiFormat,
            baseURL: trimmedBaseURL,
            model: model
        )
        let startContext = StreamingTurnStartContext(
            conversationID: conversationID,
            userText: context.userText,
            imageAttachments: context.imageAttachments,
            imageContextDescription: context.imageContextDescription,
            fileAttachments: context.fileAttachments,
            contextMessages: context.contextMessages,
            appendsUserMessage: context.appendsUserMessage,
            existingUserMessageID: context.existingUserMessageID,
            systemPrompt: effectiveSystemPrompt,
            usesImageAttachments: usesImageAttachments,
            preservesReasoningContext: preservesReasoningContext,
            maxActiveConversationGenerations: context.maxActiveConversationGenerations
        )

        let startResult: StreamingTurnStartResult
        switch startStreamingTurn(startContext) {
        case .success(let result):
            startResult = result
        case .failure(.alreadyGenerating):
            return .failure(.alreadyGenerating)
        case .failure(.tooManyActiveRequests(let limit)):
            return .failure(.tooManyActiveRequests(limit: limit))
        }

        let serviceRequest = StreamingServiceRequest(
            message: context.userText,
            imageAttachments: context.imageAttachments,
            imageContextDescription: context.imageContextDescription,
            fileAttachments: context.fileAttachments,
            baseURL: trimmedBaseURL,
            apiFormat: apiFormat,
            credentialSet: credentialSet,
            customHeaders: trimmedCustomHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            usesImageAttachments: usesImageAttachments,
            agentTools: agentTools
        )
        let shouldGenerateImageContextDescription = usesImageAttachments
            && configuration.generatesImageContextDescriptions
            && !context.imageAttachments.isEmpty
            && context.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && startResult.userMessageIDForImageContext != nil

        return .success(StreamingTurnPreparation(
            startResult: startResult,
            serviceRequest: serviceRequest,
            shouldGenerateImageContextDescription: shouldGenerateImageContextDescription
        ))
    }

    func sendStreamingRequest(
        _ request: StreamingServiceRequest,
        using startResult: StreamingTurnStartResult,
        handlers: StreamingEventHandlers
    ) {
        startResult.service.sendStreamingMessage(
            message: request.message,
            imageAttachments: request.imageAttachments,
            imageContextDescription: request.imageContextDescription,
            fileAttachments: request.fileAttachments,
            baseURL: request.baseURL,
            apiFormat: request.apiFormat,
            credentialSet: request.credentialSet,
            customHeaders: request.customHeaders,
            model: request.model,
            modelParameters: request.modelParameters,
            anthropicMaxTokens: request.anthropicMaxTokens,
            reasoningEnabled: request.reasoningEnabled,
            reasoningEffort: request.reasoningEffort,
            usesImageAttachments: request.usesImageAttachments,
            agentTools: request.agentTools,
            toolExecutor: handlers.toolExecutor,
            onToolExchangesUpdated: handlers.onToolExchangesUpdated,
            onToolRoundReset: handlers.onToolRoundReset,
            isReasoningDisplayActive: handlers.isReasoningDisplayActive,
            onReasoningToken: handlers.onReasoningToken,
            onContentToken: handlers.onContentToken,
            onComplete: handlers.onComplete,
            onError: handlers.onError
        )
    }

    func prepareForVisibleGenerationStart() {
        isGenerating = true
        streamingTokenBuffer.reset()
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isFlushScheduled = false
    }

    func beginVisibleGeneration(_ generation: ActiveConversationGeneration) {
        activeConversationGenerations[generation.conversationID] = generation
        bindVisibleGeneration(generation)
    }

    func bindVisibleGeneration(_ generation: ActiveConversationGeneration) {
        isGenerating = true
        activeAssistantMessageID = generation.assistantMessageID
        streamingTokenBuffer = generation.tokenBuffer
        activeAssistantHasReasoning = generation.hasReasoning
        activeAssistantHasContent = generation.hasContent
        activeAssistantReasoningIsExpanded = generation.reasoningIsExpanded
        activeAssistantDidCollapseReasoningAfterThinking = generation.didCollapseReasoningAfterThinking
        liveAssistantDisplays[generation.assistantMessageID] = AssistantLiveDisplay()
    }

    func clearVisibleGenerationSelection() {
        isGenerating = false
        activeAssistantMessageID = nil
    }

    func resetVisibleGenerationState() {
        activeAssistantMessageID = nil
        liveAssistantDisplays = [:]
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        streamingTokenBuffer.reset()
        isFlushScheduled = false
    }

    func resetVisibleGenerationStateAndMarkIdle() {
        resetVisibleGenerationState()
        isGenerating = false
    }

    func detachVisibleGenerationState() {
        resetVisibleGenerationState()
        isGenerating = false
        streamingTokenBuffer = StreamingTokenBuffer()
        flushTask = nil
    }

    func completeVisibleGeneration(assistantMessageID: UUID) {
        isGenerating = false
        activeAssistantMessageID = nil
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isFlushScheduled = false
        flushTask = nil
        liveAssistantDisplays[assistantMessageID] = nil
        streamingTokenBuffer = StreamingTokenBuffer()
    }

    func cancelActiveGeneration(
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> ActiveGenerationCancellation? {
        guard let generation = activeConversationGenerations[conversationID] else { return nil }

        generation.service.cancelStreaming()
        cancelScheduledFlush(
            in: conversationID,
            visibleConversationID: visibleConversationID
        )
        return ActiveGenerationCancellation(
            conversationID: conversationID,
            assistantMessageID: generation.assistantMessageID
        )
    }

    func finishActiveGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?,
        marksStopped: Bool
    ) -> ActiveGenerationFinishResult? {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return nil
        }

        generation.cancelScheduledFlush()
        activeConversationGenerations[conversationID] = nil

        let didCompleteVisibleGeneration = visibleConversationID == conversationID
        if didCompleteVisibleGeneration {
            completeVisibleGeneration(assistantMessageID: assistantMessageID)
        }

        return ActiveGenerationFinishResult(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            shouldMarkStopped: marksStopped,
            didCompleteVisibleGeneration: didCompleteVisibleGeneration
        )
    }

    func activeGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) -> ActiveConversationGeneration? {
        guard let generation = activeConversationGenerations[conversationID],
              generation.assistantMessageID == assistantMessageID else {
            return nil
        }
        return generation
    }

    func activeGeneration(in conversationID: UUID) -> ActiveConversationGeneration? {
        activeConversationGenerations[conversationID]
    }

    var activeConversationIDs: [UUID] {
        Array(activeConversationGenerations.keys)
    }

    var activeConversationGenerationCount: Int {
        activeConversationGenerations.count
    }

    func resetServiceConversation(
        with messages: [ChatMessage],
        systemPrompt: String,
        usesImageAttachments: Bool
    ) {
        aiService.resetConversation(
            with: messages,
            systemPrompt: systemPrompt,
            usesImageAttachments: usesImageAttachments
        )
    }

    func replaceVisibleConversation(
        messages newMessages: [ChatMessage],
        systemPrompt: String,
        usesImageAttachments: Bool,
        marksIdle: Bool
    ) {
        messages = newMessages
        if marksIdle {
            resetVisibleGenerationStateAndMarkIdle()
        } else {
            resetVisibleGenerationState()
        }
        resetServiceConversation(
            with: newMessages,
            systemPrompt: systemPrompt,
            usesImageAttachments: usesImageAttachments
        )
    }

    @discardableResult
    func clearGeneratedContent(for messageID: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return false
        }

        messages[index].clearGeneratedContent()
        liveAssistantDisplays[messageID] = nil
        if activeAssistantMessageID == messageID {
            resetVisibleGenerationStateAndMarkIdle()
        }
        return true
    }

    func visibleAssistantDisplayState(for assistantMessageID: UUID) -> VisibleAssistantDisplayState {
        let isStreaming = activeAssistantMessageID == assistantMessageID
        guard isStreaming else {
            return VisibleAssistantDisplayState(
                isStreaming: false,
                hasStreamingReasoning: false,
                hasStreamingContent: false,
                streamingContentChannel: nil,
                streamingReasoningChannel: nil
            )
        }

        let liveDisplay = liveAssistantDisplays[assistantMessageID]
        return VisibleAssistantDisplayState(
            isStreaming: true,
            hasStreamingReasoning: activeAssistantHasReasoning,
            hasStreamingContent: activeAssistantHasContent,
            streamingContentChannel: liveDisplay?.contentChannel,
            streamingReasoningChannel: activeAssistantReasoningIsExpanded
                ? liveDisplay?.reasoningChannel
                : nil
        )
    }

    func shouldPublishLiveReasoningUpdate(for assistantMessageID: UUID) -> Bool {
        activeAssistantMessageID == assistantMessageID && activeAssistantReasoningIsExpanded
    }

    var streamingReasoningChunksSnapshot: [String] {
        streamingTokenBuffer.reasoningChunksSnapshot
    }

    func liveReasoningChannel(for assistantMessageID: UUID) -> StreamingTextUpdateChannel? {
        liveAssistantDisplays[assistantMessageID]?.reasoningChannel
    }

    func liveContentChannel(for assistantMessageID: UUID) -> StreamingTextUpdateChannel? {
        liveAssistantDisplays[assistantMessageID]?.contentChannel
    }

    func isReasoningDisplayActive(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard visibleConversationID == conversationID,
              let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return false
        }
        return generation.reasoningIsExpanded
    }

    @discardableResult
    func updateVisibleToolExchanges(
        _ exchanges: [ChatToolExchange],
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard visibleConversationID == conversationID,
              activeGeneration(for: assistantMessageID, in: conversationID) != nil,
              let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return false
        }

        messages[index].toolExchanges = exchanges
        return true
    }

    @discardableResult
    func resetStreamingRoundDisplay(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> StreamingRoundResetEffect? {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return nil
        }

        cancelScheduledFlush(in: conversationID, visibleConversationID: visibleConversationID)
        generation.tokenBuffer.clearPendingTokens()
        generation.hasContent = false
        generation.hasReasoning = false

        guard visibleConversationID == conversationID else {
            return StreamingRoundResetEffect(
                isVisibleConversation: false,
                shouldResetLiveContentDisplay: false,
                shouldClearLiveReasoningDisplay: false,
                shouldInvalidateMarkdownCache: false
            )
        }

        Self.resetStreamingRoundMessageDisplay(
            for: assistantMessageID,
            in: &messages
        )

        if activeAssistantMessageID == assistantMessageID {
            activeAssistantHasContent = false
            activeAssistantHasReasoning = false
            activeAssistantDidCollapseReasoningAfterThinking = false
        }

        return StreamingRoundResetEffect(
            isVisibleConversation: true,
            shouldResetLiveContentDisplay: true,
            shouldClearLiveReasoningDisplay: true,
            shouldInvalidateMarkdownCache: true
        )
    }

    @discardableResult
    func synchronizeVisibleCompletedAssistantContent(
        _ contentText: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard visibleConversationID == conversationID else {
            return false
        }

        return Self.synchronizeCompletedAssistantContent(
            contentText,
            for: assistantMessageID,
            in: &messages
        )
    }

    static func stampedAssistantUsage(
        _ usage: ChatUsage?,
        modelName: String,
        configurationID: UUID
    ) -> ChatUsage? {
        guard var stampedUsage = usage, stampedUsage.hasTokenCounts else { return nil }
        stampedUsage.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        stampedUsage.configurationID = configurationID
        return stampedUsage
    }

    @discardableResult
    func setVisibleAssistantUsage(
        _ usage: ChatUsage,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard visibleConversationID == conversationID,
              let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return false
        }

        messages[index].usage = usage
        return true
    }

    @discardableResult
    func setVisibleAssistantErrorContent(
        _ content: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard visibleConversationID == conversationID,
              activeGeneration(for: assistantMessageID, in: conversationID) != nil,
              let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return false
        }

        messages[index].content = content
        return true
    }

    @discardableResult
    func appendAssistantError(_ content: String) -> AssistantErrorAppendResult {
        let message = ChatMessage(role: "assistant", content: content)
        messages.append(message)
        return AssistantErrorAppendResult(
            messageID: message.id,
            content: content
        )
    }

    @discardableResult
    func applyReasoningCollapseAfterThinking(
        _ effect: ReasoningCollapseEffect,
        for assistantMessageID: UUID
    ) -> Bool {
        if let index = messages.firstIndex(where: { $0.id == assistantMessageID }),
           messages[index].isReasoningExpanded {
            messages[index].isReasoningExpanded = false
            return true
        }

        return effect.wasReasoningExpanded
    }

    @discardableResult
    func receiveReasoningToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> Bool {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return false
        }

        generation.hasReasoning = true
        generation.tokenBuffer.appendReasoning(token)

        guard visibleConversationID == conversationID,
              activeAssistantMessageID == assistantMessageID else {
            return false
        }

        bindStreamingTokenBufferIfNeeded(to: generation)
        activeAssistantHasReasoning = true
        return activeAssistantReasoningIsExpanded
    }

    func receiveContentToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?
    ) -> ContentTokenEffect? {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return nil
        }

        generation.hasContent = true
        generation.tokenBuffer.appendContent(token)

        guard visibleConversationID == conversationID,
              activeAssistantMessageID == assistantMessageID else {
            return ContentTokenEffect(shouldAppendLiveContent: false, reasoningCollapse: nil)
        }

        bindStreamingTokenBufferIfNeeded(to: generation)
        let collapse = collapseReasoningAfterThinkingIfNeeded(
            for: assistantMessageID,
            generation: generation
        )
        activeAssistantHasContent = true
        return ContentTokenEffect(shouldAppendLiveContent: true, reasoningCollapse: collapse)
    }

    func setReasoningExpansion(
        _ isExpanded: Bool,
        for assistantMessageID: UUID,
        in visibleConversationID: UUID?
    ) -> Bool {
        guard activeAssistantMessageID == assistantMessageID else { return false }

        activeAssistantReasoningIsExpanded = isExpanded
        if let visibleConversationID,
           let generation = activeGeneration(for: assistantMessageID, in: visibleConversationID) {
            generation.reasoningIsExpanded = isExpanded
        }
        return true
    }

    func pruneLiveAssistantDisplays(validMessageIDs: Set<UUID>) {
        liveAssistantDisplays = liveAssistantDisplays.filter { validMessageIDs.contains($0.key) }
    }

    func cancelVisibleScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }

    func cancelScheduledFlush(in conversationID: UUID, visibleConversationID: UUID?) {
        if visibleConversationID == conversationID {
            cancelVisibleScheduledFlush()
        }
        activeConversationGenerations[conversationID]?.cancelScheduledFlush()
    }

    func scheduleTokenFlush(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?,
        flush: @escaping @MainActor (_ assistantMessageID: UUID, _ conversationID: UUID) -> Void
    ) {
        if visibleConversationID == conversationID {
            scheduleVisibleTokenFlush(
                for: assistantMessageID,
                in: conversationID,
                flush: flush
            )
        } else {
            scheduleBackgroundTokenFlush(
                for: assistantMessageID,
                in: conversationID,
                flush: flush
            )
        }
    }

    private func scheduleVisibleTokenFlush(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        flush: @escaping @MainActor (_ assistantMessageID: UUID, _ conversationID: UUID) -> Void
    ) {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        flushTask?.cancel()

        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flush(assistantMessageID, conversationID)
        }
    }

    private func scheduleBackgroundTokenFlush(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        flush: @escaping @MainActor (_ assistantMessageID: UUID, _ conversationID: UUID) -> Void
    ) {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID),
              !generation.isFlushScheduled else {
            return
        }

        generation.isFlushScheduled = true
        generation.flushTask?.cancel()
        generation.flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            flush(assistantMessageID, conversationID)
        }
    }

    func flushVisiblePendingTokens(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        visibleConversationID: UUID?,
        flushesReasoning: Bool,
        invalidatesMarkdownCache: Bool,
        requestsAutoScroll: Bool
    ) -> TokenFlushResult? {
        guard visibleConversationID == conversationID,
              let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return nil
        }

        generation.cancelScheduledFlush()
        bindStreamingTokenBufferIfNeeded(to: generation)

        let result = Self.flushPendingTokens(
            from: generation.tokenBuffer,
            into: &messages,
            messageID: assistantMessageID,
            flushesReasoning: flushesReasoning,
            invalidatesMarkdownCache: invalidatesMarkdownCache,
            requestsAutoScroll: requestsAutoScroll
        )
        if result.didConsumeContent {
            activeAssistantHasContent = true
        }

        isFlushScheduled = false
        flushTask = nil
        return result
    }

    static func flushBackgroundPendingTokens(
        from generation: ActiveConversationGeneration,
        into messages: inout [ChatMessage],
        flushesReasoning: Bool
    ) -> TokenFlushResult {
        let result = flushPendingTokens(
            from: generation.tokenBuffer,
            into: &messages,
            messageID: generation.assistantMessageID,
            flushesReasoning: flushesReasoning,
            invalidatesMarkdownCache: false,
            requestsAutoScroll: false
        )
        generation.cancelScheduledFlush()
        return result
    }

    @discardableResult
    static func resetStreamingRoundMessageDisplay(
        for assistantMessageID: UUID,
        in messages: inout [ChatMessage]
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return false
        }

        messages[index].content = ""
        messages[index].contentChunks = []
        messages[index].reasoningContent = ""
        messages[index].reasoningChunks = []
        return true
    }

    @discardableResult
    static func synchronizeCompletedAssistantContent(
        _ contentText: String,
        for assistantMessageID: UUID,
        in messages: inout [ChatMessage]
    ) -> Bool {
        guard !contentText.isEmpty,
              let index = messages.firstIndex(where: { $0.id == assistantMessageID }),
              messages[index].content != contentText else {
            return false
        }

        messages[index].content = contentText
        return true
    }

    private func bindStreamingTokenBufferIfNeeded(to generation: ActiveConversationGeneration) {
        if streamingTokenBuffer !== generation.tokenBuffer {
            streamingTokenBuffer = generation.tokenBuffer
        }
    }

    private func collapseReasoningAfterThinkingIfNeeded(
        for assistantMessageID: UUID,
        generation: ActiveConversationGeneration
    ) -> ReasoningCollapseEffect? {
        guard activeAssistantMessageID == assistantMessageID,
              activeAssistantHasReasoning,
              !activeAssistantDidCollapseReasoningAfterThinking else {
            return nil
        }

        activeAssistantDidCollapseReasoningAfterThinking = true
        let wasReasoningExpanded = activeAssistantReasoningIsExpanded
        activeAssistantReasoningIsExpanded = false
        generation.didCollapseReasoningAfterThinking = true
        generation.reasoningIsExpanded = false
        return ReasoningCollapseEffect(wasReasoningExpanded: wasReasoningExpanded)
    }

    private static func flushPendingTokens(
        from tokenBuffer: StreamingTokenBuffer,
        into messages: inout [ChatMessage],
        messageID: UUID,
        flushesReasoning: Bool,
        invalidatesMarkdownCache: Bool,
        requestsAutoScroll: Bool
    ) -> TokenFlushResult {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            tokenBuffer.clearPendingTokens()
            return TokenFlushResult(
                messageWasFound: false,
                didConsumeReasoning: false,
                didConsumeContent: false,
                shouldInvalidateMarkdownCache: false,
                shouldRequestAutoScroll: false
            )
        }

        let didConsumeReasoning = flushesReasoning && tokenBuffer.hasPendingReasoningText
        if didConsumeReasoning {
            messages[index].reasoningChunks.append(contentsOf: tokenBuffer.consumePendingReasoningChunks())
        }

        let didConsumeContent = tokenBuffer.hasPendingContentText
        if didConsumeContent {
            messages[index].content += tokenBuffer.consumePendingContentText()
        }

        return TokenFlushResult(
            messageWasFound: true,
            didConsumeReasoning: didConsumeReasoning,
            didConsumeContent: didConsumeContent,
            shouldInvalidateMarkdownCache: didConsumeContent && invalidatesMarkdownCache,
            shouldRequestAutoScroll: requestsAutoScroll
        )
    }

    private static func containsImageWithoutContextDescription(in messages: [ChatMessage]) -> Bool {
        messages.contains { message in
            message.role == "user"
                && !message.imageAttachments.isEmpty
                && message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
