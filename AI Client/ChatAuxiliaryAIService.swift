//
//  ChatAuxiliaryAIService.swift
//  AI Client
//
//  Created by Codex on 2026/6/12.
//
import Foundation

final class ChatAuxiliaryAIService {
    private static let maxResponseByteCount = 2 * 1024 * 1024

    private enum BoundedResponseDataError: Error {
        case responseTooLarge
    }

    private let session: URLSession
    private let anthropicClaudeCodeMetadata = AnthropicClaudeCodeMetadata()

    init(session: URLSession = AIService.makeSecureSession()) {
        self.session = session
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

        sendAuxiliaryRequest(
            messages: titleMessages,
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
        ) { responseText in
            let title = Self.sanitizedConversationTitle(responseText)
                ?? Self.fallbackConversationTitle(from: messages)
            completion(title?.isEmpty == false ? title : nil)
        }
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
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping ([ChatMemoryOperation]?) -> Void
    ) {
        sendAuxiliaryMemoryRequest(
            systemPrompt: Self.memoryExtractionSystemPrompt,
            userPrompt: ChatMemoryStore.extractionUserPrompt(
                entries: memoryEntries,
                userText: userText,
                assistantText: assistantText
            ),
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
        ) { responseText in
            guard let responseText else {
                completion(nil)
                return
            }

            completion(ChatMemoryUpdateParser.operations(from: responseText))
        }
    }

    func generateMemorySummary(
        memoryEntries: [ChatMemoryEntry],
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
        completion: @escaping ([ChatMemorySummarySection]?) -> Void
    ) {
        guard !memoryEntries.isEmpty else {
            completion([])
            return
        }

        sendAuxiliaryMemoryRequest(
            systemPrompt: Self.memorySummarySystemPrompt,
            userPrompt: ChatMemoryStore.summaryUserPrompt(entries: memoryEntries),
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
        ) { responseText in
            guard let responseText else {
                completion(nil)
                return
            }

            completion(ChatMemorySummaryParser.sections(from: responseText))
        }
    }

    func proposeMemoryManagementOperations(
        memoryEntries: [ChatMemoryEntry],
        userInstruction: String,
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
        completion: @escaping ([ChatMemoryOperation]?) -> Void
    ) {
        let trimmedInstruction = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            completion([])
            return
        }

        sendAuxiliaryMemoryRequest(
            systemPrompt: Self.memoryManagementSystemPrompt,
            userPrompt: ChatMemoryStore.managementUserPrompt(
                entries: memoryEntries,
                userInstruction: trimmedInstruction
            ),
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
        ) { responseText in
            guard let responseText else {
                completion(nil)
                return
            }

            completion(ChatMemoryUpdateParser.operations(from: responseText))
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
        guard !imageAttachments.isEmpty else {
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

        sendAuxiliaryRequest(
            messages: descriptionMessages,
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
        ) { responseText in
            completion(Self.sanitizedImageContextDescription(responseText))
        }
    }

    private func sendAuxiliaryMemoryRequest(
        systemPrompt: String,
        userPrompt: String,
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
        let messages = [
            ChatRequestMessage(role: "system", text: systemPrompt),
            ChatRequestMessage(role: "user", text: userPrompt)
        ]

        sendAuxiliaryRequest(
            messages: messages,
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
            completion: completion
        )
    }

    private func sendAuxiliaryRequest(
        messages: [ChatRequestMessage],
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
        let url: URL
        do {
            url = try AIProviderRequestFactory.requestURL(
                from: baseURL,
                apiFormat: apiFormat,
                model: model,
                apiKey: apiKey,
                isStreaming: false,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled
            )
        } catch {
            completion(nil)
            return
        }

        let jsonData: Data
        do {
            jsonData = try AIRequestBodyBuilder.requestBodyData(
                apiFormat: apiFormat,
                model: model,
                messages: messages,
                stream: false,
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort,
                modelParameters: modelParameters,
                anthropicMaxTokens: anthropicMaxTokens,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
                anthropicClaudeCodeMetadata: anthropicClaudeCodeMetadata
            )
        } catch {
            completion(nil)
            return
        }

        var request = AIProviderRequestFactory.makeRequest(
            url: url,
            apiFormat: apiFormat,
            model: model,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
            anthropicClaudeCodeMetadata: anthropicClaudeCodeMetadata
        )
        request.httpBody = jsonData

        Task {
            do {
                let (data, response) = try await boundedResponseData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                DispatchQueue.main.async {
                    guard let statusCode,
                          (200...299).contains(statusCode),
                          let responseText = AIProviderRequestFactory.decodedResponseText(
                            from: data,
                            apiFormat: apiFormat
                          ) else {
                        completion(nil)
                        return
                    }

                    completion(responseText)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
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

    private static let memoryExtractionSystemPrompt = """
    You maintain the long-term memory of the user for a chat app. You receive the current memory list and the latest exchange of a conversation. Decide whether the exchange reveals durable facts about the user worth keeping across future conversations: stable preferences, ongoing projects, profession, important personal context, or corrections to existing memories.

    Output ONLY a JSON object, with no extra text, in this exact shape:
    {"operations":[{"action":"add","content":"…"},{"action":"update","index":2,"content":"…"},{"action":"delete","index":3}]}

    Rules:
    - "add": a new durable fact not covered by existing memories. Write one concise sentence in the user's primary language.
    - "update": refine, merge into, or correct the numbered existing memory.
    - "delete": remove a numbered memory that is wrong or that the user retracted; also use this when the user asks to forget something.
    - Never store one-off task details, transient questions, or secrets such as passwords and API keys.
    - Most exchanges contain nothing worth remembering; then output {"operations":[]}.
    """

    private static let memorySummarySystemPrompt = """
    You summarize the user's existing long-term memories for a memory management screen. You receive only the saved memory list. Group related memories into a small number of clear sections so the user can quickly review what the app currently remembers.

    Output ONLY a JSON object, with no extra text, in this exact shape:
    {"sections":[{"title":"Short title","body":"One concise paragraph."}]}

    Rules:
    - Use the user's primary language when it is clear from the memories.
    - Create short, specific titles and one paragraph per section.
    - Summarize only facts present in the memory list. Do not infer new facts.
    - Do not include secrets, credentials, raw API keys, or private tokens.
    - If there are no useful memories, output {"sections":[]}.
    """

    private static let memoryManagementSystemPrompt = """
    You update the user's long-term memory list for a chat app. You receive numbered existing memories and a direct memory-management instruction from the user. Propose the smallest safe set of operations needed to make the saved memories match the instruction.

    Output ONLY a JSON object, with no extra text, in this exact shape:
    {"operations":[{"action":"add","content":"…"},{"action":"update","index":2,"content":"…"},{"action":"delete","index":3}]}

    Rules:
    - "add": add one durable user fact or preference that is not already covered.
    - "update": rewrite a numbered memory to remove stale details, merge duplicates, or refine wording.
    - "delete": remove a numbered memory that should no longer be remembered or mentioned.
    - For instructions like "do not mention this" or "forget this", delete or rewrite the numbered memories that support that content. Do not add a new reminder to avoid mentioning it unless the user explicitly asks to store such a rule.
    - Never store secrets such as passwords, API keys, cookies, or private tokens.
    - If no safe memory change is needed, output {"operations":[]}.
    """

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
        if CharacterSet.alphanumerics.contains(scalar) {
            return true
        }

        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        case 0x2600...0x27BF, 0x1F000...0x1FAFF:
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
}
