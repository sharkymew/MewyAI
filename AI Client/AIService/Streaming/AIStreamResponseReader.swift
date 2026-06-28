//
//  AIStreamResponseReader.swift
//  AI Client
//
//  Created by Codex on 2026/6/12.
//
import Foundation

nonisolated struct AIStreamedResponse {
    let content: String
    let reasoningContent: String
    let usage: ChatUsage?
    let toolCalls: [ModelToolCall]

    init(
        content: String,
        reasoningContent: String,
        usage: ChatUsage?,
        toolCalls: [ModelToolCall] = []
    ) {
        self.content = content
        self.reasoningContent = reasoningContent
        self.usage = usage
        self.toolCalls = toolCalls
    }
}

nonisolated enum AIStreamResponseReader {
    private static let visibleReasoningCallbackFlushInterval: TimeInterval = 0.016
    private static let hiddenReasoningCallbackFlushInterval: TimeInterval = 0.50
    private static let contentCallbackFlushInterval: TimeInterval = 0.016
    private static let reasoningVisibilityCheckInterval: TimeInterval = 0.05

    static func read(
        session: URLSession,
        request: URLRequest,
        apiFormat: AIAPIFormat,
        redactionValues: [String],
        maxContentCharacters: Int,
        maxReasoningCharacters: Int,
        isReasoningDisplayActive: @escaping @MainActor () -> Bool,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        errorMessage: @escaping (Int?, String, URLRequest?, [String]) -> String,
        sanitizedErrorBody: @escaping (String, [String]) -> String
    ) async -> AIStreamedResponse? {
        do {
            let (bytes, response) = try await session.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorBody = await collectErrorBody(
                    from: bytes,
                    redacting: redactionValues,
                    sanitizedErrorBody: sanitizedErrorBody
                )
                await MainActor.run {
                    onError(errorMessage(
                        httpResponse.statusCode,
                        errorBody,
                        request,
                        redactionValues
                    ))
                }
                return nil
            }

            var state = StreamReadState()
            let streamDecoder = JSONDecoder()

            func refreshReasoningVisibilityIfNeeded(force: Bool = false, now: Date) async {
                guard force
                        || now.timeIntervalSince(state.lastReasoningVisibilityCheckDate) >= reasoningVisibilityCheckInterval else {
                    return
                }

                state.cachedIsReasoningDisplayActive = await MainActor.run {
                    isReasoningDisplayActive()
                }
                state.lastReasoningVisibilityCheckDate = now
            }

            func flushTokenCallbacks(force: Bool = false) async {
                guard !state.pendingReasoningCallbackChunks.isEmpty
                        || !state.pendingContentCallbackChunks.isEmpty else {
                    return
                }

                let now = Date()

                if !state.pendingReasoningCallbackChunks.isEmpty {
                    await refreshReasoningVisibilityIfNeeded(force: force, now: now)
                }

                var reasoningText = ""
                var contentText = ""

                if !state.pendingReasoningCallbackChunks.isEmpty {
                    let reasoningFlushInterval = state.cachedIsReasoningDisplayActive
                        ? visibleReasoningCallbackFlushInterval
                        : hiddenReasoningCallbackFlushInterval

                    if force || now.timeIntervalSince(state.lastReasoningCallbackFlushDate) >= reasoningFlushInterval {
                        reasoningText = state.pendingReasoningCallbackChunks.joined()
                        state.pendingReasoningCallbackChunks.removeAll(keepingCapacity: true)
                        state.lastReasoningCallbackFlushDate = now
                    }
                }

                if !state.pendingContentCallbackChunks.isEmpty,
                   force || now.timeIntervalSince(state.lastContentCallbackFlushDate) >= contentCallbackFlushInterval {
                    contentText = state.pendingContentCallbackChunks.joined()
                    state.pendingContentCallbackChunks.removeAll(keepingCapacity: true)
                    state.lastContentCallbackFlushDate = now
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
                    let sanitizedMessage = sanitizedErrorBody(errorMessage, redactionValues)
                    await MainActor.run {
                        onError(sanitizedMessage)
                    }
                    return nil
                }

                if let eventUsage = streamResult.usage {
                    state.collectedUsage = (state.collectedUsage ?? ChatUsage()).merging(eventUsage)
                }

                for fragment in streamResult.toolCallFragments {
                    state.toolCallFragmentsByIndex[fragment.index, default: []].append(fragment)
                }
                if let eventToolCalls = streamResult.completedToolCalls, !eventToolCalls.isEmpty {
                    state.completedToolCalls = eventToolCalls
                }

                if streamResult.isDone {
                    await flushTokenCallbacks(force: true)
                    return state.response()
                }

                let reasoningToken = streamResult.reasoningToken
                let contentToken = streamResult.contentToken

                if let reasoningToken, !reasoningToken.isEmpty {
                    state.reasoningCharacterCount += reasoningToken.count
                    guard state.reasoningCharacterCount <= maxReasoningCharacters else {
                        await MainActor.run {
                            onError(AppLocalizations.string(
                                "aiService.streaming.reasoningTooLong",
                                defaultValue: "Reasoning content is too long. Receiving has stopped."
                            ))
                        }
                        return nil
                    }
                    state.fullReasoningChunks.append(reasoningToken)
                    state.pendingReasoningCallbackChunks.append(reasoningToken)
                }

                if let contentToken, !contentToken.isEmpty {
                    state.fullContentCharacterCount += contentToken.count
                    guard state.fullContentCharacterCount <= maxContentCharacters else {
                        await MainActor.run {
                            onError(AppLocalizations.string(
                                "aiService.streaming.contentTooLong",
                                defaultValue: "Response content is too long. Receiving has stopped."
                            ))
                        }
                        return nil
                    }
                    state.fullContentChunks.append(contentToken)
                    state.pendingContentCallbackChunks.append(contentToken)
                }

                if reasoningToken?.isEmpty == false || contentToken?.isEmpty == false {
                    await flushTokenCallbacks()
                }
            }

            await flushTokenCallbacks(force: true)
            return state.response()
        } catch {
            if Task.isCancelled {
                return nil
            }

            await MainActor.run {
                let sanitizedMessage = sanitizedErrorBody(
                    error.localizedDescription,
                    redactionValues
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

    private static func collectErrorBody(
        from bytes: URLSession.AsyncBytes,
        maxCharacters: Int = 4_000,
        redacting sensitiveValues: [String],
        sanitizedErrorBody: (String, [String]) -> String
    ) async -> String {
        var body = ""

        do {
            for try await line in bytes.lines {
                if !body.isEmpty {
                    body += "\n"
                }
                body += line
                if body.count >= maxCharacters {
                    return sanitizedErrorBody(String(body.prefix(maxCharacters)), sensitiveValues)
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
            : sanitizedErrorBody(body, sensitiveValues)
    }

    private struct StreamReadState {
        var fullReasoningChunks: [String] = []
        var fullContentChunks: [String] = []
        var collectedUsage: ChatUsage?
        var toolCallFragmentsByIndex: [Int: [AIServiceStreamToolCallFragment]] = [:]
        var completedToolCalls: [ModelToolCall]?
        var pendingReasoningCallbackChunks: [String] = []
        var pendingContentCallbackChunks: [String] = []
        var fullContentCharacterCount = 0
        var reasoningCharacterCount = 0
        var lastReasoningCallbackFlushDate = Date.distantPast
        var lastContentCallbackFlushDate = Date.distantPast
        var lastReasoningVisibilityCheckDate = Date.distantPast
        var cachedIsReasoningDisplayActive = false

        func response() -> AIStreamedResponse {
            AIStreamedResponse(
                content: fullContentChunks.joined(),
                reasoningContent: fullReasoningChunks.joined(),
                usage: collectedUsage,
                toolCalls: completedToolCalls
                    ?? AIServiceStreamParser.assembledToolCalls(from: toolCallFragmentsByIndex)
            )
        }
    }
}
