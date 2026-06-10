import XCTest
@testable import MewyAI

final class ChatLaTeXSegmentParserTests: XCTestCase {
    func testSplitInlineMathKeepsCodeSpansAsText() {
        let segments = ChatLaTeXSegmentParser.splitInlineMath("A $x + 1$ and `code $no$`")

        XCTAssertEqual(segments, [
            .text("A "),
            .math(formula: "x + 1", displayMode: false),
            .text(" and `code $no$`")
        ])
    }

    func testSplitFindsDisplayMathOnly() {
        let segments = ChatLaTeXSegmentParser.split("before $$ x = 1 $$ after")

        XCTAssertEqual(segments, [
            .text("before "),
            .math(formula: "x = 1", displayMode: true),
            .text(" after")
        ])
    }

    func testContainsInlineMathIgnoresInlineCode() {
        XCTAssertTrue(ChatLaTeXSegmentParser.containsInlineMath(in: "value \\(x\\)"))
        XCTAssertFalse(ChatLaTeXSegmentParser.containsInlineMath(in: "`value \\(x\\)`"))
    }
}
