import Foundation
import SwiftUI
import Combine
import UIKit

final class StreamingOutputHaptics: ObservableObject {
    private let refreshGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private var lastImpactAt: Date?
    private var refreshContinuationTask: Task<Void, Never>?
    private static let minimumImpactInterval: TimeInterval = 0.09
    private static let continuationImpactInterval: Duration = .milliseconds(90)
    private static let longOutputUTF16PerAdditionalImpact = 900
    private static let maximumContinuationImpactCount = 8

    deinit {
        refreshContinuationTask?.cancel()
    }

    func prepareForStreaming() {
        cancelRefreshContinuation()
        lastImpactAt = nil
        refreshGenerator.prepare()
        completionGenerator.prepare()
    }

    func impactForOutputRefresh(chunks: [String]) {
        impactForOutputRefresh()
        scheduleRefreshContinuationIfNeeded(for: chunks)
    }

    private func impactForOutputRefresh() {
        let now = Date()
        if let lastImpactAt,
           now.timeIntervalSince(lastImpactAt) < Self.minimumImpactInterval {
            return
        }

        refreshGenerator.prepare()
        refreshGenerator.impactOccurred(intensity: 0.55)
        refreshGenerator.prepare()
        lastImpactAt = now
    }

    func impactForOutputCompletion() {
        cancelRefreshContinuation()
        completionGenerator.prepare()
        completionGenerator.impactOccurred(intensity: 1.0)
        completionGenerator.prepare()
        lastImpactAt = nil
    }

    func reset() {
        cancelRefreshContinuation()
        lastImpactAt = nil
    }

    static func continuationImpactCount(forUTF16Length length: Int) -> Int {
        guard length > longOutputUTF16PerAdditionalImpact else { return 0 }

        return min(
            length / longOutputUTF16PerAdditionalImpact,
            maximumContinuationImpactCount
        )
    }

    private func scheduleRefreshContinuationIfNeeded(for chunks: [String]) {
        cancelRefreshContinuation()

        let utf16Length = chunks.reduce(0) { $0 + $1.utf16.count }
        let impactCount = Self.continuationImpactCount(forUTF16Length: utf16Length)
        guard impactCount > 0 else { return }

        refreshContinuationTask = Task { [weak self] in
            for _ in 0..<impactCount {
                try? await Task.sleep(for: Self.continuationImpactInterval)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.impactForOutputRefresh()
                }
            }
        }
    }

    private func cancelRefreshContinuation() {
        refreshContinuationTask?.cancel()
        refreshContinuationTask = nil
    }
}
