//
//  AIService.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

class AIService {
    private static let maxResponseByteCount = 2 * 1024 * 1024
    private static let maxErrorBodyCharacters = 4_000
    private static let maxStreamingContentCharacters = 200_000
    private static let maxStreamingReasoningCharacters = 120_000
    private static let anthropicClaudeCodeSystemPrompt = "You are Claude Code, Anthropic's official CLI for Claude."
    private static let anthropicClaudeCodeBetaHeader = "context-1m-2025-08-07,claude-code-20250219,interleaved-thinking-2025-05-14,thinking-token-count-2026-05-13,context-management-2025-06-27,prompt-caching-scope-2026-01-05,mid-conversation-system-2026-04-07,advisor-tool-2026-03-01,effort-2025-11-24"
    private static let anthropicOneMillionContextBetaHeader = "context-1m-2025-08-07,context-management-2025-06-27"
    private static let anthropicClaudeCodeManagedHeaders: Set<String> = [
        "accept",
        "authorization",
        "content-type",
        "x-api-key",
        "anthropic-version",
        "anthropic-beta",
        "anthropic-dangerous-direct-browser-access",
        "user-agent",
        "x-app",
        "x-claude-code-session-id"
    ]

    private struct AnthropicModelSelection {
        let requestModel: String
        let usesOneMillionContext: Bool
    }

    private enum BoundedResponseDataError: Error {
        case responseTooLarge
    }

    private let session: URLSession
    private let anthropicClaudeCodeMetadata = AnthropicClaudeCodeMetadata()
    private var conversationHistory = AIService.initialConversationHistory(
        systemPrompt: AIConfiguration.defaultSystemPrompt
    )

    private var streamingTask: Task<Void, Never>?

    init(session: URLSession = AIService.makeSecureSession()) {
        self.session = session
    }

    static func usesDeepSeekReasoningContext(
        apiFormat: AIAPIFormat,
        baseURL: String,
        model: String
    ) -> Bool {
        guard apiFormat == .openAIChatCompletions else { return false }

        let lowercasedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowercasedModel.contains("deepseek") {
            return true
        }

        return baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("deepseek")
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    func resetConversation(
        with messages: [ChatMessage],
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        usesImageAttachments: Bool = true,
        preservesReasoningContext: Bool = false
    ) {
        conversationHistory = Self.initialConversationHistory(systemPrompt: systemPrompt)

        conversationHistory.append(
            contentsOf: messages.flatMap { message -> [ChatRequestMessage] in
                let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasImages = !message.imageAttachments.isEmpty
                let hasFiles = !message.fileAttachments.isEmpty
                let hasTools = !message.toolExchanges.isEmpty
                guard (hasImages || hasFiles || hasTools || !content.isEmpty),
                      message.role == "user" || message.role == "assistant" else {
                    return []
                }

                var requestMessages = [ChatRequestMessage]()
                if message.role == "assistant", !message.toolExchanges.isEmpty {
                    for exchange in message.toolExchanges {
                        requestMessages.append(ChatRequestMessage(
                            role: "assistant",
                            text: exchange.assistantContent,
                            reasoningContent: preservesReasoningContext ? exchange.reasoningContent : "",
                            toolCalls: exchange.toolCalls
                        ))
                        requestMessages.append(contentsOf: exchange.toolResults.map { result in
                            ChatRequestMessage(
                                toolCallID: result.toolCallID,
                                name: result.name,
                                content: result.content
                            )
                        })
                    }
                }

                if message.role == "assistant" {
                    requestMessages.append(ChatRequestMessage(
                        role: "assistant",
                        text: content,
                        reasoningContent: preservesReasoningContext ? Self.reasoningContent(from: message) : "",
                        toolCalls: []
                    ))
                } else {
                    requestMessages.append(ChatRequestMessage(
                        role: message.role,
                        text: Self.textByAppendingRequestMetadata(content),
                        imageAttachments: message.imageAttachments,
                        imageContextDescription: message.imageContextDescription,
                        fileAttachments: message.fileAttachments,
                        usesImageAttachments: usesImageAttachments
                    ))
                }
                return requestMessages
            }
        )
    }

    private static func reasoningContent(from message: ChatMessage) -> String {
        var chunks = [String]()
        if !message.reasoningContent.isEmpty {
            chunks.append(message.reasoningContent)
        }
        chunks.append(contentsOf: message.reasoningChunks)
        return chunks.joined()
    }

    private static func textByAppendingRequestMetadata(_ text: String, date: Date = Date()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm:ss"

        let offsetSeconds = TimeZone.current.secondsFromGMT(for: date)
        let offsetSign = offsetSeconds >= 0 ? "+" : "-"
        let absoluteOffset = abs(offsetSeconds)
        let offsetHours = absoluteOffset / 3_600
        let offsetMinutes = (absoluteOffset % 3_600) / 60
        let offsetText = String(format: "UTC%@%02d:%02d", offsetSign, offsetHours, offsetMinutes)

        let metadata = """
        <message_metadata>
        current_date: \(dateFormatter.string(from: date))
        current_time: \(timeFormatter.string(from: date))
        timezone: \(TimeZone.current.identifier) (\(offsetText))
        note: Treat latest/current/today/recent requests relative to current_date. Prefer searches using the current year unless the user asks for a specific past year.
        </message_metadata>
        """

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return metadata }
        return "\(metadata)\n\n\(text)"
    }

    private static func initialConversationHistory(systemPrompt: String) -> [ChatRequestMessage] {
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return [] }
        return [ChatRequestMessage(role: "system", text: trimmedPrompt)]
    }

    private func requestBodyData(
        apiFormat: AIAPIFormat,
        model: String,
        messages: [ChatRequestMessage],
        stream: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        tools: [AgentToolDefinition] = []
    ) throws -> Data {
        let encoder = JSONEncoder()
        switch apiFormat {
        case .openAIChatCompletions:
            return try encoder.encode(OpenAIRequest(
                model: model,
                messages: messages,
                stream: stream,
                thinking: thinkingConfig(from: reasoningEnabled),
                reasoningEffort: reasoningEnabled == true ? reasoningEffort : nil,
                tools: openAITools(from: tools),
                temperature: modelParameters?.temperature,
                topP: modelParameters?.topP,
                maxTokens: modelParameters?.maxOutputTokens
            ))
        case .openAIResponses:
            let responseMessages = Self.openAIResponsesMessages(from: messages)
            return try encoder.encode(OpenAIResponsesRequest(
                model: model,
                input: responseMessages.input,
                instructions: responseMessages.instructions,
                stream: stream,
                reasoning: reasoningEnabled == true ? reasoningEffort.map(OpenAIResponsesReasoning.init(effort:)) : nil,
                tools: openAIResponsesTools(from: tools),
                temperature: modelParameters?.temperature,
                topP: modelParameters?.topP,
                maxOutputTokens: modelParameters?.maxOutputTokens
            ))
        case .anthropicMessages:
            let anthropicModel = Self.anthropicModelSelection(from: model)
            let usesOneMillionContext = anthropicClaudeCodeImpersonationEnabled
                || anthropicModel.usesOneMillionContext
            let anthropicMessages = Self.anthropicMessages(
                from: messages,
                usesClaudeCodeImpersonation: anthropicClaudeCodeImpersonationEnabled
            )
            return try encoder.encode(AnthropicMessagesRequest(
                model: anthropicModel.requestModel,
                maxTokens: usesOneMillionContext ? 64_000 : max(1, anthropicMaxTokens),
                messages: anthropicMessages.messages,
                system: anthropicMessages.system,
                stream: stream,
                tools: anthropicTools(from: tools),
                temperature: modelParameters?.temperature,
                topP: modelParameters?.topP,
                metadata: anthropicClaudeCodeImpersonationEnabled ? anthropicClaudeCodeMetadata : nil,
                contextManagement: usesOneMillionContext ? .claudeCodeDefault : nil
            ))
        case .vertexAIExpress:
            let vertexRequest = Self.vertexRequest(
                from: messages,
                modelParameters: modelParameters
            )
            return try encoder.encode(vertexRequest)
        }
    }

    private static func openAIResponsesMessages(
        from messages: [ChatRequestMessage]
    ) -> (instructions: String?, input: [OpenAIResponsesInputItem]) {
        var instructions = [String]()
        var input = [OpenAIResponsesInputItem]()

        for message in messages {
            if message.role == "system" {
                let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    instructions.append(text)
                }
                continue
            }

            if message.role == "tool", let toolCallID = message.toolCallID {
                input.append(.functionCallOutput(
                    callID: toolCallID,
                    output: message.content.plainText
                ))
                continue
            }

            if message.role == "assistant", !message.toolCalls.isEmpty {
                for call in message.toolCalls {
                    input.append(.functionCall(
                        callID: call.id,
                        name: call.name,
                        arguments: call.argumentsJSON
                    ))
                }
                continue
            }

            let role = message.role == "assistant" ? "assistant" : "user"
            input.append(.message(
                role: role,
                content: message.content.openAIResponsesContent
            ))
        }

        return (
            instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"),
            input
        )
    }

    private static func anthropicMessages(
        from messages: [ChatRequestMessage],
        usesClaudeCodeImpersonation: Bool
    ) -> (system: AnthropicSystemContent?, messages: [AnthropicMessage]) {
        var systemMessages = [String]()
        var requestMessages = [AnthropicMessage]()

        for message in messages {
            if message.role == "system" {
                let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    systemMessages.append(text)
                }
                continue
            }

            if message.role == "tool", let toolCallID = message.toolCallID {
                requestMessages.append(AnthropicMessage(
                    role: "user",
                    content: .parts([
                        .toolResult(
                            toolUseID: toolCallID,
                            content: message.content.plainText,
                            isError: false
                        )
                    ])
                ))
                continue
            }

            if message.role == "assistant", !message.toolCalls.isEmpty {
                var parts = [AnthropicContentPart]()
                let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    parts.append(.text(text))
                }
                parts.append(contentsOf: message.toolCalls.map { call in
                    .toolUse(
                        id: call.id,
                        name: call.name,
                        input: Self.jsonValue(from: call.argumentsJSON)
                    )
                })
                requestMessages.append(AnthropicMessage(role: "assistant", content: .parts(parts)))
                continue
            }

            let role = message.role == "assistant" ? "assistant" : "user"
            requestMessages.append(AnthropicMessage(
                role: role,
                content: message.content.anthropicContent
            ))
        }

        if usesClaudeCodeImpersonation,
           let lastMessage = requestMessages.popLast() {
            requestMessages.append(lastMessage.applyingEphemeralCacheControlToLastContentPart())
        }

        return (
            anthropicSystemContent(
                from: systemMessages,
                usesClaudeCodeImpersonation: usesClaudeCodeImpersonation
            ),
            requestMessages
        )
    }

    private static func anthropicSystemContent(
        from systemMessages: [String],
        usesClaudeCodeImpersonation: Bool
    ) -> AnthropicSystemContent? {
        if usesClaudeCodeImpersonation {
            return .parts([
                AnthropicSystemPart(
                    text: anthropicClaudeCodeSystemPrompt,
                    cacheControl: .ephemeral
                )
            ])
        }

        guard !systemMessages.isEmpty else { return nil }
        return .text(systemMessages.joined(separator: "\n\n"))
    }

    private static func anthropicModelSelection(from model: String) -> AnthropicModelSelection {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "[1m]"
        guard trimmedModel.lowercased().hasSuffix(suffix) else {
            return AnthropicModelSelection(requestModel: trimmedModel, usesOneMillionContext: false)
        }

        let suffixStartIndex = trimmedModel.index(trimmedModel.endIndex, offsetBy: -suffix.count)
        let baseModel = trimmedModel[..<suffixStartIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseModel.isEmpty else {
            return AnthropicModelSelection(requestModel: trimmedModel, usesOneMillionContext: false)
        }

        return AnthropicModelSelection(requestModel: baseModel, usesOneMillionContext: true)
    }

    private static func vertexRequest(
        from messages: [ChatRequestMessage],
        modelParameters: AIModelConfiguration?
    ) -> VertexGenerateContentRequest {
        var systemParts = [VertexPart]()
        var contents = [VertexContent]()

        for message in messages {
            if message.role == "system" {
                let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    systemParts.append(.text(text))
                }
                continue
            }

            let parts = message.content.vertexParts
            guard !parts.isEmpty else { continue }
            contents.append(VertexContent(
                role: message.role == "assistant" ? "model" : "user",
                parts: parts
            ))
        }

        return VertexGenerateContentRequest(
            contents: contents,
            systemInstruction: systemParts.isEmpty ? nil : VertexContent(role: nil, parts: systemParts),
            generationConfig: vertexGenerationConfig(from: modelParameters)
        )
    }

    private static func vertexGenerationConfig(
        from modelParameters: AIModelConfiguration?
    ) -> VertexGenerationConfig? {
        guard modelParameters?.temperature != nil
                || modelParameters?.topP != nil
                || modelParameters?.maxOutputTokens != nil else {
            return nil
        }

        return VertexGenerationConfig(
            temperature: modelParameters?.temperature,
            topP: modelParameters?.topP,
            maxOutputTokens: modelParameters?.maxOutputTokens
        )
    }

    private func openAITools(from tools: [AgentToolDefinition]) -> [OpenAIToolDefinition]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            OpenAIToolDefinition(function: OpenAIFunctionDefinition(
                name: tool.functionName,
                description: tool.description,
                parameters: tool.inputSchema
            ))
        }
    }

    private func openAIResponsesTools(from tools: [AgentToolDefinition]) -> [OpenAIResponsesToolDefinition]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            OpenAIResponsesToolDefinition(
                name: tool.functionName,
                description: tool.description,
                parameters: tool.inputSchema
            )
        }
    }

    private func anthropicTools(from tools: [AgentToolDefinition]) -> [AnthropicToolDefinition]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            AnthropicToolDefinition(
                name: tool.functionName,
                description: tool.description,
                inputSchema: tool.inputSchema
            )
        }
    }

    private static func jsonValue(from json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    func fetchModels(
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        completion: @escaping (Result<[AIModelConfiguration], AIServiceError>) -> Void
    ) {
        guard apiFormat != .vertexAIExpress else {
            completion(.failure(.requestFailed(AppLocalizations.string(
                "aiService.models.vertexFetchUnsupported",
                defaultValue: "Vertex Express does not support automatic model fetching yet. Add Gemini model IDs manually."
            ))))
            return
        }

        let url: URL
        do {
            url = try modelsURL(from: baseURL, apiFormat: apiFormat, filtersTextChatModels: true)
        } catch let error as AIServiceError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidURL))
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        )
        request.httpMethod = "GET"
        request.httpBody = nil
        let redactionValues = Self.redactionValues(apiKey: apiKey, customHeaders: customHeaders)

        Task {
            do {
                let (data, response) = try await boundedResponseData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let responseText = Self.responseText(from: data, redacting: redactionValues)

                guard let statusCode, (200...299).contains(statusCode) else {
                    DispatchQueue.main.async {
                        completion(.failure(.requestFailed(Self.errorMessage(
                            statusCode: statusCode,
                            body: responseText,
                            request: request,
                            redacting: redactionValues
                        ))))
                    }
                    return
                }

                DispatchQueue.main.async {
                    guard let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                        completion(.failure(.decodingFailed(AppLocalizations.format(
                            "aiService.models.decodingFailed",
                            defaultValue: "Failed to parse model list\n\n%@",
                            arguments: [responseText]
                        ))))
                        return
                    }

                    let models = decoded.data
                        .filter { !$0.id.isEmpty }
                        .filter { Self.isTextChatModel($0.id) }
                        .map { item in
                            AIModelConfiguration(
                                name: item.id,
                                supportsReasoning: item.supportsReasoning ?? Self.infersReasoningSupport(for: item.id),
                                supportsImages: item.supportsImages ?? Self.infersImageSupport(for: item.id),
                                supportsTools: item.supportsTools ?? AIModelConfiguration.defaultToolsSupport(for: item.id)
                            )
                        }
                        .sorted { $0.name < $1.name }
                    completion(.success(models))
                }
            } catch BoundedResponseDataError.responseTooLarge {
                DispatchQueue.main.async {
                    completion(.failure(.requestFailed(AppLocalizations.string(
                        "aiService.models.responseTooLarge",
                        defaultValue: "The model list response is too large and was rejected."
                    ))))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.requestFailed(AppLocalizations.format(
                        "aiService.models.requestFailed",
                        defaultValue: "Model list request failed: %@",
                        arguments: [error.localizedDescription]
                    ))))
                }
            }
        }
    }

    func generateConversationTitle(
        messages: [ChatMessage],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    ) {
        guard let url = try? requestURL(
            from: baseURL,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            isStreaming: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        ) else {
            completion(nil)
            return
        }

        let transcript = messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        guard !transcript.isEmpty else {
            completion(nil)
            return
        }

        let titleMessages = [
            ChatRequestMessage(
                role: "system",
                text: AppLocalizations.string(
                    "prompt.titleGeneration.system",
                    defaultValue: "Generate a short title based on the conversation. Only output natural English or Chinese words; do not output special tokens, template fragments, XML/JSON, Markdown, bullet points, quotes, parentheses, underscores, vertical bars, or any formatting symbols. Chinese titles must be at most 10 characters, and English titles at most 6 words. Output only the title itself."
                )
            ),
            ChatRequestMessage(role: "user", text: transcript)
        ]

        guard let jsonData = try? requestBodyData(
            apiFormat: apiFormat,
            model: model,
            messages: titleMessages,
            stream: false,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        ) else {
            completion(nil)
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        )
        request.httpBody = jsonData

        Task {
            do {
                let (data, response) = try await boundedResponseData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                DispatchQueue.main.async {
                    guard let statusCode,
                          (200...299).contains(statusCode),
                          let responseText = Self.decodedResponseText(from: data, apiFormat: apiFormat) else {
                        completion(nil)
                        return
                    }

                    let title = Self.sanitizedConversationTitle(responseText)
                        ?? Self.fallbackConversationTitle(from: messages)

                    completion(title?.isEmpty == false ? title : nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
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
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    ) {
        guard !imageAttachments.isEmpty,
              let url = try? requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: false,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
              ) else {
            completion(nil)
            return
        }

        let descriptionMessages = [
            ChatRequestMessage(
                role: "system",
                text: AppLocalizations.string(
                    "prompt.imageDescription.system",
                    defaultValue: "You generate hidden image context for a chat app. Describe only visible facts, text, objects, scenes, and information that may be relevant to later Q&A. Do not answer the user's question and do not add greetings."
                )
            ),
            ChatRequestMessage(
                role: "user",
                text: AppLocalizations.format(
                    "prompt.imageDescription.user",
                    defaultValue: "Generate one concise English description for the following %d images. It will be used later as replacement image context for models that do not support images. Output only the description body.",
                    arguments: [imageAttachments.count]
                ),
                imageAttachments: imageAttachments
            )
        ]

        guard let jsonData = try? requestBodyData(
            apiFormat: apiFormat,
            model: model,
            messages: descriptionMessages,
            stream: false,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        ) else {
            completion(nil)
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        )
        request.httpBody = jsonData

        Task {
            do {
                let (data, response) = try await boundedResponseData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                DispatchQueue.main.async {
                    guard let statusCode,
                          (200...299).contains(statusCode),
                          let responseText = Self.decodedResponseText(from: data, apiFormat: apiFormat) else {
                        completion(nil)
                        return
                    }

                    completion(Self.sanitizedImageContextDescription(responseText))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    private nonisolated static func sanitizedConversationTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle else { return nil }

        let lines = rawTitle
            .components(separatedBy: .newlines)
        for line in lines {
            if let title = normalizedConversationTitle(line) {
                return title
            }
        }

        return nil
    }

    private nonisolated static func fallbackConversationTitle(from messages: [ChatMessage]) -> String? {
        messages
            .first { $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .flatMap { normalizedConversationTitle($0.content) }
    }

    private nonisolated static func normalizedConversationTitle(_ rawTitle: String) -> String? {
        guard !containsSpecialTokenFragment(rawTitle) else { return nil }

        let formatCharacters = CharacterSet(charactersIn: "\"'“”‘’[]【】()（）{}《》<>#*-_`·•「」『』|:：")
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines.union(formatCharacters))
        for prefix in ["标题：", "标题:", "题目：", "题目:", "Title:", "Title：", "Topic:", "Topic："] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(formatCharacters))
            break
        }

        guard !containsSpecialTokenFragment(title) else { return nil }

        var cleaned = ""
        var previousWasSpace = false
        for scalar in title.unicodeScalars {
            if isAllowedTitleScalar(scalar) {
                cleaned.unicodeScalars.append(scalar)
                previousWasSpace = false
            } else if scalar.properties.isWhitespace || scalar.value < 128 {
                if !cleaned.isEmpty, !previousWasSpace {
                    cleaned.append(" ")
                    previousWasSpace = true
                }
            }
        }

        let normalized = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        let hasLatin = normalized.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        if hasLatin {
            return normalized
                .split(separator: " ")
                .prefix(6)
                .joined(separator: " ")
        }

        return String(normalized.prefix(10))
    }

    private nonisolated static func containsSpecialTokenFragment(_ title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        guard lowercasedTitle.contains("_")
                || lowercasedTitle.contains("|")
                || lowercasedTitle.contains("<")
                || lowercasedTitle.contains(">") else {
            return false
        }

        let compactTitle = lowercasedTitle.filter { $0.isLetter || $0.isNumber }
        return [
            "beginof",
            "endof",
            "startof",
            "think",
            "imstart",
            "imend",
            "startheaderid",
            "endheaderid",
            "eotid"
        ].contains { compactTitle.contains($0) }
    }

    private nonisolated static func isAllowedTitleScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private nonisolated static func sanitizedImageContextDescription(_ rawDescription: String?) -> String? {
        guard let rawDescription else { return nil }
        let description = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }
        return String(description.prefix(4_000))
    }

    func sendMessage(
        message: String,
        imageAttachments: [ChatImageAttachment] = [],
        imageContextDescription: String = "",
        fileAttachments: [ChatFileAttachment] = [],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool = true,
        completion: @escaping (String) -> Void
    ) {
        let url: URL
        do {
            url = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: false,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
            )
        } catch let error as AIServiceError {
            completion(error.localizedDescription)
            return
        } catch {
            completion(AppLocalizations.string("aiService.error.invalidBaseURL", defaultValue: "Invalid Base URL"))
            return
        }

        conversationHistory.append(
            ChatRequestMessage(
                role: "user",
                text: Self.textByAppendingRequestMetadata(message),
                imageAttachments: imageAttachments,
                imageContextDescription: imageContextDescription,
                fileAttachments: fileAttachments,
                usesImageAttachments: usesImageAttachments
            )
        )

        guard let jsonData = try? requestBodyData(
            apiFormat: apiFormat,
            model: model,
            messages: conversationHistory,
            stream: false,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        ) else {
            completion(AppLocalizations.string("aiService.error.encodingFailed", defaultValue: "Failed to encode request body"))
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        )
        request.httpBody = jsonData
        let redactionValues = Self.redactionValues(apiKey: apiKey, customHeaders: customHeaders)

        Task {
            do {
                let (data, response) = try await boundedResponseData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let responseText = Self.responseText(from: data, redacting: redactionValues)

                guard let statusCode, (200...299).contains(statusCode) else {
                    DispatchQueue.main.async {
                        completion(Self.errorMessage(
                            statusCode: statusCode,
                            body: responseText,
                            request: request,
                            redacting: redactionValues
                        ))
                    }
                    return
                }

                DispatchQueue.main.async {
                    if let decodedText = Self.decodedResponseText(from: data, apiFormat: apiFormat) {
                        let text = decodedText.isEmpty
                            ? AppLocalizations.string("chat.emptyAssistantReply", defaultValue: "No reply")
                            : decodedText
                        self.conversationHistory.append(ChatRequestMessage(role: "assistant", text: text))
                        completion(text)
                    } else {
                        completion(AppLocalizations.format(
                            "aiService.error.decodingFailed",
                            defaultValue: "Parsing failed\n\n%@",
                            arguments: [responseText]
                        ))
                    }
                }
            } catch BoundedResponseDataError.responseTooLarge {
                DispatchQueue.main.async {
                    completion(AppLocalizations.string(
                        "aiService.error.responseTooLarge",
                        defaultValue: "The response is too large and was rejected."
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(AppLocalizations.format(
                        "aiService.error.requestFailed",
                        defaultValue: "Request failed: %@",
                        arguments: [error.localizedDescription]
                    ))
                }
            }
        }
    }

    func sendStreamingMessage(
        message: String,
        imageAttachments: [ChatImageAttachment],
        imageContextDescription: String,
        fileAttachments: [ChatFileAttachment],
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool,
        agentTools: [AgentToolDefinition] = [],
        toolExecutor: ((AgentToolCallRequest) async -> AgentToolCallResult)? = nil,
        onToolExchangesUpdated: @escaping ([ChatToolExchange]) -> Void = { _ in },
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ contentText: String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        cancelStreaming()

        if !agentTools.isEmpty, let toolExecutor {
            sendToolEnabledMessage(
                message: message,
                imageAttachments: imageAttachments,
                imageContextDescription: imageContextDescription,
                fileAttachments: fileAttachments,
                baseURL: baseURL,
                apiFormat: apiFormat,
                apiKey: apiKey,
                customHeaders: customHeaders,
                model: model,
                modelParameters: modelParameters,
                anthropicMaxTokens: anthropicMaxTokens,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort,
                usesImageAttachments: usesImageAttachments,
                agentTools: agentTools,
                toolExecutor: toolExecutor,
                onToolExchangesUpdated: onToolExchangesUpdated,
                isReasoningDisplayActive: isReasoningDisplayActive,
                onReasoningToken: onReasoningToken,
                onContentToken: onContentToken,
                onComplete: onComplete,
                onError: onError
            )
            return
        }

        let url: URL
        do {
            url = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: true,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
            )
        } catch let error as AIServiceError {
            onError(error.localizedDescription)
            return
        } catch {
            onError(AppLocalizations.string("aiService.error.invalidBaseURL", defaultValue: "Invalid Base URL"))
            return
        }

        conversationHistory.append(
            ChatRequestMessage(
                role: "user",
                text: Self.textByAppendingRequestMetadata(message),
                imageAttachments: imageAttachments,
                imageContextDescription: imageContextDescription,
                fileAttachments: fileAttachments,
                usesImageAttachments: usesImageAttachments
            )
        )

        guard let jsonData = try? requestBodyData(
            apiFormat: apiFormat,
            model: model,
            messages: conversationHistory,
            stream: true,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        ) else {
            onError(AppLocalizations.string("aiService.error.encodingFailed", defaultValue: "Failed to encode request body"))
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: true,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
        )
        request.httpBody = jsonData
        let redactionValues = Self.redactionValues(apiKey: apiKey, customHeaders: customHeaders)
        let preservesReasoningContext = Self.usesDeepSeekReasoningContext(
            apiFormat: apiFormat,
            baseURL: baseURL,
            model: model
        )

        streamingTask = Task {
            guard let streamedResponse = await streamResponse(
                request: request,
                apiFormat: apiFormat,
                redactionValues: redactionValues,
                isReasoningDisplayActive: isReasoningDisplayActive,
                onReasoningToken: onReasoningToken,
                onContentToken: onContentToken,
                onError: onError
            ) else {
                streamingTask = nil
                return
            }

            conversationHistory.append(ChatRequestMessage(
                role: "assistant",
                text: streamedResponse.content,
                reasoningContent: preservesReasoningContext ? streamedResponse.reasoningContent : "",
                toolCalls: []
            ))

            await MainActor.run {
                onComplete(streamedResponse.content)
            }

            streamingTask = nil
        }
    }

    private func streamResponse(
        request: URLRequest,
        apiFormat: AIAPIFormat,
        redactionValues: [String],
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) async -> StreamedResponse? {
        do {
            let (bytes, response) = try await session.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorBody = await Self.collectErrorBody(from: bytes, redacting: redactionValues)
                await MainActor.run {
                    onError(Self.errorMessage(
                        statusCode: httpResponse.statusCode,
                        body: errorBody,
                        request: request,
                        redacting: redactionValues
                    ))
                }
                return nil
            }

            var fullReasoningChunks: [String] = []
            var fullContentChunks: [String] = []
            var pendingReasoningCallbackChunks: [String] = []
            var pendingContentCallbackChunks: [String] = []
            var fullContentCharacterCount = 0
            var reasoningCharacterCount = 0
            var lastReasoningCallbackFlushDate = Date.distantPast
            var lastContentCallbackFlushDate = Date.distantPast
            var lastReasoningVisibilityCheckDate = Date.distantPast
            var cachedIsReasoningDisplayActive = false
            let visibleReasoningCallbackFlushInterval: TimeInterval = 0.016
            let hiddenReasoningCallbackFlushInterval: TimeInterval = 0.50
            let contentCallbackFlushInterval: TimeInterval = 0.016
            let reasoningVisibilityCheckInterval: TimeInterval = 0.05
            let streamDecoder = JSONDecoder()

            func refreshReasoningVisibilityIfNeeded(force: Bool = false, now: Date) async {
                guard force
                        || now.timeIntervalSince(lastReasoningVisibilityCheckDate) >= reasoningVisibilityCheckInterval else {
                    return
                }

                cachedIsReasoningDisplayActive = await MainActor.run {
                    isReasoningDisplayActive()
                }
                lastReasoningVisibilityCheckDate = now
            }

            func flushTokenCallbacks(force: Bool = false) async {
                guard !pendingReasoningCallbackChunks.isEmpty || !pendingContentCallbackChunks.isEmpty else {
                    return
                }

                let now = Date()

                if !pendingReasoningCallbackChunks.isEmpty {
                    await refreshReasoningVisibilityIfNeeded(force: force, now: now)
                }

                var reasoningText = ""
                var contentText = ""

                if !pendingReasoningCallbackChunks.isEmpty {
                    let reasoningFlushInterval = cachedIsReasoningDisplayActive
                        ? visibleReasoningCallbackFlushInterval
                        : hiddenReasoningCallbackFlushInterval

                    if force || now.timeIntervalSince(lastReasoningCallbackFlushDate) >= reasoningFlushInterval {
                        reasoningText = pendingReasoningCallbackChunks.joined()
                        pendingReasoningCallbackChunks.removeAll(keepingCapacity: true)
                        lastReasoningCallbackFlushDate = now
                    }
                }

                if !pendingContentCallbackChunks.isEmpty,
                   force || now.timeIntervalSince(lastContentCallbackFlushDate) >= contentCallbackFlushInterval {
                    contentText = pendingContentCallbackChunks.joined()
                    pendingContentCallbackChunks.removeAll(keepingCapacity: true)
                    lastContentCallbackFlushDate = now
                }

                guard !reasoningText.isEmpty || !contentText.isEmpty else { return }

                let reasoningTextToDeliver = reasoningText
                let contentTextToDeliver = contentText
                await MainActor.run {
                    if !reasoningTextToDeliver.isEmpty {
                        onReasoningToken(reasoningTextToDeliver)
                    }

                    if !contentTextToDeliver.isEmpty {
                        onContentToken(contentTextToDeliver)
                    }
                }
            }

            for try await line in bytes.lines {
                if Task.isCancelled {
                    return nil
                }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                guard let streamResult = AIServiceStreamParser.parseResult(
                    from: jsonString,
                    apiFormat: apiFormat,
                    decoder: streamDecoder
                ) else {
                    continue
                }

                if let errorMessage = streamResult.errorMessage {
                    let sanitizedMessage = Self.sanitizedErrorBody(
                        errorMessage,
                        redacting: redactionValues
                    )
                    await MainActor.run {
                        onError(sanitizedMessage)
                    }
                    return nil
                }

                if streamResult.isDone {
                    await flushTokenCallbacks(force: true)
                    return StreamedResponse(
                        content: fullContentChunks.joined(),
                        reasoningContent: fullReasoningChunks.joined()
                    )
                }

                let reasoningToken = streamResult.reasoningToken
                let contentToken = streamResult.contentToken

                if let reasoningToken, !reasoningToken.isEmpty {
                    reasoningCharacterCount += reasoningToken.count
                    guard reasoningCharacterCount <= Self.maxStreamingReasoningCharacters else {
                        await MainActor.run {
                            onError(AppLocalizations.string(
                                "aiService.streaming.reasoningTooLong",
                                defaultValue: "Reasoning content is too long. Receiving has stopped."
                            ))
                        }
                        return nil
                    }
                    fullReasoningChunks.append(reasoningToken)
                    pendingReasoningCallbackChunks.append(reasoningToken)
                }

                if let contentToken, !contentToken.isEmpty {
                    fullContentCharacterCount += contentToken.count
                    guard fullContentCharacterCount <= Self.maxStreamingContentCharacters else {
                        await MainActor.run {
                            onError(AppLocalizations.string(
                                "aiService.streaming.contentTooLong",
                                defaultValue: "Response content is too long. Receiving has stopped."
                            ))
                        }
                        return nil
                    }
                    fullContentChunks.append(contentToken)
                    pendingContentCallbackChunks.append(contentToken)
                }

                if reasoningToken?.isEmpty == false || contentToken?.isEmpty == false {
                    await flushTokenCallbacks()
                }
            }

            await flushTokenCallbacks(force: true)
            return StreamedResponse(
                content: fullContentChunks.joined(),
                reasoningContent: fullReasoningChunks.joined()
            )
        } catch {
            if Task.isCancelled {
                return nil
            }

            await MainActor.run {
                let sanitizedMessage = Self.sanitizedErrorBody(
                    error.localizedDescription,
                    redacting: redactionValues
                )
                onError(AppLocalizations.format(
                    "aiService.streaming.requestFailed",
                    defaultValue: "Streaming request failed: %@",
                    arguments: [sanitizedMessage]
                ))
            }
            return nil
        }
    }

    private func sendToolEnabledMessage(
        message: String,
        imageAttachments: [ChatImageAttachment],
        imageContextDescription: String,
        fileAttachments: [ChatFileAttachment],
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
        usesImageAttachments: Bool,
        agentTools: [AgentToolDefinition],
        toolExecutor: @escaping (AgentToolCallRequest) async -> AgentToolCallResult,
        onToolExchangesUpdated: @escaping ([ChatToolExchange]) -> Void,
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ contentText: String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard apiFormat != .vertexAIExpress else {
            onError(AppLocalizations.string(
                "aiService.tools.vertexUnsupported",
                defaultValue: "Vertex Express does not support tool calls yet."
            ))
            return
        }

        let toolURL: URL
        let streamURL: URL
        do {
            toolURL = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: false,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
            )
            streamURL = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: true,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
            )
        } catch let error as AIServiceError {
            onError(error.localizedDescription)
            return
        } catch {
            onError(AppLocalizations.string("aiService.error.invalidBaseURL", defaultValue: "Invalid Base URL"))
            return
        }

        conversationHistory.append(
            ChatRequestMessage(
                role: "user",
                text: Self.textByAppendingRequestMetadata(message),
                imageAttachments: imageAttachments,
                imageContextDescription: imageContextDescription,
                fileAttachments: fileAttachments,
                usesImageAttachments: usesImageAttachments
            )
        )

        let toolsByName = Dictionary(
            agentTools.map { ($0.functionName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let redactionValues = Self.redactionValues(apiKey: apiKey, customHeaders: customHeaders)
        let preservesReasoningContext = Self.usesDeepSeekReasoningContext(
            apiFormat: apiFormat,
            baseURL: baseURL,
            model: model
        )

        streamingTask = Task {
            var workingMessages = conversationHistory
            var exchanges = [ChatToolExchange]()
            var executedToolCallCount = 0

            @MainActor
            func completeWithStreamingFinalAnswer() async {
                let finalJSONData: Data
                do {
                    finalJSONData = try requestBodyData(
                        apiFormat: apiFormat,
                        model: model,
                        messages: workingMessages,
                        stream: true,
                        reasoningEnabled: reasoningEnabled,
                        reasoningEffort: reasoningEffort,
                        modelParameters: modelParameters,
                        anthropicMaxTokens: anthropicMaxTokens,
                        anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
                    )
                } catch {
                    await MainActor.run {
                        onError(AppLocalizations.string("aiService.error.encodingFailed", defaultValue: "Failed to encode request body"))
                    }
                    streamingTask = nil
                    return
                }

                var finalRequest = makeRequest(
                    url: streamURL,
                    apiFormat: apiFormat,
                    model: model,
                    apiKey: apiKey,
                    customHeaders: customHeaders,
                    acceptsEventStream: true,
                    anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
                )
                finalRequest.httpBody = finalJSONData

                await MainActor.run {
                    onToolExchangesUpdated(exchanges)
                }

                guard let streamedResponse = await streamResponse(
                    request: finalRequest,
                    apiFormat: apiFormat,
                    redactionValues: redactionValues,
                    isReasoningDisplayActive: isReasoningDisplayActive,
                    onReasoningToken: onReasoningToken,
                    onContentToken: onContentToken,
                    onError: onError
                ) else {
                    streamingTask = nil
                    return
                }

                conversationHistory = workingMessages + [ChatRequestMessage(
                    role: "assistant",
                    text: streamedResponse.content,
                    reasoningContent: preservesReasoningContext ? streamedResponse.reasoningContent : "",
                    toolCalls: []
                )]
                await MainActor.run {
                    onComplete(streamedResponse.content)
                }
                streamingTask = nil
            }

            for _ in 0..<AgentTooling.maxToolRounds {
                guard !Task.isCancelled else { return }

                let jsonData: Data
                do {
                    jsonData = try requestBodyData(
                        apiFormat: apiFormat,
                        model: model,
                        messages: workingMessages,
                        stream: false,
                        reasoningEnabled: reasoningEnabled,
                        reasoningEffort: reasoningEffort,
                        modelParameters: modelParameters,
                        anthropicMaxTokens: anthropicMaxTokens,
                        anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
                        tools: agentTools
                    )
                } catch {
                    await MainActor.run {
                        onError(AppLocalizations.string("aiService.error.encodingFailed", defaultValue: "Failed to encode request body"))
                    }
                    streamingTask = nil
                    return
                }

                var request = makeRequest(
                    url: toolURL,
                    apiFormat: apiFormat,
                    model: model,
                    apiKey: apiKey,
                    customHeaders: customHeaders,
                    acceptsEventStream: false,
                    anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
                )
                request.httpBody = jsonData

                do {
                    let (data, response) = try await boundedResponseData(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode
                    let responseText = Self.responseText(from: data, redacting: redactionValues)

                    guard let statusCode, (200...299).contains(statusCode) else {
                        await MainActor.run {
                            onError(Self.errorMessage(
                                statusCode: statusCode,
                                body: responseText,
                                request: request,
                                redacting: redactionValues
                            ))
                        }
                        streamingTask = nil
                        return
                    }

                    guard let modelResponse = Self.toolModelResponse(from: data, apiFormat: apiFormat) else {
                        await MainActor.run {
                            onError(AppLocalizations.format(
                                "aiService.tools.decodingFailed",
                                defaultValue: "Failed to parse tool call response\n\n%@",
                                arguments: [responseText]
                            ))
                        }
                        streamingTask = nil
                        return
                    }

                    if modelResponse.toolCalls.isEmpty {
                        if exchanges.isEmpty {
                            let content = modelResponse.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AppLocalizations.string("chat.emptyAssistantReply", defaultValue: "No reply")
                                : modelResponse.content
                            conversationHistory = workingMessages + [ChatRequestMessage(
                                role: "assistant",
                                text: content,
                                reasoningContent: preservesReasoningContext ? modelResponse.reasoningContent : "",
                                toolCalls: []
                            )]
                            await MainActor.run {
                                if !modelResponse.reasoningContent.isEmpty {
                                    onReasoningToken(modelResponse.reasoningContent)
                                }
                                onToolExchangesUpdated(exchanges)
                                onContentToken(content)
                                onComplete(content)
                            }
                            streamingTask = nil
                            return
                        }

                        await completeWithStreamingFinalAnswer()
                        return
                    }

                    executedToolCallCount += modelResponse.toolCalls.count
                    if executedToolCallCount > AgentTooling.maxToolCalls {
                        await completeWithStreamingFinalAnswer()
                        return
                    }

                    let chatToolCalls = modelResponse.toolCalls.map { call -> ChatToolCall in
                        let tool = toolsByName[call.name]
                        return ChatToolCall(
                            id: call.id,
                            name: call.name,
                            displayName: tool?.displayName ?? call.name,
                            argumentsJSON: call.argumentsJSON,
                            mcpServerID: tool?.mcpServerID,
                            mcpServerName: tool?.mcpServerName ?? "",
                            mcpToolName: tool?.mcpToolName ?? call.name
                        )
                    }

                    workingMessages.append(ChatRequestMessage(
                        role: "assistant",
                        text: modelResponse.content,
                        reasoningContent: preservesReasoningContext ? modelResponse.reasoningContent : "",
                        toolCalls: chatToolCalls
                    ))

                    var exchange = ChatToolExchange(
                        assistantContent: modelResponse.content,
                        reasoningContent: modelResponse.reasoningContent,
                        toolCalls: chatToolCalls,
                        toolResults: []
                    )

                    for call in modelResponse.toolCalls {
                        guard let tool = toolsByName[call.name] else {
                            let result = ChatToolResult(
                                toolCallID: call.id,
                                name: call.name,
                                content: AppLocalizations.format(
                                    "aiService.tools.unknownToolRequested",
                                    defaultValue: "The model requested an unknown tool: %@",
                                    arguments: [call.name]
                                ),
                                isError: true
                            )
                            exchange.toolResults.append(result)
                            workingMessages.append(ChatRequestMessage(
                                toolCallID: call.id,
                                name: call.name,
                                content: result.content
                            ))
                            continue
                        }

                        let result = await toolExecutor(AgentToolCallRequest(
                            id: call.id,
                            functionName: call.name,
                            argumentsJSON: call.argumentsJSON,
                            tool: tool
                        ))
                        let limitedContent = String(result.content.prefix(AgentTooling.maxToolResultCharacters))
                        let chatResult = ChatToolResult(
                            toolCallID: call.id,
                            name: call.name,
                            content: limitedContent,
                            isError: result.isError
                        )
                        exchange.toolResults.append(chatResult)
                        workingMessages.append(ChatRequestMessage(
                            toolCallID: call.id,
                            name: call.name,
                            content: limitedContent
                        ))
                    }

                    exchanges.append(exchange)
                    await MainActor.run {
                        onToolExchangesUpdated(exchanges)
                    }
                } catch BoundedResponseDataError.responseTooLarge {
                    await MainActor.run {
                        onError(AppLocalizations.string(
                            "aiService.error.responseTooLarge",
                            defaultValue: "The response is too large and was rejected."
                        ))
                    }
                    streamingTask = nil
                    return
                } catch {
                    await MainActor.run {
                        let sanitizedMessage = Self.sanitizedErrorBody(
                            error.localizedDescription,
                            redacting: redactionValues
                        )
                        onError(AppLocalizations.format(
                            "aiService.tools.requestFailed",
                            defaultValue: "Tool call request failed: %@",
                            arguments: [sanitizedMessage]
                        ))
                    }
                    streamingTask = nil
                    return
                }
            }

            await completeWithStreamingFinalAnswer()
        }
    }

    private func makeRequest(
        url: URL,
        apiFormat: AIAPIFormat,
        model: String = "",
        apiKey: String,
        customHeaders: String,
        acceptsEventStream: Bool,
        anthropicClaudeCodeImpersonationEnabled: Bool = false
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if acceptsEventStream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesAnthropicClaudeCodeImpersonation = apiFormat == .anthropicMessages
            && anthropicClaudeCodeImpersonationEnabled
        let usesAnthropicOneMillionContext = apiFormat == .anthropicMessages
            && (anthropicClaudeCodeImpersonationEnabled || Self.anthropicModelSelection(from: model).usesOneMillionContext)

        if usesAnthropicClaudeCodeImpersonation {
            request.setValue("application/json", forHTTPHeaderField: "accept")
        }

        if !trimmedAPIKey.isEmpty {
            switch apiFormat {
            case .openAIChatCompletions, .openAIResponses:
                request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                if usesAnthropicClaudeCodeImpersonation {
                    request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "authorization")
                } else {
                    request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
                }
            case .vertexAIExpress:
                break
            }
        }

        if apiFormat == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        if usesAnthropicClaudeCodeImpersonation {
            request.setValue(Self.anthropicClaudeCodeBetaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue("true", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")
            request.setValue("claude-cli/2.1.156 (external, sdk-cli)", forHTTPHeaderField: "user-agent")
            request.setValue("cli", forHTTPHeaderField: "x-app")
            request.setValue(anthropicClaudeCodeMetadata.sessionID, forHTTPHeaderField: "x-claude-code-session-id")
            request.setValue("arm64", forHTTPHeaderField: "x-stainless-arch")
            request.setValue("js", forHTTPHeaderField: "x-stainless-lang")
            request.setValue("MacOS", forHTTPHeaderField: "x-stainless-os")
            request.setValue("0.94.0", forHTTPHeaderField: "x-stainless-package-version")
            request.setValue("0", forHTTPHeaderField: "x-stainless-retry-count")
            request.setValue("node", forHTTPHeaderField: "x-stainless-runtime")
            request.setValue("v24.3.0", forHTTPHeaderField: "x-stainless-runtime-version")
            request.setValue("600", forHTTPHeaderField: "x-stainless-timeout")
        } else if usesAnthropicOneMillionContext {
            request.setValue(Self.anthropicOneMillionContextBetaHeader, forHTTPHeaderField: "anthropic-beta")
        }

        for header in CustomHeaderSecurity.requestHeaders(from: customHeaders) {
            let headerName = header.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if (usesAnthropicClaudeCodeImpersonation && Self.isAnthropicClaudeCodeManagedHeader(headerName))
                || (usesAnthropicOneMillionContext && headerName == "anthropic-beta") {
                continue
            }
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        return request
    }

    private static func isAnthropicClaudeCodeManagedHeader(_ name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return anthropicClaudeCodeManagedHeaders.contains(normalizedName)
            || normalizedName.hasPrefix("x-stainless-")
    }

    private func thinkingConfig(from reasoningEnabled: Bool?) -> ThinkingConfig? {
        guard let reasoningEnabled else { return nil }
        return ThinkingConfig(type: reasoningEnabled ? "enabled" : "disabled")
    }

    private func requestURL(
        from urlString: String,
        apiFormat: AIAPIFormat,
        model: String,
        apiKey: String,
        isStreaming: Bool,
        anthropicClaudeCodeImpersonationEnabled: Bool = false
    ) throws -> URL {
        var resolvedURLString = urlString
        if apiFormat == .vertexAIExpress {
            let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            resolvedURLString = resolvedURLString.replacingOccurrences(of: "{model}", with: encodedModel)
        }

        let url = try Self.validatedRequestURL(from: resolvedURLString)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AIServiceError.invalidURL
        }

        if apiFormat == .vertexAIExpress {
            if isStreaming, components.path.hasSuffix(":generateContent") {
                components.path = String(components.path.dropLast(":generateContent".count)) + ":streamGenerateContent"
            }

            var queryItems = components.queryItems ?? []
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAPIKey.isEmpty {
                queryItems.removeAll { $0.name == "key" }
                queryItems.append(URLQueryItem(name: "key", value: trimmedAPIKey))
            }
            if isStreaming {
                queryItems.removeAll { $0.name == "alt" }
                queryItems.append(URLQueryItem(name: "alt", value: "sse"))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems
        }

        let usesAnthropicOneMillionContext = anthropicClaudeCodeImpersonationEnabled
            || Self.anthropicModelSelection(from: model).usesOneMillionContext
        if apiFormat == .anthropicMessages, usesAnthropicOneMillionContext {
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "beta" }
            queryItems.append(URLQueryItem(name: "beta", value: "true"))
            components.queryItems = queryItems
        }

        guard let requestURL = components.url else {
            throw AIServiceError.invalidURL
        }
        return requestURL
    }

    private static func decodedResponseText(from data: Data, apiFormat: AIAPIFormat) -> String? {
        let decoder = JSONDecoder()
        switch apiFormat {
        case .openAIChatCompletions:
            return (try? decoder.decode(OpenAIResponse.self, from: data))?
                .choices
                .first?
                .message
                .content
        case .openAIResponses:
            return (try? decoder.decode(OpenAIResponsesResponse.self, from: data))?.outputText
        case .anthropicMessages:
            return (try? decoder.decode(AnthropicResponse.self, from: data))?.outputText
        case .vertexAIExpress:
            return (try? decoder.decode(VertexGenerateContentResponse.self, from: data))?.outputText
        }
    }

    private struct ToolModelResponse {
        let content: String
        let reasoningContent: String
        let toolCalls: [ModelToolCall]
    }

    private struct StreamedResponse {
        let content: String
        let reasoningContent: String
    }

    private static func toolModelResponse(from data: Data, apiFormat: AIAPIFormat) -> ToolModelResponse? {
        let decoder = JSONDecoder()
        switch apiFormat {
        case .openAIChatCompletions:
            guard let message = (try? decoder.decode(OpenAIResponse.self, from: data))?
                .choices
                .first?
                .message else {
                return nil
            }
            let calls = message.toolCalls?.compactMap { call -> ModelToolCall? in
                guard let id = call.id,
                      let name = call.function?.name else {
                    return nil
                }
                return ModelToolCall(
                    id: id,
                    name: name,
                    argumentsJSON: call.function?.arguments ?? "{}"
                )
            } ?? []
            return ToolModelResponse(
                content: message.content,
                reasoningContent: message.reasoningContent ?? "",
                toolCalls: calls
            )
        case .openAIResponses:
            guard let response = try? decoder.decode(OpenAIResponsesResponse.self, from: data) else {
                return nil
            }
            return ToolModelResponse(
                content: response.outputText,
                reasoningContent: "",
                toolCalls: response.toolCalls
            )
        case .anthropicMessages:
            guard let response = try? decoder.decode(AnthropicResponse.self, from: data) else {
                return nil
            }
            return ToolModelResponse(
                content: response.outputText,
                reasoningContent: "",
                toolCalls: response.toolCalls
            )
        case .vertexAIExpress:
            guard let response = try? decoder.decode(VertexGenerateContentResponse.self, from: data) else {
                return nil
            }
            return ToolModelResponse(
                content: response.outputText,
                reasoningContent: "",
                toolCalls: []
            )
        }
    }

    private func modelsURL(from baseURL: String, apiFormat: AIAPIFormat, filtersTextChatModels: Bool) throws -> URL {
        let url = try Self.validatedRequestURL(from: baseURL)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AIServiceError.invalidURL
        }

        let path = components.path
        if apiFormat == .anthropicMessages {
            if path.hasSuffix("/v1/messages") {
                components.path = String(path.dropLast("/v1/messages".count)) + "/v1/models"
            } else if path.hasSuffix("/messages") {
                components.path = String(path.dropLast("/messages".count)) + "/models"
            } else {
                let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                components.path = basePath.isEmpty ? "/v1/models" : "/" + basePath + "/v1/models"
            }
        } else if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/responses") {
            components.path = String(path.dropLast("/responses".count)) + "/models"
        } else {
            let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty ? "/models" : "/" + basePath + "/models"
        }
        components.query = nil

        if filtersTextChatModels, apiFormat == .openAIChatCompletions {
            components.queryItems = [
                URLQueryItem(name: "type", value: "text"),
                URLQueryItem(name: "sub_type", value: "chat")
            ]
        }

        guard let modelsURL = components.url else {
            throw AIServiceError.invalidURL
        }
        return modelsURL
    }

    private nonisolated static func isTextChatModel(_ modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let nonChatKeywords = [
            "embedding",
            "embeddings",
            "embed",
            "rerank",
            "reranker",
            "ranker",
            "stable-diffusion",
            "sdxl",
            "flux",
            "kolors",
            "qwen-image",
            "image-edit",
            "text-to-image",
            "image-to-image",
            "cogvideo",
            "video",
            "wan",
            "audio",
            "speech",
            "voice",
            "tts",
            "whisper",
            "sensevoice",
            "funaudio",
            "cosyvoice",
            "fish-speech",
            "ocr"
        ]

        return !nonChatKeywords.contains { lowercasedID.contains($0) }
    }

    private nonisolated static func infersReasoningSupport(for modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let reasoningKeywords = [
            "deepseek-r1",
            "qwq",
            "qvq",
            "glm-z1",
            "glm-4.5",
            "glm-5",
            "o1",
            "o3",
            "o4",
            "gpt-5",
            "grok-3-mini",
            "grok-4",
            "magistral",
            "thinking",
            "deepseek-v4-pro"
        ]

        return reasoningKeywords.contains { lowercasedID.contains($0) }
    }

    private nonisolated static func infersImageSupport(for modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let imageInputKeywords = [
            "vision",
            "visual",
            "vl",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "qwen3-vl",
            "qwen3.5",
            "glm-4v",
            "glm-4.1v",
            "gpt-4o",
            "gpt-4.1",
            "gpt-5",
            "claude-3",
            "claude-4",
            "gemini",
            "llava",
            "internvl",
            "minicpm-v",
            "mllama",
            "pixtral"
        ]

        return imageInputKeywords.contains { lowercasedID.contains($0) }
    }

    private func boundedResponseData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        let expectedLength = response.expectedContentLength
        if expectedLength > Int64(Self.maxResponseByteCount) {
            throw BoundedResponseDataError.responseTooLarge
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(min(Int(expectedLength), Self.maxResponseByteCount))
        }

        for try await byte in bytes {
            guard data.count < Self.maxResponseByteCount else {
                throw BoundedResponseDataError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }

    private static func responseText(from data: Data?, redacting sensitiveValues: [String] = []) -> String {
        guard let data, !data.isEmpty else {
            return AppLocalizations.string("aiService.diagnostics.noResponseBody", defaultValue: "No response body")
        }
        guard data.count <= maxResponseByteCount else {
            return AppLocalizations.string(
                "aiService.diagnostics.responseHiddenTooLarge",
                defaultValue: "The response body exceeds the safety limit and was hidden."
            )
        }

        let text = String(data: data, encoding: .utf8)
            ?? AppLocalizations.string(
                "aiService.diagnostics.responseNotUTF8",
                defaultValue: "The response body is not UTF-8 text"
            )
        return sanitizedErrorBody(String(text.prefix(maxErrorBodyCharacters)), redacting: sensitiveValues)
    }

    private static func errorMessage(
        statusCode: Int?,
        body: String,
        request: URLRequest? = nil,
        redacting sensitiveValues: [String] = []
    ) -> String {
        let sanitizedBody = sanitizedErrorBody(
            String(body.prefix(maxErrorBodyCharacters)),
            redacting: sensitiveValues
        )
        let responseBodyDetail = sanitizedBody.contains("\n")
            ? AppLocalizations.format(
                "aiService.diagnostics.responseBodyMultiline",
                defaultValue: "Response body:\n%@",
                arguments: [sanitizedBody]
            )
            : AppLocalizations.format(
                "aiService.diagnostics.responseBody",
                defaultValue: "Response body: %@",
                arguments: [sanitizedBody]
            )
        let detailText = [
            requestDiagnosticText(for: request, redacting: sensitiveValues),
            responseBodyDetail
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        if let statusCode {
            return AppLocalizations.format(
                "aiService.diagnostics.requestFailedStatus",
                defaultValue: "Request failed, status code: %d\n\n%@",
                arguments: [statusCode, detailText]
            )
        }

        return AppLocalizations.format(
            "aiService.diagnostics.requestFailed",
            defaultValue: "Request failed\n\n%@",
            arguments: [detailText]
        )
    }

    private static func requestDiagnosticText(
        for request: URLRequest?,
        redacting sensitiveValues: [String]
    ) -> String? {
        guard let request else { return nil }

        var lines = [String]()
        if let method = request.httpMethod, !method.isEmpty {
            lines.append(AppLocalizations.format(
                "aiService.diagnostics.requestMethod",
                defaultValue: "Request method: %@",
                arguments: [method]
            ))
        }

        if let urlDescription = sanitizedRequestURLDescription(request.url) {
            lines.append(AppLocalizations.format(
                "aiService.diagnostics.requestURL",
                defaultValue: "Request URL: %@",
                arguments: [sanitizedErrorBody(urlDescription, redacting: sensitiveValues)]
            ))
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func sanitizedRequestURLDescription(_ url: URL?) -> String? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private static func collectErrorBody(
        from bytes: URLSession.AsyncBytes,
        maxCharacters: Int = 4_000,
        redacting sensitiveValues: [String] = []
    ) async -> String {
        var body = ""

        do {
            for try await line in bytes.lines {
                if !body.isEmpty {
                    body += "\n"
                }
                body += line
                if body.count >= maxCharacters {
                    return sanitizedErrorBody(String(body.prefix(maxCharacters)), redacting: sensitiveValues)
                }
            }
        } catch {
            return AppLocalizations.format(
                "aiService.diagnostics.errorBodyReadFailed",
                defaultValue: "Failed to read error response: %@",
                arguments: [error.localizedDescription]
            )
        }

        return body.isEmpty
            ? AppLocalizations.string("aiService.diagnostics.noResponseBody", defaultValue: "No response body")
            : sanitizedErrorBody(body, redacting: sensitiveValues)
    }

    private static func sanitizedErrorBody(_ body: String, redacting sensitiveValues: [String] = []) -> String {
        var sanitized = body
        for value in sensitiveValues where value.count >= 4 {
            sanitized = sanitized.replacingOccurrences(of: value, with: "[REDACTED]")
        }

        let replacements = [
            (#"(?i)(authorization\s*[:=]\s*(?:(?:bearer|basic)\s+)?)[A-Za-z0-9._\-+/=]{8,}"#, "$1[REDACTED]"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._\-+/=]{8,}"#, "$1[REDACTED]"),
            (#"(?i)(basic\s+)[A-Za-z0-9._\-+/=]{8,}"#, "$1[REDACTED]"),
            (#"(?i)((?:api[_-]?key|apikey|token|secret|password)["'\s:=]+)[^"',\s}]{8,}"#, "$1[REDACTED]"),
            (#"sk-[A-Za-z0-9_\-]{12,}"#, "sk-[REDACTED]")
        ]

        for replacement in replacements {
            sanitized = replacing(
                pattern: replacement.0,
                in: sanitized,
                template: replacement.1
            )
        }
        return sanitized
    }

    private static func redactionValues(apiKey: String, customHeaders: String) -> [String] {
        var values = CustomHeaderSecurity.sensitiveHeaderValues(from: customHeaders)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            values.append(trimmedAPIKey)
        }
        return Array(Set(values))
    }

    private static func replacing(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
