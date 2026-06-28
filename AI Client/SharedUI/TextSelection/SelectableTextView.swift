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
        if textView.text != text {
            textView.text = text
            textView.invalidateIntrinsicContentSize()
        }
        textView.textColor = textColor
        textView.font = font
        textView.textAlignment = textAlignment
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

struct SelectableAttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var textAlignment: NSTextAlignment = .left

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
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.tintColor = .systemBlue
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: IntrinsicTextView, context: Context) {
        if textView.attributedText?.isEqual(to: attributedText) != true {
            textView.attributedText = attributedText
            textView.invalidateIntrinsicContentSize()
        }
        textView.textAlignment = textAlignment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IntrinsicTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }

        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case let .link(url) = textItem.content else { return defaultAction }
            return isSafeLink(url) ? defaultAction : nil
        }

        private func isSafeLink(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return ["https", "http", "mailto"].contains(scheme)
                && url.user == nil
                && url.password == nil
        }
    }
}

final class IntrinsicTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
    }
}
