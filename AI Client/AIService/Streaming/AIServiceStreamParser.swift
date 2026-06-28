//
//  AIServiceStreamParser.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

/// One incremental piece of a streamed tool call, normalized across API
/// formats. Fragments with the same `index` belong to the same call; the
/// first fragment carries `id`/`name`, later ones append `argumentsDelta`.
nonisolated struct AIServiceStreamToolCallFragment: Equatable {
    let index: Int
    let id: String?
    let name: String?
    let argumentsDelta: String?
}

nonisolated struct AIServiceStreamParseResult {
    let reasoningToken: String?
    let contentToken: String?
    let usage: ChatUsage?
    let isDone: Bool
    let errorMessage: String?
    let toolCallFragments: [AIServiceStreamToolCallFragment]
    let completedToolCalls: [ModelToolCall]?

    init(
        reasoningToken: String?,
        contentToken: String?,
        usage: ChatUsage? = nil,
        isDone: Bool,
        errorMessage: String?,
        toolCallFragments: [AIServiceStreamToolCallFragment] = [],
        completedToolCalls: [ModelToolCall]? = nil
    ) {
        self.reasoningToken = reasoningToken
        self.contentToken = contentToken
        self.usage = usage
        self.isDone = isDone
        self.errorMessage = errorMessage
        self.toolCallFragments = toolCallFragments
        self.completedToolCalls = completedToolCalls
    }
}

nonisolated enum AIServiceStreamParser {
    static func parseResult(
        from jsonString: String,
        apiFormat: AIAPIFormat,
        decoder: JSONDecoder = JSONDecoder()
    ) -> AIServiceStreamParseResult? {
        if jsonString == "[DONE]" {
            return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: true, errorMessage: nil)
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }
        return adapter(for: apiFormat).parse(data: data, decoder: decoder)
    }

    /// Assembles complete tool calls from accumulated stream fragments,
    /// ordered by fragment index. Calls without an id or name are dropped.
    static func assembledToolCalls(
        from fragmentsByIndex: [Int: [AIServiceStreamToolCallFragment]]
    ) -> [ModelToolCall] {
        fragmentsByIndex
            .sorted { $0.key < $1.key }
            .compactMap { _, fragments in
                let id = fragments.compactMap(\.id).first
                let name = fragments.compactMap(\.name).first
                guard let id, let name else { return nil }

                let arguments = fragments.compactMap(\.argumentsDelta).joined()
                return ModelToolCall(
                    id: id,
                    name: name,
                    argumentsJSON: arguments.isEmpty ? "{}" : arguments
                )
            }
    }

    private static func adapter(for apiFormat: AIAPIFormat) -> StreamProviderAdapter {
        switch apiFormat {
        case .openAIChatCompletions:
            OpenAIChatCompletionsStreamAdapter()
        case .openAIResponses:
            OpenAIResponsesStreamAdapter()
        case .anthropicMessages:
            AnthropicMessagesStreamAdapter()
        case .vertexAIExpress:
            VertexAIExpressStreamAdapter()
        }
    }

    private protocol StreamProviderAdapter {
        func parse(data: Data, decoder: JSONDecoder) -> AIServiceStreamParseResult?
    }

    private struct OpenAIChatCompletionsStreamAdapter: StreamProviderAdapter {
        func parse(data: Data, decoder: JSONDecoder) -> AIServiceStreamParseResult? {
            guard let decoded = try? decoder.decode(OpenAIStreamResponse.self, from: data) else { return nil }
            let delta = decoded.choices?.first?.delta
            let fragments = (delta?.toolCalls ?? []).enumerated().map { position, fragment in
                AIServiceStreamToolCallFragment(
                    index: fragment.index ?? position,
                    id: fragment.id,
                    name: fragment.function?.name,
                    argumentsDelta: fragment.function?.arguments
                )
            }
            return AIServiceStreamParseResult(
                reasoningToken: delta?.reasoningContent,
                contentToken: delta?.content,
                usage: decoded.usage?.chatUsage,
                isDone: false,
                errorMessage: nil,
                toolCallFragments: fragments
            )
        }
    }

    private struct OpenAIResponsesStreamAdapter: StreamProviderAdapter {
        func parse(data: Data, decoder: JSONDecoder) -> AIServiceStreamParseResult? {
            guard let event = try? decoder.decode(OpenAIResponsesStreamEvent.self, from: data) else { return nil }
            if let message = event.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let type = event.type ?? ""
            return AIServiceStreamParseResult(
                reasoningToken: type == "response.reasoning_summary_text.delta" ? event.delta : nil,
                contentToken: type == "response.output_text.delta" ? event.delta : nil,
                usage: type == "response.completed" ? event.response?.usage?.chatUsage : nil,
                isDone: type == "response.completed",
                errorMessage: nil,
                completedToolCalls: type == "response.completed" ? event.completedToolCalls : nil
            )
        }
    }

    private struct AnthropicMessagesStreamAdapter: StreamProviderAdapter {
        func parse(data: Data, decoder: JSONDecoder) -> AIServiceStreamParseResult? {
            guard let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) else { return nil }
            if let message = event.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let eventType = event.type ?? ""
            let deltaType = event.delta?.type ?? ""
            let usage: ChatUsage? = switch eventType {
            case "message_start":
                event.message?.usage?.chatUsage
            case "message_delta":
                event.usage?.chatUsage
            default:
                nil
            }

            var fragments = [AIServiceStreamToolCallFragment]()
            if eventType == "content_block_start",
               event.contentBlock?.type == "tool_use",
               let blockIndex = event.index {
                fragments.append(AIServiceStreamToolCallFragment(
                    index: blockIndex,
                    id: event.contentBlock?.id,
                    name: event.contentBlock?.name,
                    argumentsDelta: nil
                ))
            } else if eventType == "content_block_delta",
                      deltaType == "input_json_delta",
                      let blockIndex = event.index {
                fragments.append(AIServiceStreamToolCallFragment(
                    index: blockIndex,
                    id: nil,
                    name: nil,
                    argumentsDelta: event.delta?.partialJSON
                ))
            }

            return AIServiceStreamParseResult(
                reasoningToken: eventType == "content_block_delta" && deltaType == "thinking_delta" ? event.delta?.thinking : nil,
                contentToken: eventType == "content_block_delta" && deltaType == "text_delta" ? event.delta?.text : nil,
                usage: usage,
                isDone: eventType == "message_stop",
                errorMessage: nil,
                toolCallFragments: fragments
            )
        }
    }

    private struct VertexAIExpressStreamAdapter: StreamProviderAdapter {
        func parse(data: Data, decoder: JSONDecoder) -> AIServiceStreamParseResult? {
            guard let response = try? decoder.decode(VertexGenerateContentResponse.self, from: data) else { return nil }
            if let message = response.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let text = response.outputText
            return AIServiceStreamParseResult(
                reasoningToken: nil,
                contentToken: text.isEmpty ? nil : text,
                usage: response.usageMetadata?.chatUsage,
                isDone: false,
                errorMessage: nil
            )
        }
    }
}
