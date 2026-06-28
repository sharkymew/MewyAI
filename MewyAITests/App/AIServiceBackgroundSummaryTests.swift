import XCTest
@testable import MewyAI

final class AIServiceBackgroundSummaryTests: XCTestCase {
    func testSanitizedBackgroundCompletionSummaryRemovesFormatting() {
        XCTAssertEqual(
            AIService.sanitizedBackgroundCompletionSummary(#"**「任務完成」**"#),
            "任務完成"
        )
    }

    func testSanitizedBackgroundCompletionSummaryStripsSummaryPrefix() {
        XCTAssertEqual(
            AIService.sanitizedBackgroundCompletionSummary("摘要：任務完成"),
            "任務完成"
        )
    }

    func testSanitizedBackgroundCompletionSummaryRejectsSpecialTokens() {
        XCTAssertNil(
            AIService.sanitizedBackgroundCompletionSummary("<|im_start|>任務完成")
        )
    }

    func testSanitizedBackgroundCompletionSummaryReturnsNilForEmptyText() {
        XCTAssertNil(AIService.sanitizedBackgroundCompletionSummary("   \n  "))
    }

    func testFallbackBackgroundCompletionSummaryKeepsNaturalSentence() {
        let responseText = "已完成資料整理，以下是完整內容。"

        XCTAssertEqual(
            AIService.fallbackBackgroundCompletionSummary(from: responseText),
            responseText
        )
    }

    func testFallbackBackgroundCompletionSummaryCapsLengthWithEllipsis() {
        let longText = String(repeating: "好", count: 300)
        let summary = AIService.fallbackBackgroundCompletionSummary(from: longText)

        XCTAssertEqual(summary?.count, AIService.backgroundCompletionSummaryMaxLength + 1)
        XCTAssertEqual(summary?.hasSuffix("…"), true)
    }

    func testFallbackBackgroundCompletionSummarySkipsCodeBlocksAndBlockMarkers() {
        let responseText = """
        ## 结论
        修复方案如下：
        ```swift
        let x = 1
        ```
        - 第一步：检查权限
        """

        XCTAssertEqual(
            AIService.fallbackBackgroundCompletionSummary(from: responseText),
            "结论 修复方案如下： 第一步：检查权限"
        )
    }

    func testFallbackBackgroundCompletionSummaryReplacesLinksWithLinkText() {
        XCTAssertEqual(
            AIService.fallbackBackgroundCompletionSummary(from: "详见 [文档](https://example.com)。"),
            "详见 文档。"
        )
    }

    func testSanitizedBackgroundCompletionSummaryKeepsNonASCIIScripts() {
        XCTAssertEqual(
            AIService.sanitizedBackgroundCompletionSummary("résumé terminé"),
            "résumé terminé"
        )
        XCTAssertEqual(
            AIService.sanitizedBackgroundCompletionSummary("ありがとう完了"),
            "ありがとう完了"
        )
    }

    func testSanitizedBackgroundCompletionSummaryKeepsEmojiSummary() {
        XCTAssertEqual(
            AIService.sanitizedBackgroundCompletionSummary("✅ 完成"),
            "✅ 完成"
        )
    }
}
