import Foundation
import SwiftUI
import Combine
import UIKit

final class StreamingOutputHaptics: ObservableObject {
    private let refreshGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private var lastImpactAt: Date?
    private static let minimumImpactInterval: TimeInterval = 0.055

    func prepareForStreaming() {
        lastImpactAt = nil
        refreshGenerator.prepare()
        completionGenerator.prepare()
    }

    func impactForOutputRefresh() {
        let now = Date()
        if let lastImpactAt,
           now.timeIntervalSince(lastImpactAt) < Self.minimumImpactInterval {
            return
        }

        refreshGenerator.impactOccurred(intensity: 0.55)
        refreshGenerator.prepare()
        lastImpactAt = now
    }

    func impactForOutputCompletion() {
        completionGenerator.impactOccurred(intensity: 1.0)
        completionGenerator.prepare()
        lastImpactAt = nil
    }

    func reset() {
        lastImpactAt = nil
    }
}
