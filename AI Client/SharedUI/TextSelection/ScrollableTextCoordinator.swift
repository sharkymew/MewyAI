import UIKit

private struct TextChunksSignature: Equatable {
    let count: Int
    let totalUTF16Length: Int
    let firstPrefix: String
    let lastSuffix: String

    init(_ chunks: [String]) {
        count = chunks.count
        totalUTF16Length = chunks.reduce(0) { $0 + $1.utf16.count }
        firstPrefix = chunks.first.map { String($0.prefix(16)) } ?? ""
        lastSuffix = chunks.last.map { String($0.suffix(16)) } ?? ""
    }
}

@MainActor
final class ScrollableTextCoordinator: NSObject, UITextViewDelegate {
    var previousUTF16Length = 0
    private var appliedStreamingVersion = -1
    private weak var streamingTextView: UITextView?
    private var streamingChannel: StreamingTextUpdateChannel?
    private var streamingObserverID: UUID?
    private var streamingAttributes: [NSAttributedString.Key: Any] = [:]
    private var streamingScrollsToBottom = false
    private var appliedStaticChunksSignature: TextChunksSignature?
    private var progressiveUpdateTask: Task<Void, Never>?
    var pendingScrollTask: Task<Void, Never>?
    var lastImmediateScroll = ContinuousClock.now
    private var isProgressiveResetActive = false
    private var queuedStreamingChunks: [String] = []
    private var userHasPausedAutoScroll = false
    private var isProgrammaticScroll = false

    func update(
        _ textView: UITextView,
        text: String,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) {
        detachStreamingChannel()
        appliedStaticChunksSignature = nil
        appliedStreamingVersion = -1
        let currentUTF16Length = text.utf16.count
        if currentUTF16Length < previousUTF16Length || previousUTF16Length == 0 {
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        } else if currentUTF16Length > previousUTF16Length {
            let delta = (text as NSString).substring(from: previousUTF16Length)
            textView.textStorage.append(NSAttributedString(string: delta, attributes: attributes))
        } else if textView.text != text {
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }

        previousUTF16Length = currentUTF16Length

        if scrollsToBottom {
            scheduleScrollToBottom(textView)
        }
    }

    func update(
        _ textView: UITextView,
        chunks: [String],
        appendsProgressively: Bool,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) {
        detachStreamingChannel()

        let signature = TextChunksSignature(chunks)
        guard signature != appliedStaticChunksSignature else { return }

        appliedStaticChunksSignature = signature
        appliedStreamingVersion = -1
        resetTextView(
            textView,
            update: StreamingTextUpdate(
                version: 0,
                chunks: chunks,
                resetsText: true,
                appendsProgressively: appendsProgressively
            ),
            attributes: attributes,
            scrollsToBottom: scrollsToBottom
        )
    }

    func configureStreaming(
        _ textView: UITextView,
        channel: StreamingTextUpdateChannel,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) {
        if streamingChannel !== channel {
            detachStreamingChannel(keepsText: true)
            appliedStreamingVersion = -1
            streamingChannel = channel
            userHasPausedAutoScroll = false
            streamingObserverID = channel.addObserver { [weak self] update in
                self?.applyStreamingUpdate(update)
            }
        }

        streamingTextView = textView
        streamingAttributes = attributes
        streamingScrollsToBottom = scrollsToBottom

        applyStreamingUpdate(channel.latest)
    }

    func detachStreamingChannel(keepsText: Bool = false) {
        if let streamingObserverID {
            streamingChannel?.removeObserver(streamingObserverID)
        }

        streamingObserverID = nil
        streamingChannel = nil
        streamingTextView = nil
        cancelProgressiveUpdate()
        userHasPausedAutoScroll = false

        if !keepsText {
            appliedStreamingVersion = -1
        }
    }

    private func applyStreamingUpdate(_ streamingUpdate: StreamingTextUpdate) {
        guard streamingUpdate.version != appliedStreamingVersion,
              let textView = streamingTextView else { return }

        if streamingUpdate.resetsText {
            resetTextView(
                textView,
                update: streamingUpdate,
                attributes: streamingAttributes,
                scrollsToBottom: streamingScrollsToBottom
            )
        } else if !streamingUpdate.chunks.isEmpty {
            if isProgressiveResetActive {
                queuedStreamingChunks.append(contentsOf: streamingUpdate.chunks)
            } else if streamingUpdate.appendsProgressively {
                startProgressiveAppend(
                    streamingUpdate.chunks,
                    to: textView,
                    attributes: streamingAttributes,
                    scrollsToBottom: streamingScrollsToBottom
                )
            } else {
                appendChunks(
                    streamingUpdate.chunks,
                    to: textView,
                    attributes: streamingAttributes
                )
            }
        }

        appliedStreamingVersion = streamingUpdate.version

        if streamingScrollsToBottom {
            scheduleScrollToBottom(textView)
        }
    }

    func cancelProgressiveUpdate() {
        progressiveUpdateTask?.cancel()
        progressiveUpdateTask = nil
        pendingScrollTask?.cancel()
        pendingScrollTask = nil
        isProgressiveResetActive = false
        queuedStreamingChunks.removeAll(keepingCapacity: true)
    }

    private func resetTextView(
        _ textView: UITextView,
        update: StreamingTextUpdate,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) {
        cancelProgressiveUpdate()
        userHasPausedAutoScroll = false

        guard update.appendsProgressively else {
            let text = update.chunks.joined()
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
            previousUTF16Length = text.utf16.count
            if scrollsToBottom {
                scheduleScrollToBottom(textView, immediate: true)
            }
            return
        }

        textView.attributedText = NSAttributedString(string: "", attributes: attributes)
        previousUTF16Length = 0
        startProgressiveAppend(
            update.chunks,
            to: textView,
            attributes: attributes,
            scrollsToBottom: scrollsToBottom
        )
    }

    private func startProgressiveAppend(
        _ chunks: [String],
        to textView: UITextView,
        attributes: [NSAttributedString.Key: Any],
        scrollsToBottom: Bool
    ) {
        cancelProgressiveUpdate()
        isProgressiveResetActive = true

        progressiveUpdateTask = Task { @MainActor [weak textView, weak self] in
            guard let textView, let self else { return }

            await self.appendChunksProgressively(
                chunks,
                to: textView,
                attributes: attributes,
                scrollsToBottom: scrollsToBottom
            )

            guard !Task.isCancelled else { return }
            while !self.queuedStreamingChunks.isEmpty {
                let queuedChunks = self.queuedStreamingChunks
                self.queuedStreamingChunks.removeAll(keepingCapacity: true)
                await self.appendChunksProgressively(
                    queuedChunks,
                    to: textView,
                    attributes: attributes,
                    scrollsToBottom: scrollsToBottom
                )
                guard !Task.isCancelled else { return }
            }

            self.isProgressiveResetActive = false
            if scrollsToBottom {
                self.scheduleScrollToBottom(textView, immediate: true)
            }
            self.progressiveUpdateTask = nil
        }
    }

    func appendChunks(
        _ chunks: [String],
        to textView: UITextView,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let nonEmptyChunks = chunks.filter { !$0.isEmpty }
        guard !nonEmptyChunks.isEmpty else { return }

        if nonEmptyChunks.count == 1, let chunk = nonEmptyChunks.first {
            textView.textStorage.append(NSAttributedString(string: chunk, attributes: attributes))
            previousUTF16Length += chunk.utf16.count
            return
        }

        let attributedChunks = NSMutableAttributedString()
        var appendedUTF16Length = 0
        for chunk in nonEmptyChunks {
            attributedChunks.append(NSAttributedString(string: chunk, attributes: attributes))
            appendedUTF16Length += chunk.utf16.count
        }

        textView.textStorage.beginEditing()
        textView.textStorage.append(attributedChunks)
        textView.textStorage.endEditing()
        previousUTF16Length += appendedUTF16Length
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard streamingScrollsToBottom else { return }
        userHasPausedAutoScroll = true
        pendingScrollTask?.cancel()
        pendingScrollTask = nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard streamingScrollsToBottom, !isProgrammaticScroll else { return }
        if isScrolledNearBottom(scrollView) {
            userHasPausedAutoScroll = false
        }
    }

    func canAutoScroll(_ scrollView: UIScrollView) -> Bool {
        guard userHasPausedAutoScroll else { return true }
        if isScrolledNearBottom(scrollView) {
            userHasPausedAutoScroll = false
            return true
        }
        return false
    }

    func markProgrammaticScroll(_ isActive: Bool) {
        isProgrammaticScroll = isActive
    }

    func isScrolledNearBottom(_ scrollView: UIScrollView) -> Bool {
        let visibleBottom = scrollView.contentOffset.y
            + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        let distanceFromBottom = scrollView.contentSize.height - visibleBottom
        return distanceFromBottom <= Self.bottomDetectionTolerance
    }

    private static let bottomDetectionTolerance: CGFloat = 12

}
