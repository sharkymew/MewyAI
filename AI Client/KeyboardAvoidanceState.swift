import CoreGraphics
import Foundation
import UIKit

struct KeyboardAvoidanceState: Equatable {
    var bottomPadding: CGFloat = 0

    static func bottomPadding(
        keyboardEndFrame: CGRect,
        screenBounds: CGRect,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat {
        let overlap = max(screenBounds.maxY - keyboardEndFrame.minY, 0)
        return max(overlap - bottomSafeAreaInset, 0)
    }

    static func bottomPadding(
        from notification: Notification,
        screenBounds: CGRect = UIScreen.main.bounds,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat? {
        guard let endFrame = keyboardEndFrame(from: notification) else {
            return nil
        }

        return bottomPadding(
            keyboardEndFrame: endFrame,
            screenBounds: screenBounds,
            bottomSafeAreaInset: bottomSafeAreaInset
        )
    }

    static func animationDuration(from notification: Notification) -> TimeInterval {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
    }

    private static func keyboardEndFrame(from notification: Notification) -> CGRect? {
        let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]

        if let rect = value as? CGRect {
            return rect
        }

        return (value as? NSValue)?.cgRectValue
    }

    mutating func updateBottomPadding(_ padding: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        guard abs(bottomPadding - padding) > tolerance else { return false }
        bottomPadding = padding
        return true
    }
}
