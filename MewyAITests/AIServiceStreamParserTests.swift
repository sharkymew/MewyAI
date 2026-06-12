import XCTest
@testable import MewyAI

@MainActor
final class AIServiceStreamParserTests: XCTestCase {
    func testParsesOpenAIChatStreamingDelta() {
        let json = #"{"choices":[{"delta":{"reasoning_content":"thinking","content":"answer"}}]}"#

        let result = AIServiceStreamParser.parseResult(
            from: json,
            apiFormat: .openAIChatCompletions
        )

        XCTAssertEqual(result?.reasoningToken, "thinking")
        XCTAssertEqual(result?.contentToken, "answer")
        XCTAssertEqual(result?.isDone, false)
        XCTAssertNil(result?.errorMessage)
    }

    func testParsesAnthropicTextDeltaAndDoneMarker() {
        let json = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}"#

        let textResult = AIServiceStreamParser.parseResult(
            from: json,
            apiFormat: .anthropicMessages
        )
        let doneResult = AIServiceStreamParser.parseResult(
            from: "[DONE]",
            apiFormat: .anthropicMessages
        )

        XCTAssertNil(textResult?.reasoningToken)
        XCTAssertEqual(textResult?.contentToken, "hello")
        XCTAssertEqual(textResult?.isDone, false)
        XCTAssertEqual(doneResult?.isDone, true)
    }

    func testParsesOpenAIChatStreamingUsageChunkWithoutChoices() {
        let json = #"{"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":40,"total_tokens":140}}"#

        let result = AIServiceStreamParser.parseResult(
            from: json,
            apiFormat: .openAIChatCompletions
        )

        XCTAssertNil(result?.contentToken)
        XCTAssertEqual(result?.usage?.inputTokens, 100)
        XCTAssertEqual(result?.usage?.outputTokens, 40)
        XCTAssertEqual(result?.usage?.totalTokens, 140)
    }

    func testParsesAnthropicMessageStartAndDeltaUsage() {
        let startJSON = #"{"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1,"cache_read_input_tokens":10}}}"#
        let deltaJSON = #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":220}}"#

        let startResult = AIServiceStreamParser.parseResult(
            from: startJSON,
            apiFormat: .anthropicMessages
        )
        let deltaResult = AIServiceStreamParser.parseResult(
            from: deltaJSON,
            apiFormat: .anthropicMessages
        )

        XCTAssertEqual(startResult?.usage?.inputTokens, 35)
        XCTAssertEqual(startResult?.usage?.cacheReadInputTokens, 10)
        XCTAssertEqual(deltaResult?.usage?.outputTokens, 220)
        XCTAssertNil(deltaResult?.usage?.inputTokens)
    }

    func testParsesOpenAIResponsesCompletedUsage() {
        let json = #"{"type":"response.completed","response":{"usage":{"input_tokens":12,"output_tokens":34,"total_tokens":46}}}"#

        let result = AIServiceStreamParser.parseResult(
            from: json,
            apiFormat: .openAIResponses
        )

        XCTAssertEqual(result?.isDone, true)
        XCTAssertEqual(result?.usage?.inputTokens, 12)
        XCTAssertEqual(result?.usage?.outputTokens, 34)
    }

    func testParsesVertexUsageMetadata() {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"hi"}]}}],"usageMetadata":{"promptTokenCount":9,"candidatesTokenCount":11,"totalTokenCount":20}}"#

        let result = AIServiceStreamParser.parseResult(
            from: json,
            apiFormat: .vertexAIExpress
        )

        XCTAssertEqual(result?.contentToken, "hi")
        XCTAssertEqual(result?.usage?.inputTokens, 9)
        XCTAssertEqual(result?.usage?.outputTokens, 11)
        XCTAssertEqual(result?.usage?.totalTokens, 20)
    }

    func testParsesOpenAIChatToolCallFragments() {
        let firstJSON = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"chat_history_search","arguments":""}}]}}]}"#
        let deltaJSON = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"swift\"}"}}]}}]}"#

        let firstResult = AIServiceStreamParser.parseResult(from: firstJSON, apiFormat: .openAIChatCompletions)
        let deltaResult = AIServiceStreamParser.parseResult(from: deltaJSON, apiFormat: .openAIChatCompletions)

        XCTAssertEqual(firstResult?.toolCallFragments, [
            AIServiceStreamToolCallFragment(index: 0, id: "call_1", name: "chat_history_search", argumentsDelta: "")
        ])
        XCTAssertEqual(deltaResult?.toolCallFragments, [
            AIServiceStreamToolCallFragment(index: 0, id: nil, name: nil, argumentsDelta: #"{"query":"swift"}"#)
        ])
    }

    func testParsesAnthropicToolUseFragments() {
        let startJSON = #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"chat_history_read"}}"#
        let deltaJSON = #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"conversation_id\""}}"#
        let textStartJSON = #"{"type":"content_block_start","index":0,"content_block":{"type":"text"}}"#

        let startResult = AIServiceStreamParser.parseResult(from: startJSON, apiFormat: .anthropicMessages)
        let deltaResult = AIServiceStreamParser.parseResult(from: deltaJSON, apiFormat: .anthropicMessages)
        let textStartResult = AIServiceStreamParser.parseResult(from: textStartJSON, apiFormat: .anthropicMessages)

        XCTAssertEqual(startResult?.toolCallFragments, [
            AIServiceStreamToolCallFragment(index: 1, id: "toolu_1", name: "chat_history_read", argumentsDelta: nil)
        ])
        XCTAssertEqual(deltaResult?.toolCallFragments, [
            AIServiceStreamToolCallFragment(index: 1, id: nil, name: nil, argumentsDelta: #"{"conversation_id""#)
        ])
        XCTAssertEqual(textStartResult?.toolCallFragments, [])
    }

    func testParsesOpenAIResponsesCompletedToolCalls() {
        let json = #"{"type":"response.completed","response":{"output":[{"type":"function_call","call_id":"call_9","name":"chat_history_search","arguments":"{\"query\":\"memory\"}"},{"type":"message","content":[{"type":"output_text","text":"hi"}]}],"usage":{"input_tokens":5,"output_tokens":6,"total_tokens":11}}}"#

        let result = AIServiceStreamParser.parseResult(from: json, apiFormat: .openAIResponses)

        XCTAssertEqual(result?.isDone, true)
        XCTAssertEqual(result?.completedToolCalls, [
            ModelToolCall(id: "call_9", name: "chat_history_search", argumentsJSON: #"{"query":"memory"}"#)
        ])
    }

    func testAssemblesToolCallsFromFragmentsInIndexOrder() {
        let assembled = AIServiceStreamParser.assembledToolCalls(from: [
            1: [
                AIServiceStreamToolCallFragment(index: 1, id: "call_b", name: "tool_b", argumentsDelta: nil),
                AIServiceStreamToolCallFragment(index: 1, id: nil, name: nil, argumentsDelta: "{\"a\""),
                AIServiceStreamToolCallFragment(index: 1, id: nil, name: nil, argumentsDelta: ":1}")
            ],
            0: [
                AIServiceStreamToolCallFragment(index: 0, id: "call_a", name: "tool_a", argumentsDelta: "")
            ],
            2: [
                AIServiceStreamToolCallFragment(index: 2, id: nil, name: nil, argumentsDelta: "{}")
            ]
        ])

        XCTAssertEqual(assembled, [
            ModelToolCall(id: "call_a", name: "tool_a", argumentsJSON: "{}"),
            ModelToolCall(id: "call_b", name: "tool_b", argumentsJSON: #"{"a":1}"#)
        ])
    }
}
