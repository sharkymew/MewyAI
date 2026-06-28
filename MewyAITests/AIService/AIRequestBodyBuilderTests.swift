import XCTest
@testable import MewyAI

@MainActor
final class AIRequestBodyBuilderTests: XCTestCase {
    func testBuildsOpenAIChatCompletionRequestWithReasoningParametersAndTools() throws {
        let tool = AgentToolDefinition(
            functionName: "search_web",
            displayName: "Search Web",
            description: "Search the web.",
            inputSchema: .object(["type": .string("object")]),
            mcpServerID: UUID(),
            mcpServerName: "Search",
            mcpServerURL: "https://example.com",
            mcpToolName: "search",
            requiresApproval: false,
            authorizationToken: ""
        )

        let json = try jsonObject(from: AIRequestBodyBuilder.requestBodyData(
            apiFormat: .openAIChatCompletions,
            model: "gpt-5",
            messages: [ChatRequestMessage(role: "user", text: "Hello")],
            stream: true,
            reasoningEnabled: true,
            reasoningEffort: .high,
            modelParameters: AIModelConfiguration(
                name: "gpt-5",
                temperature: 0.2,
                topP: 0.8,
                maxOutputTokens: 123
            ),
            anthropicMaxTokens: 4096,
            tools: [tool]
        ))

        XCTAssertEqual(json["model"] as? String, "gpt-5")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual((json["stream_options"] as? [String: Any])?["include_usage"] as? Bool, true)
        XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "enabled")
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
        XCTAssertEqual(json["max_tokens"] as? Int, 123)
        XCTAssertEqual(
            (((json["tools"] as? [[String: Any]])?.first)?["function"] as? [String: Any])?["name"] as? String,
            "search_web"
        )
    }

    func testBuildsOpenAIChatCompletionRequestWithReasoningDisabled() throws {
        let json = try jsonObject(from: AIRequestBodyBuilder.requestBodyData(
            apiFormat: .openAIChatCompletions,
            model: "gpt-5",
            messages: [ChatRequestMessage(role: "user", text: "Hello")],
            stream: false,
            reasoningEnabled: false,
            reasoningEffort: .high,
            modelParameters: nil,
            anthropicMaxTokens: 4096
        ))

        XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertNil(json["reasoning_effort"])
        XCTAssertNil(json["stream_options"])
    }

    func testBuildsOpenAIResponsesRequestWithInstructionsAndToolMessages() throws {
        let tool = agentTool(
            functionName: "lookup_docs",
            description: "Look up docs."
        )
        let toolCall = ChatToolCall(
            id: "call_1",
            name: "lookup_docs",
            displayName: "Lookup Docs",
            argumentsJSON: "{\"query\":\"swift\"}"
        )
        let json = try jsonObject(from: AIRequestBodyBuilder.requestBodyData(
            apiFormat: .openAIResponses,
            model: "gpt-5",
            messages: [
                ChatRequestMessage(role: "system", text: "Be concise."),
                ChatRequestMessage(role: "user", text: "Find it"),
                ChatRequestMessage(
                    role: "assistant",
                    text: "",
                    reasoningContent: "",
                    toolCalls: [toolCall]
                ),
                ChatRequestMessage(toolCallID: "call_1", name: "lookup", content: "result")
            ],
            stream: false,
            reasoningEnabled: true,
            reasoningEffort: .medium,
            modelParameters: AIModelConfiguration(name: "gpt-5", maxOutputTokens: 321),
            anthropicMaxTokens: 4096,
            tools: [tool]
        ))

        XCTAssertEqual(json["instructions"] as? String, "Be concise.")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["max_output_tokens"] as? Int, 321)
        XCTAssertEqual((json["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["type"] as? String, "function")
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["name"] as? String, "lookup_docs")
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["description"] as? String, "Look up docs.")

        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["type"] as? String }, ["message", "function_call", "function_call_output"])
        XCTAssertEqual(input[1]["call_id"] as? String, "call_1")
        XCTAssertEqual(input[1]["name"] as? String, "lookup_docs")
        XCTAssertEqual(input[1]["arguments"] as? String, "{\"query\":\"swift\"}")
        XCTAssertEqual(input[2]["call_id"] as? String, "call_1")
        XCTAssertEqual(input[2]["output"] as? String, "result")
    }

    func testBuildsAnthropicRequestWithoutSpecialModelSuffixHandling() throws {
        let tool = agentTool(
            functionName: "lookup_docs",
            description: "Look up docs."
        )
        let toolCall = ChatToolCall(
            id: "call_1",
            name: "lookup_docs",
            displayName: "Lookup Docs",
            argumentsJSON: "{\"query\":\"swift\"}"
        )
        let modelName = "claude-sonnet-4 " + "[1" + "m]"
        let json = try jsonObject(from: AIRequestBodyBuilder.requestBodyData(
            apiFormat: .anthropicMessages,
            model: modelName,
            messages: [
                ChatRequestMessage(role: "system", text: "Be precise."),
                ChatRequestMessage(role: "user", text: "Hello"),
                ChatRequestMessage(
                    role: "assistant",
                    text: "I will look it up.",
                    reasoningContent: "",
                    toolCalls: [toolCall]
                ),
                ChatRequestMessage(toolCallID: "call_1", name: "lookup_docs", content: "result")
            ],
            stream: true,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            tools: [tool]
        ))

        XCTAssertEqual(json["model"] as? String, modelName)
        XCTAssertEqual(json["max_tokens"] as? Int, 4096)
        XCTAssertEqual(json["system"] as? String, "Be precise.")
        XCTAssertNil(json["context" + "_management"])
        XCTAssertNil(json["metadata"])
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["name"] as? String, "lookup_docs")
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.first?["description"] as? String, "Look up docs.")
        XCTAssertNotNil((json["tools"] as? [[String: Any]])?.first?["input_schema"] as? [String: Any])

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")

        let assistantContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.map { $0["type"] as? String }, ["text", "tool_use"])
        XCTAssertEqual(assistantContent[0]["text"] as? String, "I will look it up.")
        XCTAssertEqual(assistantContent[1]["id"] as? String, "call_1")
        XCTAssertEqual(assistantContent[1]["name"] as? String, "lookup_docs")
        XCTAssertEqual((assistantContent[1]["input"] as? [String: Any])?["query"] as? String, "swift")

        XCTAssertEqual(messages[2]["role"] as? String, "user")
        let toolResultContent = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(toolResultContent.first?["type"] as? String, "tool_result")
        XCTAssertEqual(toolResultContent.first?["tool_use_id"] as? String, "call_1")
        XCTAssertEqual(toolResultContent.first?["content"] as? String, "result")
    }

    func testBuildsVertexRequestWithSystemInstructionAndGenerationConfig() throws {
        let json = try jsonObject(from: AIRequestBodyBuilder.requestBodyData(
            apiFormat: .vertexAIExpress,
            model: "gemini-2.5-pro",
            messages: [
                ChatRequestMessage(role: "system", text: "Be helpful."),
                ChatRequestMessage(role: "assistant", text: "Previous answer"),
                ChatRequestMessage(role: "user", text: "Next question")
            ],
            stream: false,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            modelParameters: AIModelConfiguration(
                name: "gemini-2.5-pro",
                temperature: 0.4,
                topP: 0.9,
                maxOutputTokens: 555
            ),
            anthropicMaxTokens: 4096
        ))

        XCTAssertNotNil(json["system_instruction"])

        let generationConfig = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["temperature"] as? Double, 0.4)
        XCTAssertEqual(generationConfig["topP"] as? Double, 0.9)
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 555)

        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["model", "user"])
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func agentTool(functionName: String, description: String) -> AgentToolDefinition {
        AgentToolDefinition(
            functionName: functionName,
            displayName: functionName,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string")
                    ])
                ])
            ]),
            mcpServerID: UUID(),
            mcpServerName: "Docs",
            mcpServerURL: "https://example.com/mcp",
            mcpToolName: functionName,
            requiresApproval: false,
            authorizationToken: ""
        )
    }
}
