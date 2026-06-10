import XCTest
@testable import MewyAI

@MainActor
final class ConversationStoreTests: XCTestCase {
    func testChatMessageDecodeDefaultsAndNormalize() throws {
        let data = """
        {
          "role": "assistant",
          "contentChunks": ["Hello", " world"],
          "reasoningContent": "kept reasoning",
          "reasoningChunks": ["old reasoning"],
          "toolExchanges": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "assistantContent": "",
              "reasoningContent": "",
              "toolCalls": [],
              "toolResults": []
            }
          ]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: data).normalized

        XCTAssertEqual(message.role, "assistant")
        XCTAssertEqual(message.content, "Hello world")
        XCTAssertTrue(message.contentChunks.isEmpty)
        XCTAssertEqual(message.reasoningContent, "kept reasoning")
        XCTAssertTrue(message.reasoningChunks.isEmpty)
        XCTAssertTrue(message.toolExchanges.isEmpty)
    }

    func testConversationNormalizeFiltersInvalidRevisionGroups() {
        let userID = UUID()
        let validRevision = ChatMessageRevision(messages: [
            ChatMessage(id: userID, role: "user", content: "", contentChunks: ["edited"])
        ])
        let invalidRevision = ChatMessageRevision(messages: [
            ChatMessage(role: "assistant", content: "orphan")
        ])
        let conversation = AIConversation(
            messages: [
                ChatMessage(id: userID, role: "user", content: "current")
            ],
            messageRevisionGroups: [
                ChatMessageRevisionGroup(
                    id: userID,
                    selectedRevisionID: invalidRevision.id,
                    revisions: [invalidRevision, validRevision]
                )
            ]
        ).normalized

        XCTAssertEqual(conversation.messageRevisionGroups.count, 1)
        XCTAssertEqual(conversation.messageRevisionGroups[0].revisions, [validRevision.normalized])
        XCTAssertEqual(conversation.messageRevisionGroups[0].selectedRevisionID, validRevision.id)
    }

    func testLegacyImageAttachmentDataURLDecodesMimeType() throws {
        let data = """
        {
          "role": "user",
          "content": "image",
          "imageAttachments": [
            { "dataURL": "data:image/png;base64,AAAA" }
          ]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.imageAttachments[0].mimeType, "image/png")
        XCTAssertEqual(message.imageAttachments[0].byteCount, 0)
    }
}
