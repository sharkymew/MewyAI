import Foundation
import SwiftUI

struct MessageRevisionNavigationState: Equatable {
    let currentIndex: Int
    let count: Int

    var displayText: String {
        "\(currentIndex + 1) / \(count)"
    }

    var canMovePrevious: Bool {
        currentIndex > 0
    }

    var canMoveNext: Bool {
        currentIndex + 1 < count
    }
}
