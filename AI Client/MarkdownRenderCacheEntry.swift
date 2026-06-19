import Foundation
import SwiftUI

nonisolated struct MarkdownRenderCacheEntry: @unchecked Sendable {
    let signature: String
    let renderedMarkdown: String
    let segments: [PreparedChatMarkdownSegment]
    private static let maxRenderedLaTeXFormulaCount = LaTeXRenderBudget.maxFormulasPerMessage

    private nonisolated init(
        signature: String,
        renderedMarkdown: String,
        segments: [PreparedChatMarkdownSegment]
    ) {
        self.signature = signature
        self.renderedMarkdown = renderedMarkdown
        self.segments = segments
    }

    nonisolated static func make(content: String, style: MarkdownRenderStyle) async -> MarkdownRenderCacheEntry {
        let signature = Self.signature(for: content, style: style)
        let renderedMarkdown = content
        var preparedSegments: [PreparedChatMarkdownSegment] = []
        var renderedFormulaCount = 0

        for segment in ChatMarkdownBlockSegment.split(content) {
            switch segment.kind {
            case let .text(text):
                let preprocessedText = ChatMarkdownPreprocessor.preprocess(text)
                let trimmedText = preprocessedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let blocks = trimmedText.isEmpty ? [] : await PreparedMarkdownBlockRenderer.renderBlocks(
                    markdown: trimmedText,
                    style: style
                )
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .text(blocks)))
            case let .code(language, code):
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .code(language: language, code: code)))
            case let .math(formula, displayMode):
                let preparedFormula: PreparedLaTeXFormula
                if renderedFormulaCount < maxRenderedLaTeXFormulaCount,
                   LaTeXRenderBudget.canRenderFormula(formula) {
                    renderedFormulaCount += 1
                    preparedFormula = await LaTeXSVGRenderer.shared.render(
                        formula: formula,
                        displayMode: displayMode,
                        style: style
                    )
                } else {
                    preparedFormula = LaTeXSVGRenderer.fallbackFormula(
                        formula: formula,
                        displayMode: displayMode,
                        error: "Formula render budget exceeded"
                    )
                }
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .math(preparedFormula)))
            }
        }

        return MarkdownRenderCacheEntry(
            signature: signature,
            renderedMarkdown: renderedMarkdown,
            segments: preparedSegments
        )
    }

    nonisolated static func signature(for content: String, style: MarkdownRenderStyle) -> String {
        "\(style.signature):\(content.count):\(content.hashValue)"
    }
}
