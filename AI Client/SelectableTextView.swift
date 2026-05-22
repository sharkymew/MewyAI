import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    let text: String
    var textColor: UIColor
    var font: UIFont
    var textAlignment: NSTextAlignment = .natural
    var sizing: Sizing = .fill
    var onTap: (() -> Void)?

    enum Sizing {
        case fill
        case natural
    }

    func makeUIView(context: Context) -> IntrinsicTextView {
        let textView = IntrinsicTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapText))
        tapGesture.cancelsTouchesInView = false
        textView.addGestureRecognizer(tapGesture)

        return textView
    }

    func updateUIView(_ textView: IntrinsicTextView, context: Context) {
        context.coordinator.onTap = onTap
        textView.text = text
        textView.textColor = textColor
        textView.font = font
        textView.textAlignment = textAlignment
        textView.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IntrinsicTextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? uiView.bounds.width
        guard maxWidth > 0 else { return nil }

        let width: CGFloat
        switch sizing {
        case .fill:
            width = maxWidth
        case .natural:
            width = min(maxWidth, naturalTextWidth(for: uiView, maxWidth: maxWidth))
        }

        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    private func naturalTextWidth(for textView: UITextView, maxWidth: CGFloat) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return max(1, ceil(bounds.width + textView.textContainerInset.left + textView.textContainerInset.right))
    }

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?

        init(onTap: (() -> Void)?) {
            self.onTap = onTap
        }

        @objc func didTapText() {
            onTap?()
        }
    }
}

final class IntrinsicTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
    }
}
