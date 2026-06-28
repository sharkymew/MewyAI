import Foundation
import SwiftUI
import Combine
import UIKit

final class ConversationActionHaptics: ObservableObject {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        generator.prepare()
    }

    func impact() {
        generator.impactOccurred(intensity: 0.7)
        generator.prepare()
    }
}
