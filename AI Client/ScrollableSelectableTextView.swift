import SwiftUI
import UIKit

struct ScrollableSelectableTextView: UIViewRepresentable {
    let text: String
    var chunks: [String] = []
    var appendsChunksProgressively = false
    var streamingChannel: StreamingTextUpdateChannel?
    var textColor: UIColor
    var font: UIFont
    var textAlignment: NSTextAlignment = .left
    var height: CGFloat = 340
    var scrollsToBottom = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.dataDetectorTypes = []
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.textColor = textColor
        textView.font = font
        textView.textAlignment = textAlignment

        if let streamingChannel {
            context.coordinator.configureStreaming(
                textView,
                channel: streamingChannel,
                attributes: textAttributes,
                scrollsToBottom: scrollsToBottom
            )
        } else if !chunks.isEmpty {
            context.coordinator.update(
                textView,
                chunks: chunks,
                appendsProgressively: appendsChunksProgressively,
                attributes: textAttributes,
                scrollsToBottom: scrollsToBottom
            )
        } else {
            context.coordinator.update(
                textView,
                text: text,
                attributes: textAttributes,
                scrollsToBottom: scrollsToBottom
            )
        }
    }

    func makeCoordinator() -> ScrollableTextCoordinator {
        ScrollableTextCoordinator()
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: ScrollableTextCoordinator) {
        coordinator.detachStreamingChannel()
        uiView.delegate = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

}
