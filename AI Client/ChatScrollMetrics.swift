import Foundation
import SwiftUI
import UIKit

enum ChatScrollMetrics {
    static let coordinateSpaceName = "ChatScrollCoordinateSpace"
    static let bottomThreshold: CGFloat = 12
    static let dragIntentMinimumDistance: CGFloat = 3
    static let scrollToBottomButtonHitOutset: CGFloat = 8
    static let scrollToBottomButtonHitSize: CGFloat = 52

    static func roundedDistance(_ distance: CGFloat) -> CGFloat {
        let scale = max(UIScreen.main.scale, 1)
        return (max(distance, 0) * scale).rounded() / scale
    }
}
