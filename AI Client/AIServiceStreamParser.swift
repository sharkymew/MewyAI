//
//  AIServiceStreamParser.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

nonisolated struct AIServiceStreamParseResult {
    let reasoningToken: String?
    let contentToken: String?
    let isDone: Bool
    let errorMessage: String?
}

enum AIServiceStreamParser {
    static func parseResult(
        from jsonString: String,
        apiFormat: AIAPIFormat,
        decoder: JSONDecoder = JSONDecoder()
    ) -> AIServiceStreamParseResult? {
        if jsonString == "[DONE]" {
            return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: true, errorMessage: nil)
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }
        switch apiFormat {
        case .openAIChatCompletions:
            guard let decoded = try? decoder.decode(OpenAIStreamResponse.self, from: data) else { return nil }
            let delta = decoded.choices.first?.delta
            return AIServiceStreamParseResult(
                reasoningToken: delta?.reasoningContent,
                contentToken: delta?.content,
                isDone: false,
                errorMessage: nil
            )
        case .openAIResponses:
            guard let event = try? decoder.decode(OpenAIResponsesStreamEvent.self, from: data) else { return nil }
            if let message = event.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let type = event.type ?? ""
            return AIServiceStreamParseResult(
                reasoningToken: type == "response.reasoning_summary_text.delta" ? event.delta : nil,
                contentToken: type == "response.output_text.delta" ? event.delta : nil,
                isDone: type == "response.completed",
                errorMessage: nil
            )
        case .anthropicMessages:
            guard let event = try? decoder.decode(AnthropicStreamEvent.self, from: data) else { return nil }
            if let message = event.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let eventType = event.type ?? ""
            let deltaType = event.delta?.type ?? ""
            return AIServiceStreamParseResult(
                reasoningToken: eventType == "content_block_delta" && deltaType == "thinking_delta" ? event.delta?.thinking : nil,
                contentToken: eventType == "content_block_delta" && deltaType == "text_delta" ? event.delta?.text : nil,
                isDone: eventType == "message_stop",
                errorMessage: nil
            )
        case .vertexAIExpress:
            guard let response = try? decoder.decode(VertexGenerateContentResponse.self, from: data) else { return nil }
            if let message = response.error?.message {
                return AIServiceStreamParseResult(reasoningToken: nil, contentToken: nil, isDone: false, errorMessage: message)
            }
            let text = response.outputText
            return AIServiceStreamParseResult(
                reasoningToken: nil,
                contentToken: text.isEmpty ? nil : text,
                isDone: false,
                errorMessage: nil
            )
        }
    }
}
