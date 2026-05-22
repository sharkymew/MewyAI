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

struct SelectableMarkdownTextView: UIViewRepresentable {
    let markdown: String
    var textColor: UIColor = .label
    var baseFont: UIFont = .preferredFont(forTextStyle: .body)
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
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: IntrinsicTextView, context: Context) {
        textView.attributedText = MarkdownTextFormatter.attributedString(
            from: markdown,
            baseFont: baseFont,
            textColor: textColor,
            textAlignment: textAlignment
        )
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IntrinsicTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }

        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }
}

private enum MarkdownTextFormatter {
    static func attributedString(
        from markdown: String,
        baseFont: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            let style = lineStyle(for: line, baseFont: baseFont)
            appendInlineMarkdown(
                style.text,
                to: result,
                font: style.font,
                textColor: textColor,
                paragraphSpacing: style.paragraphSpacing,
                textAlignment: textAlignment
            )

            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private static func lineStyle(
        for line: String,
        baseFont: UIFont
    ) -> (text: String, font: UIFont, paragraphSpacing: CGFloat) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let leadingWhitespaceCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let leadingWhitespace = String(line.prefix(leadingWhitespaceCount))

        for level in 1...3 {
            let marker = String(repeating: "#", count: level) + " "
            if trimmed.hasPrefix(marker) {
                let text = String(trimmed.dropFirst(marker.count))
                let size = baseFont.pointSize + CGFloat(6 - level * 2)
                return (text, .boldSystemFont(ofSize: max(baseFont.pointSize, size)), 8)
            }
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let text = leadingWhitespace + "• " + String(trimmed.dropFirst(2))
            return (text, baseFont, 4)
        }

        return (line, baseFont, 4)
    }

    private static func appendInlineMarkdown(
        _ text: String,
        to result: NSMutableAttributedString,
        font: UIFont,
        textColor: UIColor,
        paragraphSpacing: CGFloat,
        textAlignment: NSTextAlignment
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = paragraphSpacing

        var index = text.startIndex
        while index < text.endIndex {
            if let token = nextToken(in: text, from: index) {
                appendPlainText(
                    String(text[index..<token.range.lowerBound]),
                    to: result,
                    font: font,
                    textColor: textColor,
                    paragraphStyle: paragraphStyle
                )
                appendPlainText(
                    token.content,
                    to: result,
                    font: tokenFont(baseFont: font, token: token.marker),
                    textColor: textColor,
                    paragraphStyle: paragraphStyle
                )
                index = token.range.upperBound
            } else {
                appendPlainText(
                    String(text[index...]),
                    to: result,
                    font: font,
                    textColor: textColor,
                    paragraphStyle: paragraphStyle
                )
                break
            }
        }
    }

    private static func appendPlainText(
        _ text: String,
        to result: NSMutableAttributedString,
        font: UIFont,
        textColor: UIColor,
        paragraphStyle: NSParagraphStyle
    ) {
        guard !text.isEmpty else { return }
        result.append(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
        )
    }

    private static func nextToken(
        in text: String,
        from index: String.Index
    ) -> (marker: String, content: String, range: Range<String.Index>)? {
        for marker in ["**", "`", "*"] {
            guard let start = text[index...].range(of: marker)?.lowerBound else { continue }
            let contentStart = text.index(start, offsetBy: marker.count)
            guard contentStart < text.endIndex,
                  let end = text[contentStart...].range(of: marker)?.lowerBound else {
                continue
            }
            let content = String(text[contentStart..<end])
            let range = start..<text.index(end, offsetBy: marker.count)
            return (marker, content, range)
        }
        return nil
    }

    private static func tokenFont(baseFont: UIFont, token: String) -> UIFont {
        switch token {
        case "**":
            return .boldSystemFont(ofSize: baseFont.pointSize)
        case "`":
            return .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        case "*":
            return .italicSystemFont(ofSize: baseFont.pointSize)
        default:
            return baseFont
        }
    }
}

final class IntrinsicTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
    }
}
