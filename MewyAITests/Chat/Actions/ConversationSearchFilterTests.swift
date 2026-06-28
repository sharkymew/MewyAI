import XCTest
@testable import MewyAI

@MainActor
final class ConversationSearchFilterTests: XCTestCase {
    private func conversation(
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        revisionGroups: [ChatMessageRevisionGroup] = []
    ) -> AIConversation {
        AIConversation(
            title: title,
            messages: messages,
            messageRevisionGroups: revisionGroups
        )
    }

    func testEmptyQueryMatchesEverything() {
        let conversations = [conversation(title: "Swift"), conversation(title: "随便聊聊")]

        XCTAssertEqual(ConversationSearchFilter.filtered(conversations, query: ""), conversations)
        XCTAssertEqual(ConversationSearchFilter.filtered(conversations, query: "   "), conversations)
    }

    func testMatchesTitleCaseInsensitively() {
        let target = conversation(title: "SwiftUI Layout 问题")
        let other = conversation(title: "晚饭吃什么")

        let filtered = ConversationSearchFilter.filtered([target, other], query: "swiftui")

        XCTAssertEqual(filtered, [target])
    }

    func testMatchesCurrentMessageContent() {
        let target = conversation(messages: [
            ChatMessage(role: "user", content: "帮我写一个快速排序"),
            ChatMessage(role: "assistant", content: "好的，下面是 quicksort 的实现。")
        ])
        let other = conversation(messages: [
            ChatMessage(role: "user", content: "今天天气如何")
        ])

        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "快速排序"), [target])
        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "QUICKSORT"), [target])
    }

    func testMatchesRevisionHistoryMessages() {
        let userID = UUID()
        let revision = ChatMessageRevision(messages: [
            ChatMessage(id: userID, role: "user", content: "被修改前提到了量子纠缠")
        ])
        let target = conversation(
            messages: [ChatMessage(id: userID, role: "user", content: "改后的内容")],
            revisionGroups: [
                ChatMessageRevisionGroup(
                    id: userID,
                    selectedRevisionID: revision.id,
                    revisions: [revision]
                )
            ]
        )
        let other = conversation(messages: [ChatMessage(role: "user", content: "改后的内容")])

        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "量子纠缠"), [target])
    }

    func testMatchesFileAttachmentNameAndText() {
        let attachment = ChatFileAttachment(
            name: "季度报告.txt",
            typeIdentifier: "public.plain-text",
            byteCount: 128,
            characterCount: 64,
            extractedText: "第三季度营收增长百分之十二",
            isTruncated: false
        )
        let target = conversation(messages: [
            ChatMessage(role: "user", content: "总结这个文件", fileAttachments: [attachment])
        ])
        let other = conversation(messages: [ChatMessage(role: "user", content: "总结这个文件")])

        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "营收增长"), [target])
        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "季度报告"), [target])
    }

    func testMatchesImageContextDescription() {
        let target = conversation(messages: [
            ChatMessage(
                role: "user",
                content: "这是什么",
                imageContextDescription: "A photo of the Golden Gate Bridge at sunset"
            )
        ])
        let other = conversation(messages: [ChatMessage(role: "user", content: "这是什么")])

        XCTAssertEqual(ConversationSearchFilter.filtered([target, other], query: "golden gate"), [target])
    }

    func testAllTermsMustMatchAcrossFields() {
        let target = conversation(
            title: "Swift 学习",
            messages: [ChatMessage(role: "assistant", content: "闭包是可以捕获上下文的函数。")]
        )

        XCTAssertTrue(ConversationSearchFilter.matches(target, query: "swift 闭包"))
        XCTAssertFalse(ConversationSearchFilter.matches(target, query: "swift 协议"))
    }
}
