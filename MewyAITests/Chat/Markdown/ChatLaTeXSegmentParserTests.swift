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

    func testSplitFindsBracketDisplayMath() {
        let segments = ChatLaTeXSegmentParser.split("Energy:\n\\[E = mc^2\\]\nDone")

        XCTAssertEqual(segments, [
            .text("Energy:\n"),
            .math(formula: "E = mc^2", displayMode: true),
            .text("\nDone")
        ])
    }

    func testSplitFindsMultilineDisplayMath() {
        let segments = ChatLaTeXSegmentParser.split(
            """
            \\[\\int_{a}^{b} f(x) \\, dx = F(b)
            - F(a)\\]
            """
        )

        XCTAssertEqual(segments, [
            .math(
                formula: "\\int_{a}^{b} f(x) \\, dx = F(b)\n- F(a)",
                displayMode: true
            )
        ])
    }

    func testSplitFindsMatrixAndAlignedEnvironments() {
        let segments = ChatLaTeXSegmentParser.split(
            """
            \\[\\begin{pmatrix}
            a & b \\\\
            c & d
            \\end{pmatrix}\\]

            \\[\\begin{aligned}
            y &= (x + 1)^2 \\\\
              &= x^2 + 2x + 1
            \\end{aligned}\\]
            """
        )

        XCTAssertEqual(segments, [
            .math(
                formula: "\\begin{pmatrix}\na & b \\\\\nc & d\n\\end{pmatrix}",
                displayMode: true
            ),
            .text("\n\n"),
            .math(
                formula: "\\begin{aligned}\ny &= (x + 1)^2 \\\\\n  &= x^2 + 2x + 1\n\\end{aligned}",
                displayMode: true
            )
        ])
    }

    func testContainsInlineMathIgnoresInlineCode() {
        XCTAssertTrue(ChatLaTeXSegmentParser.containsInlineMath(in: "value \\(x\\)"))
        XCTAssertFalse(ChatLaTeXSegmentParser.containsInlineMath(in: "`value \\(x\\)`"))
    }
}
