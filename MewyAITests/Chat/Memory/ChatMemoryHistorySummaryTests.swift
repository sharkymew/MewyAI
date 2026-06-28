import XCTest
@testable import MewyAI

@MainActor
final class ChatMemoryHistorySummaryTests: XCTestCase {
    func testBuilderLoadsIndexOnlyConversationsSortsAndSkipsEmptyHistory() {
        let newerID = UUID()
        let newerIndexOnly = AIConversation(
            id: newerID,
            title: "Newer",
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 200),
            indexedMessageCount: 2
        )
        let newerFull = AIConversation(
            id: newerID,
            title: "Newer",
            messages: [
                ChatMessage(role: "user", content: "new prompt"),
                ChatMessage(role: "assistant", content: "new answer")
            ],
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let older = AIConversation(
            title: "Older",
            messages: [ChatMessage(role: "user", content: "old prompt")],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let empty = AIConversation(
            title: "Empty",
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let batches = ChatMemoryHistoryBatchBuilder.makeBatches(
            conversations: [empty, older, newerIndexOnly],
            loadConversation: { id in id == newerID ? newerFull : nil },
            batchCharacterLimit: 2_000
        )

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].conversationCount, 2)
        XCTAssertTrue(batches[0].text.contains("new prompt"))
        XCTAssertTrue(batches[0].text.contains("old prompt"))
        XCTAssertFalse(batches[0].text.contains("Empty"))

        let newerRange = batches[0].text.range(of: "Newer")
        let olderRange = batches[0].text.range(of: "Older")
        XCTAssertNotNil(newerRange)
        XCTAssertNotNil(olderRange)
        if let newerRange, let olderRange {
            XCTAssertTrue(newerRange.lowerBound < olderRange.lowerBound)
        }
    }

    func testBuilderSplitsLongConversationWithoutDroppingLaterMessages() {
        let messages = (0..<12).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "message \(index) " + String(repeating: "body ", count: 18)
            )
        }
        let conversation = AIConversation(
            title: "Long",
            messages: messages,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let batches = ChatMemoryHistoryBatchBuilder.makeBatches(
            conversations: [conversation],
            batchCharacterLimit: 420
        )
        let combinedText = batches.map(\.text).joined(separator: "\n")

        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertTrue(combinedText.contains("message 0"))
        XCTAssertTrue(combinedText.contains("message 11"))
    }

    func testBuilderRendersImageDescriptionsAndFileText() {
        var message = ChatMessage(role: "user", content: "see attached")
        message.imageAttachments = [
            ChatImageAttachment(fileName: "roadmap.jpg", md5: "abc", byteCount: 12)
        ]
        message.imageContextDescription = "whiteboard roadmap for the Atlas project"
        message.fileAttachments = [
            ChatFileAttachment(
                name: "notes.txt",
                typeIdentifier: nil,
                byteCount: 10,
                characterCount: 10,
                extractedText: "Zephyr handshake decisions",
                isTruncated: false
            )
        ]
        let conversation = AIConversation(
            title: "Attachments",
            messages: [message]
        )

        let batches = ChatMemoryHistoryBatchBuilder.makeBatches(conversations: [conversation])
        let text = batches.map(\.text).joined(separator: "\n")

        XCTAssertTrue(text.contains("[image attached: whiteboard roadmap for the Atlas project]"))
        XCTAssertTrue(text.contains("[file attached: notes.txt]"))
        XCTAssertTrue(text.contains("Zephyr handshake decisions"))
    }

    func testParsesBatchSummaryFromPlainOrWrappedJSON() throws {
        let plain = try XCTUnwrap(ChatMemoryHistorySummaryParser.batchSummary(from: """
        {"summary":"User often works on iOS UI.","facts":["User prefers SwiftUI-native fixes.","   "]}
        """))

        XCTAssertEqual(plain.summary, "User often works on iOS UI.")
        XCTAssertEqual(plain.facts, ["User prefers SwiftUI-native fixes."])

        let wrapped = try XCTUnwrap(ChatMemoryHistorySummaryParser.batchSummary(from: """
        Here is the result:
        {"batch_summary":"History mentions local memory.","memory_facts":["User wants history-derived memory summaries."]}
        Done.
        """))

        XCTAssertEqual(wrapped.summary, "History mentions local memory.")
        XCTAssertEqual(wrapped.facts, ["User wants history-derived memory summaries."])
    }

    func testParsesFinalSummaryResultAndRejectsUnrelatedJSON() throws {
        let result = try XCTUnwrap(ChatMemoryHistorySummaryParser.result(from: """
        ```json
        {"sections":[{"title":"Memory","body":"User wants summaries from all history."}],"operations":[{"action":"add","content":"User wants memory summaries generated from all local chat history."},{"action":"update","index":"2","content":"Updated memory"}]}
        ```
        """))

        XCTAssertEqual(result.sections, [
            ChatMemorySummarySection(title: "Memory", body: "User wants summaries from all history.")
        ])
        XCTAssertEqual(result.operations, [
            ChatMemoryOperation(action: .add, index: nil, content: "User wants memory summaries generated from all local chat history."),
            ChatMemoryOperation(action: .update, index: 2, content: "Updated memory")
        ])
        XCTAssertNil(ChatMemoryHistorySummaryParser.result(from: #"{"summary":"batch only"}"#))
        XCTAssertNil(ChatMemoryHistorySummaryParser.batchSummary(from: "not json"))
    }
}
