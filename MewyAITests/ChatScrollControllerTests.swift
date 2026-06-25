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

    func testEndingManualInteractionAtBottomRestoresAutoScroll() async throws {
        let controller = ChatScrollController()
        var requestedAnimations: [Bool] = []
        controller.setScrollAction { animated in
            requestedAnimations.append(animated)
        }

        controller.beginUserScrollInteraction()
        controller.endUserScrollInteraction()

        try await Task.sleep(for: .milliseconds(120))
        controller.requestImmediateAutoScroll(animated: false)

        XCTAssertEqual(requestedAnimations, [false])
    }

    func testEndingManualInteractionAwayFromBottomKeepsAutoScrollPaused() async throws {
        let controller = ChatScrollController()
        var requestedAnimations: [Bool] = []
        controller.setScrollAction { animated in
            requestedAnimations.append(animated)
        }

        controller.beginUserScrollInteraction()
        controller.scheduleBottomDistanceUpdate(ChatScrollMetrics.bottomThreshold + 40)
        try await Task.sleep(for: .milliseconds(20))
        controller.endUserScrollInteraction()

        try await Task.sleep(for: .milliseconds(120))
        controller.requestImmediateAutoScroll(animated: false)

        XCTAssertTrue(requestedAnimations.isEmpty)
    }

    func testReachingBottomDuringManualInteractionRestoresWhenContentGrowsBeforeRelease() async throws {
        let controller = ChatScrollController()
        var requestedAnimations: [Bool] = []
        controller.setScrollAction { animated in
            requestedAnimations.append(animated)
        }

        controller.beginUserScrollInteraction()
        controller.scheduleBottomDistanceUpdate(ChatScrollMetrics.bottomThreshold + 80)
        try await Task.sleep(for: .milliseconds(20))
        controller.scheduleBottomDistanceUpdate(0)
        try await Task.sleep(for: .milliseconds(20))
        controller.scheduleBottomDistanceUpdate(ChatScrollMetrics.bottomThreshold + 40)
        controller.endUserScrollInteraction()

        try await Task.sleep(for: .milliseconds(120))
        controller.requestImmediateAutoScroll(animated: false)

        XCTAssertEqual(requestedAnimations, [false])
    }

    func testReachingBottomDuringManualInteractionDoesNotRestoreAfterMovingFarAway() async throws {
        let controller = ChatScrollController()
        var requestedAnimations: [Bool] = []
        controller.setScrollAction { animated in
            requestedAnimations.append(animated)
        }

        controller.beginUserScrollInteraction()
        controller.scheduleBottomDistanceUpdate(ChatScrollMetrics.bottomThreshold + 80)
        try await Task.sleep(for: .milliseconds(20))
        controller.scheduleBottomDistanceUpdate(0)
        try await Task.sleep(for: .milliseconds(20))
        controller.scheduleBottomDistanceUpdate(ChatScrollMetrics.bottomResumeCarryDistance + 40)
        controller.endUserScrollInteraction()

        try await Task.sleep(for: .milliseconds(120))
        controller.requestImmediateAutoScroll(animated: false)

        XCTAssertTrue(requestedAnimations.isEmpty)
    }
}
