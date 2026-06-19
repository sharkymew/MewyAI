import XCTest
@testable import MewyAI

@MainActor
final class ConversationRenameDraftTests: XCTestCase {
    func testBeginCapturesConversationIDAndTitle() {
        let id = UUID()
        let conversation = AIConversation(id: id, title: "Planning")
        var draft = ConversationRenameDraft()

        draft.begin(conversation: conversation)

        XCTAssertEqual(draft.conversationID, id)
        XCTAssertEqual(draft.title, "Planning")
        XCTAssertTrue(draft.isPresented)
    }

    func testResetClearsDraftState() {
        var draft = ConversationRenameDraft()
        draft.begin(conversation: AIConversation(title: "Planning"))

        draft.reset()

        XCTAssertNil(draft.conversationID)
        XCTAssertEqual(draft.title, "")
        XCTAssertFalse(draft.isPresented)
    }

    func testNormalizedTitleTrimsWhitespace() {
        XCTAssertEqual(
            ConversationRenameDraft.normalizedTitle("  Research Plan  "),
            "Research Plan"
        )
    }

    func testNormalizedTitleFallsBackForBlankTitle() {
        XCTAssertEqual(
            ConversationRenameDraft.normalizedTitle(" \n\t "),
            AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
        )
    }
}
