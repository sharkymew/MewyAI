import Foundation
import SwiftUI
import Combine

@MainActor
final class ChatScrollController: ObservableObject {
    @Published private var shouldAutoScroll = true
    @Published private var isScrolledToBottom = true

    private var isUserDragging = false
    private var hasUserPausedAutoScroll = false
    private var reachedBottomDuringUserInteraction = false
    private var isAutoScrollScheduled = false
    private var isBottomDistanceUpdateScheduled = false
    private var pendingDistanceFromBottom: CGFloat?
    private var lastDistanceFromBottom: CGFloat = 0
    private var autoScrollTask: Task<Void, Never>?
    private var userInteractionResumeTask: Task<Void, Never>?
    private var conversationRestoreTask: Task<Void, Never>?
    private var scrollAction: ((Bool) -> Void)?

    var shouldShowScrollToBottomButton: Bool {
        !isScrolledToBottom
    }

    deinit {
        autoScrollTask?.cancel()
        userInteractionResumeTask?.cancel()
        conversationRestoreTask?.cancel()
    }

    func setScrollAction(_ action: @escaping (Bool) -> Void) {
        scrollAction = action
    }

    func clearScrollAction() {
        scrollAction = nil
    }

    func beginUserScrollInteraction() {
        userInteractionResumeTask?.cancel()
        userInteractionResumeTask = nil
        if !isUserDragging {
            reachedBottomDuringUserInteraction = false
        }
        isUserDragging = true
        pauseAutoScrollForUser()
    }

    func endUserScrollInteraction() {
        isUserDragging = false
        scheduleUserInteractionResumeAudit()
    }

    func scheduleBottomDistanceUpdate(_ distanceFromBottom: CGFloat) {
        lastDistanceFromBottom = distanceFromBottom
        pendingDistanceFromBottom = distanceFromBottom

        guard !isBottomDistanceUpdateScheduled else { return }
        isBottomDistanceUpdateScheduled = true

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }

            let distanceFromBottom = pendingDistanceFromBottom ?? 0
            pendingDistanceFromBottom = nil
            isBottomDistanceUpdateScheduled = false
            updateBottomDistance(distanceFromBottom)
        }
    }

    private func updateBottomDistance(_ distanceFromBottom: CGFloat) {
        lastDistanceFromBottom = distanceFromBottom
        let isAtBottom = distanceFromBottom <= ChatScrollMetrics.bottomThreshold

        if isScrolledToBottom != isAtBottom {
            setIsScrolledToBottom(isAtBottom)
        }

        if isAtBottom {
            if isUserDragging {
                reachedBottomDuringUserInteraction = true
            }

            if hasUserPausedAutoScroll {
                if !isUserDragging {
                    resumeAutoScroll()
                }
            } else {
                setShouldAutoScroll(true)
            }
        } else if isUserDragging {
            pauseAutoScrollForUser()
        }
    }

    func returnToBottom() {
        resumeAutoScroll()
        requestImmediateAutoScroll(animated: false)
    }

    func resetForConversationChange() {
        cancelScheduledAutoScroll()
        userInteractionResumeTask?.cancel()
        userInteractionResumeTask = nil
        isUserDragging = false
        hasUserPausedAutoScroll = false
        reachedBottomDuringUserInteraction = false
        isBottomDistanceUpdateScheduled = false
        pendingDistanceFromBottom = nil
        lastDistanceFromBottom = 0
        setIsScrolledToBottom(true)
        setShouldAutoScroll(true)
    }

    func restoreAfterConversationChange() {
        conversationRestoreTask?.cancel()
        resetForConversationChange()
        requestImmediateAutoScroll(animated: false)

        conversationRestoreTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            requestImmediateAutoScroll(animated: false)

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            requestImmediateAutoScroll(animated: false)
            conversationRestoreTask = nil
        }
    }

    func requestImmediateAutoScroll(animated: Bool = false) {
        guard shouldAutoScroll else { return }
        cancelScheduledAutoScroll()
        scrollAction?(animated)
    }

    func scheduleStreamingAutoScroll() {
        guard shouldAutoScroll else { return }
        guard !hasUserPausedAutoScroll else { return }
        guard !isUserDragging else { return }
        guard !isAutoScrollScheduled else { return }
        isAutoScrollScheduled = true
        autoScrollTask?.cancel()

        autoScrollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard let self, !Task.isCancelled else { return }
            if shouldAutoScroll {
                scrollAction?(false)
            }
            isAutoScrollScheduled = false
            autoScrollTask = nil
        }
    }

    func cancelScheduledAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrollScheduled = false
    }

    private func setShouldAutoScroll(_ value: Bool) {
        guard shouldAutoScroll != value else { return }
        shouldAutoScroll = value
    }

    private func setIsScrolledToBottom(_ value: Bool) {
        guard isScrolledToBottom != value else { return }
        isScrolledToBottom = value
    }

    private func pauseAutoScrollForUser() {
        hasUserPausedAutoScroll = true
        setShouldAutoScroll(false)
        cancelScheduledAutoScroll()
    }

    private func resumeAutoScroll() {
        userInteractionResumeTask?.cancel()
        userInteractionResumeTask = nil
        hasUserPausedAutoScroll = false
        reachedBottomDuringUserInteraction = false
        setShouldAutoScroll(true)
    }

    @discardableResult
    private func resumeAutoScrollIfUserReturnedToBottom() -> Bool {
        guard hasUserPausedAutoScroll else { return false }
        let isAtBottom = isScrolledToBottom || lastDistanceFromBottom <= ChatScrollMetrics.bottomThreshold
        let reachedBottomRecently = reachedBottomDuringUserInteraction
            && lastDistanceFromBottom <= ChatScrollMetrics.bottomResumeCarryDistance
        guard isAtBottom || reachedBottomRecently else { return false }
        resumeAutoScroll()
        return true
    }

    private func scheduleUserInteractionResumeAudit() {
        userInteractionResumeTask?.cancel()

        userInteractionResumeTask = Task { @MainActor [weak self] in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }

            resumeAutoScrollIfUserReturnedToBottom()
            userInteractionResumeTask = nil
        }
    }
}
