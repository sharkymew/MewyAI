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
}
