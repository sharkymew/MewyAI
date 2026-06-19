import XCTest
import UIKit
@testable import MewyAI

@MainActor
final class MarkdownRenderCacheControllerTests: XCTestCase {
    func testPrepareCacheStoresRenderedEntry() async {
        let controller = MarkdownRenderCacheController()
        let messageID = UUID()
        let prepared = expectation(description: "Markdown cache prepared")

        controller.prepareCache(
            for: messageID,
            content: "Hello **Markdown**",
            style: Self.testStyle,
            onPrepared: {
                prepared.fulfill()
            }
        )

        await fulfillment(of: [prepared], timeout: 2)

        XCTAssertNotNil(controller[messageID])
        XCTAssertEqual(controller.cachedMessageIDs, [messageID])
        XCTAssertTrue(controller.pendingMessageIDs.isEmpty)
    }

    func testErrorDetailContentInvalidatesExistingEntry() async {
        let controller = MarkdownRenderCacheController()
        let messageID = UUID()
        let prepared = expectation(description: "Markdown cache prepared")

        controller.prepareCache(
            for: messageID,
            content: "Regular assistant message",
            style: Self.testStyle,
            onPrepared: {
                prepared.fulfill()
            }
        )
        await fulfillment(of: [prepared], timeout: 2)
        XCTAssertNotNil(controller[messageID])

        controller.prepareCache(
            for: messageID,
            content: "Request failed\n\nHTTP status code 500",
            style: Self.testStyle
        )

        XCTAssertNil(controller[messageID])
        XCTAssertFalse(controller.pendingMessageIDs.contains(messageID))
    }

    func testPrepareCacheForMissingAssistantMessageInvalidatesExistingEntry() async {
        let controller = MarkdownRenderCacheController()
        let messageID = UUID()
        let prepared = expectation(description: "Markdown cache prepared")

        controller.prepareCache(
            for: messageID,
            content: "Regular assistant message",
            style: Self.testStyle,
            onPrepared: {
                prepared.fulfill()
            }
        )
        await fulfillment(of: [prepared], timeout: 2)

        controller.prepareCache(
            for: messageID,
            in: [ChatMessage(id: messageID, role: "user", content: "not assistant")],
            style: Self.testStyle
        )

        XCTAssertNil(controller[messageID])
    }

    func testResetClearsOldEntriesAndPreparesAssistantMessages() async {
        let controller = MarkdownRenderCacheController()
        let oldID = UUID()
        let assistant = ChatMessage(role: "assistant", content: "Cached response")
        let user = ChatMessage(role: "user", content: "User prompt")
        let oldPrepared = expectation(description: "Old cache prepared")

        controller.prepareCache(
            for: oldID,
            content: "Old response",
            style: Self.testStyle,
            onPrepared: {
                oldPrepared.fulfill()
            }
        )
        await fulfillment(of: [oldPrepared], timeout: 2)

        controller.reset(for: [user, assistant], style: Self.testStyle)

        XCTAssertNil(controller[oldID])
        XCTAssertFalse(controller.pendingMessageIDs.contains(user.id))
        XCTAssertTrue(controller.pendingMessageIDs.contains(assistant.id) || controller.cachedMessageIDs.contains(assistant.id))
    }

    func testPruneRemovesEntriesOutsideValidMessageIDs() async {
        let controller = MarkdownRenderCacheController()
        let keptID = UUID()
        let removedID = UUID()
        let keptPrepared = expectation(description: "Kept cache prepared")
        let removedPrepared = expectation(description: "Removed cache prepared")

        controller.prepareCache(
            for: keptID,
            content: "Keep",
            style: Self.testStyle,
            onPrepared: {
                keptPrepared.fulfill()
            }
        )
        controller.prepareCache(
            for: removedID,
            content: "Remove",
            style: Self.testStyle,
            onPrepared: {
                removedPrepared.fulfill()
            }
        )
        await fulfillment(of: [keptPrepared, removedPrepared], timeout: 2)

        controller.prune(validMessageIDs: [keptID])

        XCTAssertNotNil(controller[keptID])
        XCTAssertNil(controller[removedID])
    }

    private static let testStyle = MarkdownRenderStyle(
        textColor: .label,
        baseFont: .preferredFont(forTextStyle: .body),
        textAlignment: .left,
        userInterfaceStyle: .light,
        displayScale: 2
    )
}
