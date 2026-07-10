//
//  AIService.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

class AIService {
    nonisolated private static let maxResponseByteCount = 2 * 1024 * 1024
    nonisolated private static let maxErrorBodyCharacters = 4_000
    nonisolated private static let maxStreamingContentCharacters = 200_000
    nonisolated private static let maxStreamingReasoningCharacters = 120_000

    nonisolated private enum BoundedResponseDataError: Error {
        case responseTooLarge
    }

    nonisolated private let session: URLSession
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

    func appendSystemContext(_ context: String) {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = conversationHistory.firstIndex(where: { $0.role == "system" }) {
            let existing = conversationHistory[index].content.plainText
            conversationHistory[index] = ChatRequestMessage(
                role: "system",
                text: existing + "\n\n" + trimmed
            )
        } else {
            conversationHistory.insert(ChatRequestMessage(role: "system", text: trimmed), at: 0)
        }
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
        tools: [AgentToolDefinition] = []
    ) throws -> Data {
        try AIRequestBodyBuilder.requestBodyData(
            apiFormat: apiFormat,
            model: model,
            messages: messages,
            stream: stream,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            tools: tools
        )
    }

    func fetchModels(
        baseURL: String,
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
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
            acceptsEventStream: false
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

    nonisolated static let backgroundCompletionSummaryMaxLength = 200

    nonisolated static func sanitizedBackgroundCompletionSummary(_ rawSummary: String?) -> String? {
        guard let rawSummary else { return nil }

        var summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [
            "摘要：", "摘要:", "总结：", "总结:", "通知：", "通知:",
            "Summary:", "Summary：", "Notification:", "Notification："
        ] where summary.hasPrefix(prefix) {
            summary.removeFirst(prefix.count)
            break
        }

        return backgroundCompletionNotificationBody(from: summary)
    }

    nonisolated static func fallbackBackgroundCompletionSummary(from responseText: String) -> String? {
        backgroundCompletionNotificationBody(from: responseText)
    }

    private nonisolated static func backgroundCompletionNotificationBody(from rawText: String) -> String? {
        var fragments: [String] = []
        var insideCodeFence = false
        var totalLength = 0

        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideCodeFence.toggle()
                continue
            }
            guard !insideCodeFence, !line.isEmpty, !containsSpecialTokenFragment(line) else { continue }

            let cleaned = strippedInlineMarkdown(strippedLeadingBlockMarkers(line))
            guard !cleaned.isEmpty else { continue }

            fragments.append(cleaned)
            totalLength += cleaned.count
            if totalLength >= backgroundCompletionSummaryMaxLength { break }
        }

        guard !fragments.isEmpty else { return nil }

        let joined = strippedWrappingQuotes(fragments.joined(separator: " "))
        guard !joined.isEmpty else { return nil }
        guard joined.count > backgroundCompletionSummaryMaxLength else { return joined }
        return String(joined.prefix(backgroundCompletionSummaryMaxLength)) + "…"
    }

    private nonisolated static func strippedWrappingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [
            ("「", "」"), ("『", "』"), ("“", "”"), ("‘", "’"),
            ("\"", "\""), ("'", "'"), ("【", "】"), ("《", "》"),
            ("（", "）"), ("(", ")"), ("[", "]")
        ]

        var result = Substring(text)
        var changed = true
        while changed, result.count > 2 {
            changed = false
            for (open, close) in pairs where result.first == open && result.last == close {
                let inner = result.dropFirst().dropLast()
                guard !inner.contains(open), !inner.contains(close) else { continue }
                result = inner
                changed = true
                break
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func strippedLeadingBlockMarkers(_ line: String) -> String {
        var text = Substring(line)
        var changed = true
        while changed {
            changed = false

            while text.first == ">" {
                text = text.dropFirst().drop(while: { $0 == " " })
                changed = true
            }

            let hashes = text.prefix(while: { $0 == "#" })
            if (1...6).contains(hashes.count), text.dropFirst(hashes.count).first == " " {
                text = text.dropFirst(hashes.count + 1)
                changed = true
            }

            if let first = text.first, "-*+".contains(first), text.dropFirst().first == " " {
                text = text.dropFirst(2).drop(while: { $0 == " " })
                changed = true
            }

            let digits = text.prefix(while: \.isNumber)
            if (1...3).contains(digits.count),
               let separator = text.dropFirst(digits.count).first, separator == "." || separator == ")",
               text.dropFirst(digits.count + 1).first == " " {
                text = text.dropFirst(digits.count + 2)
                changed = true
            }
        }

        return text.trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static let markdownLinkRegex = try! NSRegularExpression(
        pattern: #"!?\[([^\]]*)\]\([^)]*\)"#
    )

    private nonisolated static func strippedInlineMarkdown(_ text: String) -> String {
        var result = markdownLinkRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "$1"
        )
        for token in ["**", "__", "~~", "`", "*"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool = true,
        completion: @escaping (String) -> Void
    ) {
        sendMessageResult(
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
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            usesImageAttachments: usesImageAttachments
        ) { result in
            switch result {
            case .success(let text):
                completion(text)
            case .failure(let error):
                completion(error.localizedDescription)
            }
        }
    }

    func sendMessageResult(
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
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool = true,
        completion: @escaping (Result<String, AIServiceError>) -> Void
    ) {
        let url: URL
        do {
            url = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: false
            )
        } catch let error as AIServiceError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidBaseURL))
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
            anthropicMaxTokens: anthropicMaxTokens
        ) else {
            completion(.failure(.encodingFailed))
            return
        }

        var request = makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false
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
                    if let decodedText = Self.decodedResponseText(from: data, apiFormat: apiFormat) {
                        let text = decodedText.isEmpty
                            ? AppLocalizations.string("chat.emptyAssistantReply", defaultValue: "No reply")
                            : decodedText
                        self.conversationHistory.append(ChatRequestMessage(role: "assistant", text: text))
                        completion(.success(text))
                    } else {
                        completion(.failure(.decodingFailed(AppLocalizations.format(
                            "aiService.error.decodingFailed",
                            defaultValue: "Parsing failed\n\n%@",
                            arguments: [responseText]
                        ))))
                    }
                }
            } catch BoundedResponseDataError.responseTooLarge {
                DispatchQueue.main.async {
                    completion(.failure(.responseTooLarge))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.requestFailed(AppLocalizations.format(
                        "aiService.error.requestFailed",
                        defaultValue: "Request failed: %@",
                        arguments: [error.localizedDescription]
                    ))))
                }
            }
        }
    }

    func sendMessageAsync(
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
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool = true
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            sendMessageResult(
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
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort,
                usesImageAttachments: usesImageAttachments
            ) { result in
                continuation.resume(with: result)
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
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool,
        agentTools: [AgentToolDefinition] = [],
        toolExecutor: ((AgentToolCallRequest) async -> AgentToolCallResult)? = nil,
        onToolExchangesUpdated: @escaping ([ChatToolExchange]) -> Void = { _ in },
        onToolRoundReset: @escaping () -> Void = {},
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ contentText: String, _ usage: ChatUsage?) -> Void,
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
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort,
                usesImageAttachments: usesImageAttachments,
                agentTools: agentTools,
                toolExecutor: toolExecutor,
                onToolExchangesUpdated: onToolExchangesUpdated,
                onToolRoundReset: onToolRoundReset,
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
                isStreaming: true
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
            anthropicMaxTokens: anthropicMaxTokens
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
            acceptsEventStream: true
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
                onComplete(streamedResponse.content, streamedResponse.usage)
            }

            streamingTask = nil
        }
    }

    private nonisolated func streamResponse(
        request: URLRequest,
        apiFormat: AIAPIFormat,
        redactionValues: [String],
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) async -> AIStreamedResponse? {
        await AIStreamResponseReader.read(
            session: session,
            request: request,
            apiFormat: apiFormat,
            redactionValues: redactionValues,
            maxContentCharacters: Self.maxStreamingContentCharacters,
            maxReasoningCharacters: Self.maxStreamingReasoningCharacters,
            isReasoningDisplayActive: isReasoningDisplayActive,
            onReasoningToken: onReasoningToken,
            onContentToken: onContentToken,
            onError: onError,
            errorMessage: { statusCode, body, request, redactionValues in
                Self.errorMessage(
                    statusCode: statusCode,
                    body: body,
                    request: request,
                    redacting: redactionValues
                )
            },
            sanitizedErrorBody: { body, redactionValues in
                Self.sanitizedErrorBody(body, redacting: redactionValues)
            }
        )
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
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        usesImageAttachments: Bool,
        agentTools: [AgentToolDefinition],
        toolExecutor: @escaping (AgentToolCallRequest) async -> AgentToolCallResult,
        onToolExchangesUpdated: @escaping ([ChatToolExchange]) -> Void,
        onToolRoundReset: @escaping () -> Void,
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ contentText: String, _ usage: ChatUsage?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard apiFormat != .vertexAIExpress else {
            onError(AppLocalizations.string(
                "aiService.tools.vertexUnsupported",
                defaultValue: "Vertex Express does not support tool calls yet."
            ))
            return
        }

        let streamURL: URL
        do {
            streamURL = try requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: true
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
            var accumulatedUsage: ChatUsage?

            func accumulateUsage(_ usage: ChatUsage?) {
                guard let usage else { return }
                accumulatedUsage = accumulatedUsage?.adding(usage) ?? usage
            }

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
                        anthropicMaxTokens: anthropicMaxTokens
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
                    acceptsEventStream: true
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

                accumulateUsage(streamedResponse.usage)
                conversationHistory = workingMessages + [ChatRequestMessage(
                    role: "assistant",
                    text: streamedResponse.content,
                    reasoningContent: preservesReasoningContext ? streamedResponse.reasoningContent : "",
                    toolCalls: []
                )]
                await MainActor.run {
                    onComplete(streamedResponse.content, accumulatedUsage)
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
                        stream: true,
                        reasoningEnabled: reasoningEnabled,
                        reasoningEffort: reasoningEffort,
                        modelParameters: modelParameters,
                        anthropicMaxTokens: anthropicMaxTokens,
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
                    url: streamURL,
                    apiFormat: apiFormat,
                    model: model,
                    apiKey: apiKey,
                    customHeaders: customHeaders,
                    acceptsEventStream: true
                )
                request.httpBody = jsonData

                // Tool rounds stream like plain responses: content and
                // reasoning reach the UI live while tool-call fragments
                // accumulate. A round without tool calls IS the final answer.
                guard let modelResponse = await streamResponse(
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

                accumulateUsage(modelResponse.usage)

                if modelResponse.toolCalls.isEmpty {
                    var content = modelResponse.content
                    if exchanges.isEmpty,
                       content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        content = AppLocalizations.string("chat.emptyAssistantReply", defaultValue: "No reply")
                        let placeholderContent = content
                        await MainActor.run {
                            onContentToken(placeholderContent)
                        }
                    }

                    conversationHistory = workingMessages + [ChatRequestMessage(
                        role: "assistant",
                        text: content,
                        reasoningContent: preservesReasoningContext ? modelResponse.reasoningContent : "",
                        toolCalls: []
                    )]
                    let finalContent = content
                    await MainActor.run {
                        onToolExchangesUpdated(exchanges)
                        onComplete(finalContent, accumulatedUsage)
                    }
                    streamingTask = nil
                    return
                }

                executedToolCallCount += modelResponse.toolCalls.count
                if executedToolCallCount > AgentTooling.maxToolCalls {
                    await MainActor.run {
                        onToolRoundReset()
                    }
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

                // The streamed prefix now belongs to this exchange; clear the
                // live message display and show it inside the exchange instead.
                let pendingExchanges = exchanges + [exchange]
                await MainActor.run {
                    onToolRoundReset()
                    onToolExchangesUpdated(pendingExchanges)
                }

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
                let publishedExchanges = exchanges
                await MainActor.run {
                    onToolExchangesUpdated(publishedExchanges)
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
        acceptsEventStream: Bool
    ) -> URLRequest {
        AIProviderRequestFactory.makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: acceptsEventStream
        )
    }

    private func requestURL(
        from urlString: String,
        apiFormat: AIAPIFormat,
        model: String,
        apiKey: String,
        isStreaming: Bool
    ) throws -> URL {
        try AIProviderRequestFactory.requestURL(
            from: urlString,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            isStreaming: isStreaming
        )
    }

    private static func decodedResponseText(from data: Data, apiFormat: AIAPIFormat) -> String? {
        AIProviderRequestFactory.decodedResponseText(from: data, apiFormat: apiFormat)
    }

    private func modelsURL(from baseURL: String, apiFormat: AIAPIFormat, filtersTextChatModels: Bool) throws -> URL {
        try AIProviderRequestFactory.modelsURL(
            from: baseURL,
            apiFormat: apiFormat,
            filtersTextChatModels: filtersTextChatModels
        )
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

    private nonisolated func boundedResponseData(for request: URLRequest) async throws -> (Data, URLResponse) {
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

    private nonisolated static func responseText(from data: Data?, redacting sensitiveValues: [String] = []) -> String {
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

    private nonisolated static func errorMessage(
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

    private nonisolated static func requestDiagnosticText(
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

    private nonisolated static func sanitizedRequestURLDescription(_ url: URL?) -> String? {
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

    private nonisolated static func sanitizedErrorBody(_ body: String, redacting sensitiveValues: [String] = []) -> String {
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

    private nonisolated static func replacing(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
