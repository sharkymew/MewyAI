import SwiftUI
import UIKit

struct MemorySummarySelectableTextView: UIViewRepresentable {
    let text: String
    let onForgetSelection: (String) -> Void

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
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: IntrinsicTextView, context: Context) {
        context.coordinator.onForgetSelection = onForgetSelection
        if textView.text != text {
            textView.text = text
            textView.invalidateIntrinsicContentSize()
        }
        textView.textColor = .label
        textView.font = .preferredFont(forTextStyle: .body)
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
        Coordinator(onForgetSelection: onForgetSelection)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onForgetSelection: (String) -> Void

        init(onForgetSelection: @escaping (String) -> Void) {
            self.onForgetSelection = onForgetSelection
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let text = textView.text,
                  range.location != NSNotFound,
                  range.length > 0,
                  range.location + range.length <= (text as NSString).length else {
                return UIMenu(children: suggestedActions)
            }

            let selectedText = (text as NSString)
                .substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedText.isEmpty else {
                return UIMenu(children: suggestedActions)
            }

            let forgetAction = UIAction(
                title: "不再提到",
                image: UIImage(systemName: "minus.circle")
            ) { [weak self] _ in
                self?.onForgetSelection(selectedText)
            }

            return UIMenu(children: suggestedActions + [forgetAction])
        }
    }
}
