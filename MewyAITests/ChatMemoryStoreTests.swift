import Foundation
import XCTest
@testable import MewyAI

@MainActor
final class ChatMemoryStoreTests: XCTestCase {
    private func makeEntry(
        _ content: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ChatMemoryEntry {
        ChatMemoryEntry(
            content: content,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    func testApplyingAddAppendsEntryAndSkipsDuplicates() {
        let existing = [makeEntry("用户在开发 iOS 应用")]
        let conversationID = UUID()

        let updated = ChatMemoryStore.applying(
            [
                ChatMemoryOperation(action: .add, index: nil, content: "用户偏好 SwiftUI"),
                ChatMemoryOperation(action: .add, index: nil, content: "用户在开发 iOS 应用"),
                ChatMemoryOperation(action: .add, index: nil, content: "   ")
            ],
            to: existing,
            snapshotIDs: existing.map(\.id),
            sourceConversationID: conversationID
        )

        XCTAssertEqual(updated.map(\.content), ["用户在开发 iOS 应用", "用户偏好 SwiftUI"])
        XCTAssertEqual(updated[1].sourceConversationID, conversationID)
    }

    func testApplyingUpdateAndDeleteResolveSnapshotIndexesByID() {
        let first = makeEntry("first")
        let second = makeEntry("second")
        let third = makeEntry("third")
        let snapshotIDs = [first.id, second.id, third.id]

        // The stored list changed since the snapshot: an entry was inserted
        // at the front, so positions no longer match the prompt numbering.
        let currentEntries = [makeEntry("inserted"), first, second, third]

        let updated = ChatMemoryStore.applying(
            [
                ChatMemoryOperation(action: .update, index: 2, content: "second (updated)"),
                ChatMemoryOperation(action: .delete, index: 3, content: nil)
            ],
            to: currentEntries,
            snapshotIDs: snapshotIDs,
            sourceConversationID: nil
        )

        XCTAssertEqual(updated.map(\.content), ["inserted", "first", "second (updated)"])
        XCTAssertEqual(updated[2].id, second.id)
    }

    func testApplyingIgnoresOutOfRangeOrMissingIndexes() {
        let existing = [makeEntry("only")]

        let updated = ChatMemoryStore.applying(
            [
                ChatMemoryOperation(action: .update, index: 5, content: "changed"),
                ChatMemoryOperation(action: .update, index: nil, content: "changed"),
                ChatMemoryOperation(action: .delete, index: 0, content: nil),
                ChatMemoryOperation(action: .delete, index: nil, content: nil)
            ],
            to: existing,
            snapshotIDs: existing.map(\.id),
            sourceConversationID: nil
        )

        XCTAssertEqual(updated, existing)
    }

    func testApplyingTruncatesOverlongContent() {
        let longContent = String(repeating: "记", count: ChatMemoryStore.maxEntryCharacters + 50)

        let updated = ChatMemoryStore.applying(
            [ChatMemoryOperation(action: .add, index: nil, content: longContent)],
            to: [],
            snapshotIDs: [],
            sourceConversationID: nil
        )

        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].content.count, ChatMemoryStore.maxEntryCharacters + 1)
        XCTAssertTrue(updated[0].content.hasSuffix("…"))
    }

    func testApplyingEnforcesEntryCapByDroppingOldest() {
        let oldDate = Date(timeIntervalSince1970: 0)
        let entries = (0..<ChatMemoryStore.maxEntryCount).map { index in
            makeEntry("memory \(index)", updatedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)))
        }
        let oldest = makeEntry("oldest", updatedAt: oldDate)
        let fullEntries = [oldest] + entries

        let updated = ChatMemoryStore.applying(
            [ChatMemoryOperation(action: .add, index: nil, content: "newest")],
            to: fullEntries,
            snapshotIDs: fullEntries.map(\.id),
            sourceConversationID: nil
        )

        XCTAssertEqual(updated.count, ChatMemoryStore.maxEntryCount)
        XCTAssertFalse(updated.contains { $0.id == oldest.id })
        XCTAssertFalse(updated.contains { $0.content == "memory 0" })
        XCTAssertTrue(updated.contains { $0.content == "newest" })
    }

    func testPromptAppendixIsEmptyWithoutMemories() {
        XCTAssertEqual(ChatMemoryStore.promptAppendix(for: []), "")
        XCTAssertEqual(ChatMemoryStore.promptAppendix(for: [makeEntry("   ")]), "")
    }

    func testPromptAppendixRendersNumberedDatedLines() {
        let date = Date(timeIntervalSince1970: 1_770_000_000) // 2026-02-02 UTC
        let appendix = ChatMemoryStore.promptAppendix(for: [
            makeEntry("用户在开发 iOS 应用", updatedAt: date),
            makeEntry("User prefers concise answers", updatedAt: date)
        ])

        XCTAssertTrue(appendix.contains("<user_memory>"))
        XCTAssertTrue(appendix.contains("</user_memory>"))
        XCTAssertTrue(appendix.contains("1. [2026-02-0"))
        XCTAssertTrue(appendix.contains("用户在开发 iOS 应用"))
        XCTAssertTrue(appendix.contains("2. [2026-02-0"))
        XCTAssertTrue(appendix.contains("User prefers concise answers"))
        XCTAssertTrue(appendix.hasPrefix("\n\n"))
    }

    func testExtractionUserPromptIncludesMemoriesAndExchange() {
        let prompt = ChatMemoryStore.extractionUserPrompt(
            entries: [makeEntry("用户在开发 iOS 应用")],
            userText: "我刚把项目迁移到了 Swift 6",
            assistantText: "恭喜！Swift 6 的并发检查……"
        )

        XCTAssertTrue(prompt.contains("<existing_memories>"))
        XCTAssertTrue(prompt.contains("1. ["))
        XCTAssertTrue(prompt.contains("用户在开发 iOS 应用"))
        XCTAssertTrue(prompt.contains("<latest_exchange>"))
        XCTAssertTrue(prompt.contains("user: 我刚把项目迁移到了 Swift 6"))
        XCTAssertTrue(prompt.contains("assistant: 恭喜！"))
    }

    func testExtractionUserPromptShowsPlaceholderWithoutMemoriesAndTruncatesExchange() {
        let longUserText = String(repeating: "a", count: ChatMemoryStore.maxExchangeCharacters + 100)
        let prompt = ChatMemoryStore.extractionUserPrompt(
            entries: [],
            userText: longUserText,
            assistantText: "ok"
        )

        XCTAssertTrue(prompt.contains("(no memories yet)"))
        XCTAssertFalse(prompt.contains(longUserText))
        XCTAssertTrue(prompt.contains(String(repeating: "a", count: ChatMemoryStore.maxExchangeCharacters) + "…"))
    }

    func testEntryDecodeAppliesDefaults() throws {
        let data = """
        {"content": "用户在开发 iOS 应用"}
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(ChatMemoryEntry.self, from: data)

        XCTAssertEqual(entry.content, "用户在开发 iOS 应用")
        XCTAssertEqual(entry.createdAt, entry.updatedAt)
        XCTAssertNil(entry.sourceConversationID)
    }
}
