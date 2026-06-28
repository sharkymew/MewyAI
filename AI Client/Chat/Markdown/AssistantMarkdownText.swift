import Foundation
import SwiftUI

struct AssistantMarkdownText: View {
    let renderCache: MarkdownRenderCacheEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(renderCache.segments) { segment in
                switch segment.kind {
                case let .text(blocks):
                    if !blocks.isEmpty {
                        SelectableMarkdownTextView(blocks: blocks)
                    }
                case let .code(language, code):
                    ChatCodeBlock(content: code, language: language)
                case let .math(formula):
                    PreparedLaTeXFormulaView(formula: formula)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
