import XCTest
@testable import MewyAI

@MainActor
final class ChatMemorySummaryParserTests: XCTestCase {
    func testParsesPlainJSONSummary() throws {
        let sections = try XCTUnwrap(ChatMemorySummaryParser.sections(from: """
        {"sections":[{"title":"工作方式","body":"用户偏好简短、直接的回答。"},{"title":"项目","body":"用户正在开发 iOS 应用。"}]}
        """))

        XCTAssertEqual(sections.map(\.title), ["工作方式", "项目"])
        XCTAssertEqual(sections.map(\.body), ["用户偏好简短、直接的回答。", "用户正在开发 iOS 应用。"])
    }

    func testParsesJSONWrappedInCodeFence() throws {
        let sections = try XCTUnwrap(ChatMemorySummaryParser.sections(from: """
        ```json
        {"sections":[{"title":"Preferences","body":"User prefers SwiftUI-native solutions."}]}
        ```
        """))

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Preferences")
        XCTAssertEqual(sections[0].body, "User prefers SwiftUI-native solutions.")
    }

    func testParsesJSONSurroundedByProse() throws {
        let sections = try XCTUnwrap(ChatMemorySummaryParser.sections(from: """
        Here is the summary:
        {"sections":[{"title":"记忆管理","body":"用户希望先预览再应用记忆更新。"}]}
        Done.
        """))

        XCTAssertEqual(sections, [
            ChatMemorySummarySection(title: "记忆管理", body: "用户希望先预览再应用记忆更新。")
        ])
    }

    func testParsesEmptySections() throws {
        let sections = try XCTUnwrap(ChatMemorySummaryParser.sections(from: #"{"sections":[]}"#))
        XCTAssertTrue(sections.isEmpty)
    }

    func testIgnoresIncompleteSections() throws {
        let sections = try XCTUnwrap(ChatMemorySummaryParser.sections(from: """
        {"sections":[{"title":"Ignored","body":"   "},{"title":"Kept","content":"Uses content fallback."},{"body":"Missing title"}]}
        """))

        XCTAssertEqual(sections, [
            ChatMemorySummarySection(title: "Kept", body: "Uses content fallback.")
        ])
    }

    func testReturnsNilForUnparseableContent() {
        XCTAssertNil(ChatMemorySummaryParser.sections(from: ""))
        XCTAssertNil(ChatMemorySummaryParser.sections(from: "No JSON here."))
        XCTAssertNil(ChatMemorySummaryParser.sections(from: "{not json}"))
    }
}
