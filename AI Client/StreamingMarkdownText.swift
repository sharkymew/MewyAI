import Foundation
import SwiftUI

struct StreamingMarkdownText: View, Equatable {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    static func == (lhs: StreamingMarkdownText, rhs: StreamingMarkdownText) -> Bool {
        lhs.markdown == rhs.markdown
    }

    var body: some View {
        if ChatLaTeXSegmentParser.containsInlineMath(in: markdown) {
            LaTeXInlineTextView(
                text: markdown,
                textColor: .label,
                font: .preferredFont(forTextStyle: .body),
                textAlignment: .left
            )
        } else {
            Text(Self.attributedString(from: markdown))
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func attributedString(from markdown: String) -> AttributedString {
        let fullOptions = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: fullOptions) {
            return attributed
        }

        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: inlineOptions)) ?? AttributedString(markdown)
    }
}
