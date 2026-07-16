import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class StreamingOutputHaptics: ObservableObject {
    private let refreshGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private var lastImpactAt: Date?
    private var refreshContinuationTask: Task<Void, Never>?
    private var streamedUTF16Length = 0
    private var targetContinuationImpactCount = 0
    private var deliveredContinuationImpactCount = 0
    private static let minimumImpactInterval: TimeInterval = 0.09
    private static let continuationImpactInterval: Duration = .milliseconds(90)
    private nonisolated static let longOutputUTF16PerAdditionalImpact = 900
    private nonisolated static let maximumContinuationImpactCount = 8

    deinit {
        refreshContinuationTask?.cancel()
    }

    func prepareForStreaming() {
        resetContinuationState()
        lastImpactAt = nil
        refreshGenerator.prepare()
        completionGenerator.prepare()
    }

    func impactForOutputRefresh(chunks: [String]) {
        streamedUTF16Length += chunks.reduce(0) { $0 + $1.utf16.count }
        impactForOutputRefresh()
        scheduleRefreshContinuationIfNeeded()
    }

    @discardableResult
    private func impactForOutputRefresh() -> Bool {
        let now = Date()
        if let lastImpactAt,
           now.timeIntervalSince(lastImpactAt) < Self.minimumImpactInterval {
            return false
        }

        refreshGenerator.impactOccurred(intensity: 0.55)
        refreshGenerator.prepare()
        lastImpactAt = now
        return true
    }

    func impactForOutputCompletion() {
        resetContinuationState()
        completionGenerator.prepare()
        completionGenerator.impactOccurred(intensity: 1.0)
        lastImpactAt = nil
    }

    func reset() {
        resetContinuationState()
        lastImpactAt = nil
    }

    nonisolated static func continuationImpactCount(forUTF16Length length: Int) -> Int {
        guard length > longOutputUTF16PerAdditionalImpact else { return 0 }

        return min(
            length / longOutputUTF16PerAdditionalImpact,
            maximumContinuationImpactCount
        )
    }

    private func scheduleRefreshContinuationIfNeeded() {
        targetContinuationImpactCount = max(
            targetContinuationImpactCount,
            Self.continuationImpactCount(forUTF16Length: streamedUTF16Length)
        )
        guard deliveredContinuationImpactCount < targetContinuationImpactCount,
              refreshContinuationTask == nil else { return }

        refreshContinuationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let deliveredBeforeSleep = self?.deliveredContinuationImpactCount,
                      let targetBeforeSleep = self?.targetContinuationImpactCount else {
                    return
                }
                guard deliveredBeforeSleep < targetBeforeSleep else {
                    self?.refreshContinuationTask = nil
                    return
                }

                try? await Task.sleep(for: Self.continuationImpactInterval)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.deliveredContinuationImpactCount == deliveredBeforeSleep,
                      self.targetContinuationImpactCount >= targetBeforeSleep,
                      self.impactForOutputRefresh() else {
                    continue
                }
                self.deliveredContinuationImpactCount += 1
            }
        }
    }

    private func cancelRefreshContinuation() {
        refreshContinuationTask?.cancel()
        refreshContinuationTask = nil
    }

    private func resetContinuationState() {
        cancelRefreshContinuation()
        streamedUTF16Length = 0
        targetContinuationImpactCount = 0
        deliveredContinuationImpactCount = 0
    }
}
