import Foundation
import SwiftUI
import UIKit

struct ImagePastingTextView: UIViewRepresentable {
    let text: String
    let textRevision: Int
    @Binding var isFocused: Bool
    let focusRequestID: Int
    let focusDelay: TimeInterval
    let placeholder: String
    let maxVisibleLineCount: Int
    let fillsAvailableHeight: Bool
    let trailingAccessoryInset: CGFloat
    let allowsFocus: Bool
    let onTextChanged: (String) -> Void
    let onMeasuredLineCountChanged: (Int) -> Void
    let onPasteImageProviders: ([NSItemProvider]) -> Void

    func makeUIView(context: Context) -> ImagePastingUITextView {
        let textView = ImagePastingUITextView()
        textView.delegate = context.coordinator
        textView.onPasteImageProviders = onPasteImageProviders
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: ImagePastingUITextView, context: Context) {
        textView.configure(
            maxVisibleLineCount: maxVisibleLineCount,
            fillsAvailableHeight: fillsAvailableHeight,
            trailingAccessoryInset: trailingAccessoryInset
        )

        var didApplyExternalText = false
        if context.coordinator.lastAppliedTextRevision != textRevision,
           (textView.text ?? "") != text {
            let previousText = textView.text ?? ""
            let previousSelectedRange = textView.selectedRange
            textView.text = text
            didApplyExternalText = true
            textView.selectedRange = context.coordinator.restoredSelectedRange(
                previousText: previousText,
                newText: text,
                previousSelectedRange: previousSelectedRange
            )
            textView.scrollCaretToVisibleIfNeeded()
        }
        context.coordinator.lastAppliedTextRevision = textRevision

        context.coordinator.onTextChanged = onTextChanged
        context.coordinator.onMeasuredLineCountChanged = onMeasuredLineCountChanged
        textView.onPasteImageProviders = onPasteImageProviders
        textView.isEditable = true
        textView.isSelectable = true
        textView.placeholderText = placeholder
        textView.accessibilityLabel = placeholder
        textView.updatePlaceholderVisibility()
        textView.updateScrollingBehavior()
        textView.scrollCaretToVisibleIfNeeded()
        if didApplyExternalText || context.coordinator.needsScheduledLayoutStateRefresh(for: textView) {
            context.coordinator.scheduleLayoutStateRefresh(for: textView)
        }

        context.coordinator.updateFocus(
            for: textView,
            shouldBeFocused: isFocused,
            allowsFocus: allowsFocus,
            requestID: focusRequestID,
            focusDelay: focusDelay
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        let fittingWidth = width > 0 ? width : UIScreen.main.bounds.width
        let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        if fillsAvailableHeight, let proposedHeight = proposal.height, proposedHeight > 0 {
            return CGSize(width: fittingWidth, height: max(proposedHeight, lineHeight))
        }

        let fittingSize = uiView.sizeThatFits(
            CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        )

        let maxHeight = lineHeight * CGFloat(max(maxVisibleLineCount, 1))
        let height = min(max(fittingSize.height, lineHeight), maxHeight)
        return CGSize(width: fittingWidth, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isFocused: $isFocused,
            onTextChanged: onTextChanged,
            onMeasuredLineCountChanged: onMeasuredLineCountChanged
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let isFocused: Binding<Bool>
        var onTextChanged: (String) -> Void
        var onMeasuredLineCountChanged: (Int) -> Void
        private var lastHandledFocusRequestID: Int?
        private var pendingDelayedFocusRequestID: Int?
        var lastAppliedTextRevision: Int?
        private var lastScheduledLayoutRefreshKey: LayoutRefreshKey?

        private struct LayoutRefreshKey: Equatable {
            let width: CGFloat
            let trailingInset: CGFloat
        }

        init(
            isFocused: Binding<Bool>,
            onTextChanged: @escaping (String) -> Void,
            onMeasuredLineCountChanged: @escaping (Int) -> Void
        ) {
            self.isFocused = isFocused
            self.onTextChanged = onTextChanged
            self.onMeasuredLineCountChanged = onMeasuredLineCountChanged
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            onTextChanged(updatedText)
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
            if let textView = textView as? ImagePastingUITextView {
                refreshLayoutState(for: textView)
            } else {
                publishMeasuredLineCount(for: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? ImagePastingUITextView)?.scrollCaretToVisibleIfNeeded()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
        }

        func updateFocus(
            for textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            allowsFocus: Bool,
            requestID: Int,
            focusDelay: TimeInterval
        ) {
            let isNewRequest = lastHandledFocusRequestID != requestID
            guard allowsFocus else {
                lastHandledFocusRequestID = requestID
                pendingDelayedFocusRequestID = nil
                if textView.isFirstResponder {
                    textView.resignFirstResponder()
                }
                return
            }

            guard isNewRequest || (shouldBeFocused && !textView.isFirstResponder) else { return }

            if isNewRequest {
                lastHandledFocusRequestID = requestID
                pendingDelayedFocusRequestID = nil
            }

            if shouldBeFocused, focusDelay > 0 {
                guard pendingDelayedFocusRequestID != requestID else { return }

                pendingDelayedFocusRequestID = requestID
                retryFocus(
                    to: textView,
                    shouldBeFocused: shouldBeFocused,
                    attemptsRemaining: 4,
                    delay: focusDelay
                )
                return
            }

            if shouldBeFocused, textView.window != nil {
                if !textView.becomeFirstResponder() {
                    retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
                }
                return
            }

            if shouldBeFocused {
                retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
            } else if isNewRequest, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        private func retryFocus(
            to textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            attemptsRemaining: Int,
            delay: TimeInterval = 0.01
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.isFocused.wrappedValue == shouldBeFocused,
                      shouldBeFocused != textView.isFirstResponder else {
                    return
                }

                if shouldBeFocused {
                    guard textView.window != nil else {
                        if attemptsRemaining > 0 {
                            self.retryFocus(
                                to: textView,
                                shouldBeFocused: shouldBeFocused,
                                attemptsRemaining: attemptsRemaining - 1
                            )
                        }
                        return
                    }

                    if !textView.becomeFirstResponder(), attemptsRemaining > 0 {
                        self.retryFocus(
                            to: textView,
                            shouldBeFocused: shouldBeFocused,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                } else {
                    textView.resignFirstResponder()
                }
            }
        }

        func refreshLayoutState(for textView: ImagePastingUITextView) {
            textView.updateScrollingBehavior()
            publishMeasuredLineCount(for: textView)
            textView.scrollCaretToVisibleIfNeeded()
        }

        func needsScheduledLayoutStateRefresh(for textView: ImagePastingUITextView) -> Bool {
            guard textView.bounds.width > 0 else { return false }

            let key = LayoutRefreshKey(
                width: Self.roundedLayoutValue(textView.bounds.width),
                trailingInset: Self.roundedLayoutValue(textView.textContainerInset.right)
            )
            guard lastScheduledLayoutRefreshKey != key else { return false }

            lastScheduledLayoutRefreshKey = key
            return true
        }

        func scheduleLayoutStateRefresh(for textView: ImagePastingUITextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.refreshLayoutState(for: textView)
            }
        }

        func restoredSelectedRange(
            previousText: String,
            newText: String,
            previousSelectedRange: NSRange
        ) -> NSRange {
            let previousTextLength = (previousText as NSString).length
            let newTextLength = (newText as NSString).length

            if previousSelectedRange.location >= previousTextLength {
                return NSRange(location: newTextLength, length: 0)
            }

            let location = min(max(previousSelectedRange.location, 0), newTextLength)
            let availableLength = max(newTextLength - location, 0)
            let length = min(max(previousSelectedRange.length, 0), availableLength)
            return NSRange(location: location, length: length)
        }

        private func publishMeasuredLineCount(for textView: UITextView) {
            if let textView = textView as? ImagePastingUITextView {
                guard textView.bounds.width > 0 else { return }
                onMeasuredLineCountChanged(textView.measuredVisualLineCount())
            } else {
                let lineHeight = max(
                    textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight,
                    1
                )
                let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
                let contentHeight = max(textView.contentSize.height - verticalInsets, lineHeight)
                let lineCount = Int(ceil(contentHeight / lineHeight))
                onMeasuredLineCountChanged(lineCount)
            }
        }

        private static func roundedLayoutValue(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }
    }
}
