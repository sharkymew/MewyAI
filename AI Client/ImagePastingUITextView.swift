import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ImagePastingUITextView: UITextView {
    var onPasteImageProviders: (([NSItemProvider]) -> Void)?
    private let placeholderLabel = UILabel()
    private var placeholderTrailingConstraint: NSLayoutConstraint?
    private var maxVisibleLineCount = 5
    private var fillsAvailableHeight = false

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollingBehavior()
    }

    func configure(
        maxVisibleLineCount: Int,
        fillsAvailableHeight: Bool,
        trailingAccessoryInset: CGFloat
    ) {
        let clampedLineCount = max(maxVisibleLineCount, 1)
        var didChangeLayoutBehavior = false

        if self.maxVisibleLineCount != clampedLineCount {
            self.maxVisibleLineCount = clampedLineCount
            didChangeLayoutBehavior = true
        }

        if self.fillsAvailableHeight != fillsAvailableHeight {
            self.fillsAvailableHeight = fillsAvailableHeight
            didChangeLayoutBehavior = true
        }

        alwaysBounceVertical = fillsAvailableHeight

        if abs(textContainerInset.right - trailingAccessoryInset) > 0.5 {
            textContainerInset.right = trailingAccessoryInset
            placeholderTrailingConstraint?.constant = -trailingAccessoryInset
            didChangeLayoutBehavior = true
        }

        if didChangeLayoutBehavior {
            setNeedsLayout()
        }
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    func updateScrollingBehavior() {
        if !isScrollEnabled {
            isScrollEnabled = true
        }

        showsVerticalScrollIndicator = fillsAvailableHeight || measuredVisualLineCount() > maxVisibleLineCount
    }

    func scrollCaretToVisibleIfNeeded() {
        guard isFirstResponder, isScrollEnabled else { return }

        let textLength = ((text ?? "") as NSString).length
        let caretLocation = min(selectedRange.location + selectedRange.length, textLength)
        scrollRangeToVisible(NSRange(location: caretLocation, length: 0))
    }

    func measuredVisualLineCount() -> Int {
        let textWidth = bounds.width
            - textContainerInset.left
            - textContainerInset.right
            - textContainer.lineFragmentPadding * 2
        guard textWidth > 0 else { return 1 }

        let text = text ?? ""
        guard !text.isEmpty else { return 1 }

        let font = font ?? .preferredFont(forTextStyle: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )

        let baseLineCount = Int(ceil(max(boundingRect.height, font.lineHeight) / max(font.lineHeight, 1)))
        let lineCount = text.hasSuffix("\n") ? baseLineCount + 1 : baseLineCount
        return max(lineCount, 1)
    }

    private func setupPlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = font ?? .preferredFont(forTextStyle: .body)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        let trailingConstraint = placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        placeholderTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            trailingConstraint
        ])
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)),
           UIPasteboard.general.hasImages {
            return true
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let imageProviders = UIPasteboard.general.itemProviders.filter { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }
        }
        guard !imageProviders.isEmpty else {
            super.paste(sender)
            return
        }

        onPasteImageProviders?(imageProviders)
    }
}
