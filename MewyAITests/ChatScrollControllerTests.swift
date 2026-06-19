import XCTest
@testable import MewyAI

@MainActor
final class ChatScrollControllerTests: XCTestCase {
    func testRestoreAfterConversationChangeRequestsImmediateScroll() {
        let controller = ChatScrollController()
        var requestedAnimations: [Bool] = []
        controller.setScrollAction { animated in
            requestedAnimations.append(animated)
        }

        controller.restoreAfterConversationChange()

        XCTAssertEqual(requestedAnimations, [false])
    }
}
