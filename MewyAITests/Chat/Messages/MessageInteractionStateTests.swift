import XCTest
@testable import MewyAI

@MainActor
final class MessageInteractionStateTests: XCTestCase {
    func testDefaultsAreInactive() {
        let state = MessageInteractionState()

        XCTAssertNil(state.activeActionID)
        XCTAssertFalse(state.didTapBubble)
        XCTAssertNil(state.editingMessageID)
        XCTAssertFalse(state.isEditing)
    }

    func testEditingReflectsEditingMessageID() {
        let id = UUID()
        var state = MessageInteractionState()

        state.editingMessageID = id

        XCTAssertEqual(state.editingMessageID, id)
        XCTAssertTrue(state.isEditing)
    }

    func testActionAndTapStateAreIndependent() {
        let id = UUID()
        var state = MessageInteractionState()

        state.activeActionID = id
        state.didTapBubble = true

        XCTAssertEqual(state.activeActionID, id)
        XCTAssertTrue(state.didTapBubble)
        XCTAssertFalse(state.isEditing)
    }
}
