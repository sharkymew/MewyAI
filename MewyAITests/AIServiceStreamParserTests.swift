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
}
