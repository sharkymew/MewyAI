import CoreGraphics
import UIKit
import XCTest
@testable import MewyAI

final class KeyboardAvoidanceStateTests: XCTestCase {
    func testBottomPaddingSubtractsExistingBottomSafeArea() {
        let padding = KeyboardAvoidanceState.bottomPadding(
            keyboardEndFrame: CGRect(x: 0, y: 500, width: 390, height: 344),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 310)
    }

    func testBottomPaddingIsZeroWhenKeyboardIsOffscreen() {
        let padding = KeyboardAvoidanceState.bottomPadding(
            keyboardEndFrame: CGRect(x: 0, y: 844, width: 390, height: 0),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 0)
    }

    func testBottomPaddingClampsWhenSafeAreaIsLargerThanOverlap() {
        let padding = KeyboardAvoidanceState.bottomPadding(
            keyboardEndFrame: CGRect(x: 0, y: 820, width: 390, height: 24),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 0)
    }

    func testBottomPaddingParsesUIKitKeyboardFrameNotification() {
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                    cgRect: CGRect(x: 0, y: 500, width: 390, height: 344)
                )
            ]
        )

        let padding = KeyboardAvoidanceState.bottomPadding(
            from: notification,
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            bottomSafeAreaInset: 34
        )

        XCTAssertEqual(padding, 310)
    }

    func testBottomPaddingReturnsNilWhenNotificationHasNoFrame() {
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [:]
        )

        XCTAssertNil(KeyboardAvoidanceState.bottomPadding(
            from: notification,
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            bottomSafeAreaInset: 34
        ))
    }

    func testUpdateIgnoresTinyChanges() {
        var state = KeyboardAvoidanceState(bottomPadding: 310)

        XCTAssertFalse(state.updateBottomPadding(310.25))
        XCTAssertEqual(state.bottomPadding, 310)
    }
}
