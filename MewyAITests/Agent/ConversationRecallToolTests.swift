import Foundation
import XCTest
@testable import MewyAI

@MainActor
final class ConversationRecallToolTests: XCTestCase {
    private func makeConversation(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000),
        messages: [ChatMessage]
    ) -> AIConversation {
        AIConversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func search(
        _ argumentsJSON: String,
        conversations: [AIConversation],
        excluded: Set<UUID> = []
    ) -> AgentToolCallResult {
        ConversationRecallTool.execute(
            functionName: ConversationRecallTool.searchFunctionName,
            argumentsJSON: argumentsJSON,
            conversations: conversations,
            excludedConversationIDs: excluded
        )
    }

    private func read(
        _ argumentsJSON: String,
        conversations: [AIConversation],
        excluded: Set<UUID> = []
    ) -> AgentToolCallResult {
        ConversationRecallTool.execute(
            functionName: ConversationRecallTool.readFunctionName,
            argumentsJSON: argumentsJSON,
            conversations: conversations,
            excludedConversationIDs: excluded
        )
    }

    func testSearchRanksTermCoverageAboveSingleTermHitsAndExcludesConversations() {
        let bothTerms = makeConversation(
            title: "SwiftUI 布局",
            messages: [
                ChatMessage(role: "user", content: "SwiftUI 里怎么做瀑布流布局？"),
                ChatMessage(role: "assistant", content: "可以用 LazyVGrid……")
            ]
        )
        let oneTermManyHits = makeConversation(
            title: "聊天记录",
            messages: (0..<6).map { index in
                ChatMessage(role: "user", content: "SwiftUI 问题 \(index)")
            }
        )
        let excludedMatch = makeConversation(
            title: "SwiftUI 布局（当前对话）",
            messages: [ChatMessage(role: "user", content: "SwiftUI 布局")]
        )
        let unrelated = makeConversation(
            title: "晚饭吃什么",
            messages: [ChatMessage(role: "user", content: "推荐个菜谱")]
        )

        let result = search(
            #"{"query": "SwiftUI 布局"}"#,
            conversations: [unrelated, oneTermManyHits, bothTerms, excludedMatch],
            excluded: [excludedMatch.id]
        )

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("[1] conversation_id: \(bothTerms.id.uuidString)"))
        XCTAssertTrue(result.content.contains("[2] conversation_id: \(oneTermManyHits.id.uuidString)"))
        XCTAssertFalse(result.content.contains(excludedMatch.id.uuidString))
        XCTAssertFalse(result.content.contains(unrelated.id.uuidString))
        XCTAssertTrue(result.content.contains("matched excerpts:"))
        XCTAssertTrue(result.content.contains("user:"))
    }

    func testSearchWithEmptyQueryListsRecentConversations() {
        let older = makeConversation(
            title: "旧对话",
            updatedAt: Date(timeIntervalSince1970: 100),
            messages: [ChatMessage(role: "user", content: "hello")]
        )
        let newer = makeConversation(
            title: "新对话",
            updatedAt: Date(timeIntervalSince1970: 200),
            messages: [ChatMessage(role: "user", content: "hi"), ChatMessage(role: "assistant", content: "hey")]
        )

        let result = search("{}", conversations: [older, newer])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("Most recent conversations"))
        let newerRange = result.content.range(of: newer.id.uuidString)
        let olderRange = result.content.range(of: older.id.uuidString)
        XCTAssertNotNil(newerRange)
        XCTAssertNotNil(olderRange)
        if let newerRange, let olderRange {
            XCTAssertTrue(newerRange.lowerBound < olderRange.lowerBound)
        }
        XCTAssertTrue(result.content.contains("2 messages"))
    }

    func testSearchWithoutMatchesReturnsGuidance() {
        let conversation = makeConversation(
            title: "晚饭",
            messages: [ChatMessage(role: "user", content: "推荐个菜谱")]
        )

        let result = search(#"{"query": "quantum chromodynamics"}"#, conversations: [conversation])

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("No past conversations matched"))
    }

    func testSearchMatchesHiddenImageDescriptionAndFileText() {
        var imageMessage = ChatMessage(role: "user", content: "")
        imageMessage.imageContextDescription = "A whiteboard photo about the Atlas project roadmap"
        let fileMessage = ChatMessage(
            role: "user",
            content: "看下这个文档",
            fileAttachments: [ChatFileAttachment(
                name: "spec.txt",
                typeIdentifier: nil,
                byteCount: 10,
                characterCount: 10,
                extractedText: "Zephyr protocol handshake details",
                isTruncated: false
            )]
        )
        let conversations = [
            makeConversation(title: "图", messages: [imageMessage]),
            makeConversation(title: "文档", messages: [fileMessage])
        ]

        let imageResult = search(#"{"query": "Atlas roadmap"}"#, conversations: conversations)
        XCTAssertTrue(imageResult.content.contains("image (hidden description):"))

        let fileResult = search(#"{"query": "Zephyr handshake"}"#, conversations: conversations)
        XCTAssertTrue(fileResult.content.contains("file spec.txt:"))
    }

    func testSearchClampsMaxResults() {
        let conversations = (0..<20).map { index in
            makeConversation(
                title: "对话 \(index)",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                messages: [ChatMessage(role: "user", content: "topic alpha")]
            )
        }

        let result = search(#"{"query": "alpha", "max_results": 99}"#, conversations: conversations)

        XCTAssertTrue(result.content.contains("[\(ConversationRecallTool.maxSearchResultCount)]"))
        XCTAssertFalse(result.content.contains("[\(ConversationRecallTool.maxSearchResultCount + 1)]"))
    }

    func testReadPaginatesLongTranscriptAndAcceptsStringPage() {
        let longText = String(repeating: "字", count: ConversationRecallTool.readPageCharacters)
        let conversation = makeConversation(
            title: "长对话",
            messages: [
                ChatMessage(role: "user", content: longText),
                ChatMessage(role: "assistant", content: longText),
                ChatMessage(role: "user", content: "结尾消息")
            ]
        )

        XCTAssertEqual(ConversationRecallTool.transcriptPages(for: conversation).count, 3)

        let firstPage = read(
            #"{"conversation_id": "\#(conversation.id.uuidString)"}"#,
            conversations: [conversation]
        )
        XCTAssertFalse(firstPage.isError)
        XCTAssertTrue(firstPage.content.contains("page 1 of"))
        XCTAssertTrue(firstPage.content.contains("\"page\": 2"))
        XCTAssertFalse(firstPage.content.contains("结尾消息"))

        let lastPage = read(
            #"{"conversation_id": "\#(conversation.id.uuidString)", "page": "3"}"#,
            conversations: [conversation]
        )
        XCTAssertFalse(lastPage.isError)
        XCTAssertTrue(lastPage.content.contains("结尾消息"))
        XCTAssertFalse(lastPage.content.contains("for more"))
    }

    func testReadReportsAttachmentsAndOutOfRangePage() {
        var message = ChatMessage(role: "user", content: "看图")
        message.imageAttachments = [ChatImageAttachment(fileName: "a.jpg", md5: "x", byteCount: 1)]
        message.imageContextDescription = "A cat on a keyboard"
        let conversation = makeConversation(title: "图片", messages: [message])

        let result = read(
            #"{"conversation_id": "\#(conversation.id.uuidString)"}"#,
            conversations: [conversation]
        )
        XCTAssertTrue(result.content.contains("[image attached: A cat on a keyboard]"))

        let outOfRange = read(
            #"{"conversation_id": "\#(conversation.id.uuidString)", "page": 9}"#,
            conversations: [conversation]
        )
        XCTAssertTrue(outOfRange.isError)
        XCTAssertTrue(outOfRange.content.contains("out of range"))
    }

    func testReadResolvesUniqueUUIDPrefixAndRejectsUnknownID() {
        let conversation = makeConversation(
            title: "前缀",
            messages: [ChatMessage(role: "user", content: "hello")]
        )
        let prefix = String(conversation.id.uuidString.prefix(8)).lowercased()

        let prefixResult = read(
            #"{"conversation_id": "\#(prefix)"}"#,
            conversations: [conversation]
        )
        XCTAssertFalse(prefixResult.isError)
        XCTAssertTrue(prefixResult.content.contains("hello"))

        let unknownResult = read(
            #"{"conversation_id": "\#(UUID().uuidString)"}"#,
            conversations: [conversation]
        )
        XCTAssertTrue(unknownResult.isError)

        let excludedResult = read(
            #"{"conversation_id": "\#(conversation.id.uuidString)"}"#,
            conversations: [conversation],
            excluded: [conversation.id]
        )
        XCTAssertTrue(excludedResult.isError)
    }

    func testExecuteRejectsUnknownFunctionAndMissingConversationID() {
        let unknown = ConversationRecallTool.execute(
            functionName: "chat_history_delete",
            argumentsJSON: "{}",
            conversations: [],
            excludedConversationIDs: []
        )
        XCTAssertTrue(unknown.isError)

        let missingID = read("{}", conversations: [])
        XCTAssertTrue(missingID.isError)
        XCTAssertTrue(missingID.content.contains("Missing conversation_id"))
    }

    func testDefinitionsSkipUsedFunctionNamesAndNeverRequireApproval() {
        let allDefinitions = ConversationRecallTool.definitions()
        XCTAssertEqual(allDefinitions.count, 2)
        XCTAssertTrue(allDefinitions.allSatisfy { !$0.requiresApproval })
        XCTAssertTrue(allDefinitions.allSatisfy { ConversationRecallTool.isRecallTool($0) })

        let filtered = ConversationRecallTool.definitions(
            excludingFunctionNames: [ConversationRecallTool.searchFunctionName]
        )
        XCTAssertEqual(filtered.map(\.functionName), [ConversationRecallTool.readFunctionName])
    }

    func testPromptAppendixListsRecentConversationsAndExcludesCurrentAndPrivate() {
        let current = makeConversation(
            title: "当前对话",
            updatedAt: Date(timeIntervalSince1970: 300),
            messages: [ChatMessage(role: "user", content: "now")]
        )
        let recent = makeConversation(
            title: "SwiftUI 布局",
            updatedAt: Date(timeIntervalSince1970: 200),
            messages: [ChatMessage(role: "user", content: "hi")]
        )
        let empty = makeConversation(
            title: "空对话",
            updatedAt: Date(timeIntervalSince1970: 150),
            messages: []
        )

        let appendix = ConversationRecallTool.promptAppendix(
            conversations: [current, recent, empty],
            excludedConversationIDs: [current.id]
        )

        XCTAssertTrue(appendix.contains("<chat_history_recall>"))
        XCTAssertTrue(appendix.contains("Be proactive."))
        XCTAssertTrue(appendix.contains("[\(recent.id.uuidString.prefix(8))]"))
        XCTAssertTrue(appendix.contains("SwiftUI 布局"))
        XCTAssertFalse(appendix.contains("当前对话"))
        XCTAssertFalse(appendix.contains("空对话"))
    }

    func testPromptAppendixCapsIndexSize() {
        let conversations = (0..<30).map { index in
            makeConversation(
                title: "标题\(index)",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                messages: [ChatMessage(role: "user", content: "m")]
            )
        }

        let appendix = ConversationRecallTool.promptAppendix(
            conversations: conversations,
            excludedConversationIDs: []
        )

        XCTAssertTrue(appendix.contains("标题29"))
        XCTAssertTrue(appendix.contains("标题\(30 - ConversationRecallTool.recentConversationIndexLimit)"))
        XCTAssertFalse(appendix.contains("标题\(29 - ConversationRecallTool.recentConversationIndexLimit)\n"))
        XCTAssertFalse(appendix.contains("标题0\n"))
    }
}
