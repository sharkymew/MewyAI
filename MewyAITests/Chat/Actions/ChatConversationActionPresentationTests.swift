import XCTest
@testable import MewyAI

@MainActor
final class ChatConversationActionPresentationTests: XCTestCase {
    func testBlankRegularConversationStartsPrivateConversation() {
        let presentation = ChatConversationActionPresentation(
            isCurrentConversationBlank: true,
            isPrivateConversationSelected: false
        )

        XCTAssertTrue(presentation.canCreateConversation)
        XCTAssertFalse(presentation.showsTemporaryChatNotice)
        XCTAssertTrue(presentation.showsPrivateConversationAction)
        XCTAssertEqual(presentation.systemImage, "lock")
        XCTAssertFalse(presentation.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(presentation.accessibilityHint.isEmpty)
    }

    func testBlankPrivateConversationShowsTemporaryExitAction() {
        let presentation = ChatConversationActionPresentation(
            isCurrentConversationBlank: true,
            isPrivateConversationSelected: true
        )

        XCTAssertTrue(presentation.showsTemporaryChatNotice)
        XCTAssertFalse(presentation.showsPrivateConversationAction)
        XCTAssertEqual(presentation.systemImage, "square.and.pencil")
        XCTAssertFalse(presentation.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(presentation.accessibilityHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testNonBlankConversationCreatesNewConversation() {
        let presentation = ChatConversationActionPresentation(
            isCurrentConversationBlank: false,
            isPrivateConversationSelected: false
        )

        XCTAssertFalse(presentation.showsTemporaryChatNotice)
        XCTAssertFalse(presentation.showsPrivateConversationAction)
        XCTAssertEqual(presentation.systemImage, "square.and.pencil")
        XCTAssertFalse(presentation.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(presentation.accessibilityHint.isEmpty)
    }
}
