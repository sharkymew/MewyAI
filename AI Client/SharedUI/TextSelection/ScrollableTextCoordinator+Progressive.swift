import UIKit

private enum ProgressiveTextTiming {
    static let maxUTF16PerFrame = 720
    static let frameDelay: Duration = .milliseconds(16)
    static let scrollThrottle: Duration = .milliseconds(120)
}

extension ScrollableTextCoordinator {
    func appendChunksProgressively(
        _ chunks: [String],
        to textView: UITextView,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) async {
        let maxUTF16PerFrame = ProgressiveTextTiming.maxUTF16PerFrame
        var batch = ""
        batch.reserveCapacity(maxUTF16PerFrame)

        for chunk in chunks {
            guard !Task.isCancelled else { return }

            let chunkLength = chunk.utf16.count
            if chunkLength > maxUTF16PerFrame {
                if !batch.isEmpty {
                    appendChunks([batch], to: textView, attributes: attributes)
                    batch.removeAll(keepingCapacity: true)
                    if scrollsToBottom {
                        scheduleScrollToBottom(textView)
                    }
                    await sleepDisplayFrame()
                }

                await appendTextProgressively(
                    chunk,
                    to: textView,
                    attributes: attributes,
                    scrollsToBottom: scrollsToBottom,
                    maxUTF16PerFrame: maxUTF16PerFrame
                )
                continue
            }

            if batch.utf16.count + chunkLength > maxUTF16PerFrame, !batch.isEmpty {
                appendChunks([batch], to: textView, attributes: attributes)
                batch.removeAll(keepingCapacity: true)
                if scrollsToBottom {
                    scheduleScrollToBottom(textView)
                }
                await sleepDisplayFrame()
            }

            batch += chunk
        }

        if !Task.isCancelled, !batch.isEmpty {
            appendChunks([batch], to: textView, attributes: attributes)
            if scrollsToBottom {
                scheduleScrollToBottom(textView, immediate: true)
            }
        }
    }

    func appendTextProgressively(
        _ text: String,
        to textView: UITextView,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool,
        maxUTF16PerFrame: Int
    ) async {
        let nsText = text as NSString
        var offset = 0

        while offset < nsText.length {
            guard !Task.isCancelled else { return }

            let proposedLength = min(maxUTF16PerFrame, nsText.length - offset)
            let proposedRange = NSRange(location: offset, length: proposedLength)
            let safeRange = nsText.rangeOfComposedCharacterSequences(for: proposedRange)
            appendChunks(
                [nsText.substring(with: safeRange)],
                to: textView,
                attributes: attributes
            )

            offset = NSMaxRange(safeRange)
            if scrollsToBottom {
                scheduleScrollToBottom(textView, immediate: offset >= nsText.length)
            }
            if offset < nsText.length {
                await sleepDisplayFrame()
            }
        }
    }

    func scheduleScrollToBottom(_ textView: UITextView, immediate: Bool = false) {
        guard previousUTF16Length > 0 else { return }
        guard canAutoScroll(textView) else {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
            return
        }

        pendingScrollTask?.cancel()
        let elapsed = lastImmediateScroll.duration(to: .now)
        let shouldScrollNow = immediate || elapsed >= ProgressiveTextTiming.scrollThrottle

        if shouldScrollNow {
            scrollToBottom(textView)
            return
        }

        pendingScrollTask = Task { @MainActor [weak textView, weak self] in
            try? await Task.sleep(for: ProgressiveTextTiming.scrollThrottle)
            guard !Task.isCancelled, let textView, let self else { return }
            guard self.canAutoScroll(textView) else {
                self.pendingScrollTask = nil
                return
            }
            self.scrollToBottom(textView)
            self.pendingScrollTask = nil
        }
    }

    func scrollToBottom(_ textView: UITextView) {
        guard previousUTF16Length > 0 else { return }
        lastImmediateScroll = .now
        markProgrammaticScroll(true)
        textView.scrollRangeToVisible(NSRange(location: previousUTF16Length - 1, length: 1))
        markProgrammaticScroll(false)
    }

    func sleepDisplayFrame() async {
        try? await Task.sleep(for: ProgressiveTextTiming.frameDelay)
    }
}
