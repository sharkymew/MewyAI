//
//  AIRequestBodyBuilder.swift
//  AI Client
//
//  Created by Codex on 2026/6/12.
//
import Foundation

enum AIRequestBodyBuilder {
    nonisolated struct AnthropicModelSelection {
        let requestModel: String
        let usesOneMillionContext: Bool
    }

    private static let anthropicClaudeCodeSystemPrompt = "You are Claude Code, Anthropic's official CLI for Claude."

    private struct RequestContext {
        let model: String
        let messages: [ChatRequestMessage]
        let stream: Bool
        let reasoningEnabled: Bool?
        let reasoningEffort: ReasoningEffort?
        let modelParameters: AIModelConfiguration?
        let anthropicMaxTokens: Int
        let anthropicClaudeCodeImpersonationEnabled: Bool
        let anthropicClaudeCodeMetadata: AnthropicClaudeCodeMetadata?
        let tools: [AgentToolDefinition]
    }

    private protocol ProviderRequestAdapter {
        func requestBodyData(context: RequestContext, encoder: JSONEncoder) throws -> Data
    }

    private struct OpenAIChatCompletionsRequestAdapter: ProviderRequestAdapter {
        func requestBodyData(context: RequestContext, encoder: JSONEncoder) throws -> Data {
            try encoder.encode(OpenAIRequest(
                model: context.model,
                messages: context.messages,
                stream: context.stream,
                streamOptions: context.stream ? .includesUsage : nil,
                thinking: thinkingConfig(from: context.reasoningEnabled),
                reasoningEffort: context.reasoningEnabled == true ? context.reasoningEffort : nil,
                tools: openAITools(from: context.tools),
                temperature: context.modelParameters?.temperature,
                topP: context.modelParameters?.topP,
                maxTokens: context.modelParameters?.maxOutputTokens
            ))
        }
    }

    private struct OpenAIResponsesRequestAdapter: ProviderRequestAdapter {
        func requestBodyData(context: RequestContext, encoder: JSONEncoder) throws -> Data {
            let responseMessages = openAIResponsesMessages(from: context.messages)
            return try encoder.encode(OpenAIResponsesRequest(
                model: context.model,
                input: responseMessages.input,
                instructions: responseMessages.instructions,
                stream: context.stream,
                reasoning: context.reasoningEnabled == true ? context.reasoningEffort.map(OpenAIResponsesReasoning.init(effort:)) : nil,
                tools: openAIResponsesTools(from: context.tools),
                temperature: context.modelParameters?.temperature,
                topP: context.modelParameters?.topP,
                maxOutputTokens: context.modelParameters?.maxOutputTokens
            ))
        }
    }

    private struct AnthropicMessagesRequestAdapter: ProviderRequestAdapter {
        func requestBodyData(context: RequestContext, encoder: JSONEncoder) throws -> Data {
            let anthropicModel = anthropicModelSelection(from: context.model)
            let usesOneMillionContext = context.anthropicClaudeCodeImpersonationEnabled
                || anthropicModel.usesOneMillionContext
            let anthropicMessages = anthropicMessages(
                from: context.messages,
                usesClaudeCodeImpersonation: context.anthropicClaudeCodeImpersonationEnabled
            )
            return try encoder.encode(AnthropicMessagesRequest(
                model: anthropicModel.requestModel,
                maxTokens: usesOneMillionContext ? 64_000 : max(1, context.anthropicMaxTokens),
                messages: anthropicMessages.messages,
                system: anthropicMessages.system,
                stream: context.stream,
                tools: anthropicTools(from: context.tools),
                temperature: context.modelParameters?.temperature,
                topP: context.modelParameters?.topP,
                metadata: context.anthropicClaudeCodeImpersonationEnabled ? context.anthropicClaudeCodeMetadata : nil,
                contextManagement: usesOneMillionContext ? .claudeCodeDefault : nil
            ))
        }
    }

    private struct VertexAIExpressRequestAdapter: ProviderRequestAdapter {
        func requestBodyData(context: RequestContext, encoder: JSONEncoder) throws -> Data {
            let request = vertexRequest(
                from: context.messages,
                modelParameters: context.modelParameters
            )
            return try encoder.encode(request)
        }
    }

    static func requestBodyData(
        apiFormat: AIAPIFormat,
        model: String,
        messages: [ChatRequestMessage],
        stream: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        anthropicClaudeCodeMetadata: AnthropicClaudeCodeMetadata? = nil,
        tools: [AgentToolDefinition] = []
    ) throws -> Data {
        let context = RequestContext(
            model: model,
            messages: messages,
            stream: stream,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
            anthropicClaudeCodeMetadata: anthropicClaudeCodeMetadata,
            tools: tools
        )
        return try adapter(for: apiFormat).requestBodyData(context: context, encoder: JSONEncoder())
    }

    private static func adapter(for apiFormat: AIAPIFormat) -> ProviderRequestAdapter {
        switch apiFormat {
        case .openAIChatCompletions:
            OpenAIChatCompletionsRequestAdapter()
        case .openAIResponses:
            OpenAIResponsesRequestAdapter()
        case .anthropicMessages:
            AnthropicMessagesRequestAdapter()
        case .vertexAIExpress:
            VertexAIExpressRequestAdapter()
        }
    }

    nonisolated static func anthropicModelSelection(from model: String) -> AnthropicModelSelection {
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
                        input: jsonValue(from: call.argumentsJSON)
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

    private static func openAITools(from tools: [AgentToolDefinition]) -> [OpenAIToolDefinition]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            OpenAIToolDefinition(function: OpenAIFunctionDefinition(
                name: tool.functionName,
                description: tool.description,
                parameters: tool.inputSchema
            ))
        }
    }

    private static func openAIResponsesTools(from tools: [AgentToolDefinition]) -> [OpenAIResponsesToolDefinition]? {
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            OpenAIResponsesToolDefinition(
                name: tool.functionName,
                description: tool.description,
                parameters: tool.inputSchema
            )
        }
    }

    private static func anthropicTools(from tools: [AgentToolDefinition]) -> [AnthropicToolDefinition]? {
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

    private static func thinkingConfig(from reasoningEnabled: Bool?) -> ThinkingConfig? {
        guard let reasoningEnabled else { return nil }
        return ThinkingConfig(type: reasoningEnabled ? "enabled" : "disabled")
    }
}
