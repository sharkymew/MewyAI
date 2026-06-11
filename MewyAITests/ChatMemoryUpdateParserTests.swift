import XCTest
@testable import MewyAI

@MainActor
final class ChatMemoryUpdateParserTests: XCTestCase {
    func testParsesPlainJSONOperations() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: """
        {"operations":[{"action":"add","content":"用户在开发 iOS 应用"},{"action":"update","index":2,"content":"用户住在上海"},{"action":"delete","index":3}]}
        """))

        XCTAssertEqual(operations.count, 3)
        XCTAssertEqual(operations[0], ChatMemoryOperation(action: .add, index: nil, content: "用户在开发 iOS 应用"))
        XCTAssertEqual(operations[1], ChatMemoryOperation(action: .update, index: 2, content: "用户住在上海"))
        XCTAssertEqual(operations[2], ChatMemoryOperation(action: .delete, index: 3, content: nil))
    }

    func testParsesJSONWrappedInCodeFence() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: """
        ```json
        {"operations":[{"action":"add","content":"User prefers SwiftUI"}]}
        ```
        """))

        XCTAssertEqual(operations, [ChatMemoryOperation(action: .add, index: nil, content: "User prefers SwiftUI")])
    }

    func testParsesJSONSurroundedByProse() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: """
        Here are the memory updates:
        {"operations":[{"action":"delete","index":1}]}
        Let me know if you need anything else.
        """))

        XCTAssertEqual(operations, [ChatMemoryOperation(action: .delete, index: 1, content: nil)])
    }

    func testParsesEmptyOperations() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: #"{"operations":[]}"#))
        XCTAssertTrue(operations.isEmpty)
    }

    func testParsesStringIndex() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: """
        {"operations":[{"action":"update","index":"4","content":"updated"}]}
        """))

        XCTAssertEqual(operations, [ChatMemoryOperation(action: .update, index: 4, content: "updated")])
    }

    func testIgnoresUnknownActions() throws {
        let operations = try XCTUnwrap(ChatMemoryUpdateParser.operations(from: """
        {"operations":[{"action":"noop","content":"ignored"},{"action":"ADD","content":"kept"}]}
        """))

        XCTAssertEqual(operations, [ChatMemoryOperation(action: .add, index: nil, content: "kept")])
    }

    func testReturnsNilForUnparseableContent() {
        XCTAssertNil(ChatMemoryUpdateParser.operations(from: ""))
        XCTAssertNil(ChatMemoryUpdateParser.operations(from: "I could not produce JSON."))
        XCTAssertNil(ChatMemoryUpdateParser.operations(from: "{not json}"))
    }
}
