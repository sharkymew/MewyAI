import Foundation
import SwiftUI

struct ChatMarkdownBlockSegment: Identifiable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text(String)
        case code(language: String?, code: String)
        case math(formula: String, displayMode: Bool)
    }

    nonisolated static func split(_ content: String) -> [ChatMarkdownBlockSegment] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [ChatMarkdownBlockSegment] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendText() {
            guard !textBuffer.isEmpty else { return }
            appendTextSegments(textBuffer.joined(separator: "\n"))
            textBuffer.removeAll()
        }

        func appendTextSegments(_ text: String) {
            for segment in ChatLaTeXSegmentParser.split(text) {
                switch segment {
                case let .text(text):
                    segments.append(
                        ChatMarkdownBlockSegment(
                            id: segments.count,
                            kind: .text(text)
                        )
                    )
                case let .math(formula, displayMode):
                    segments.append(
                        ChatMarkdownBlockSegment(
                            id: segments.count,
                            kind: .math(formula: formula, displayMode: displayMode)
                        )
                    )
                }
            }
        }

        func appendCode() {
            segments.append(
                ChatMarkdownBlockSegment(
                    id: segments.count,
                    kind: .code(language: codeLanguage, code: codeBuffer.joined(separator: "\n"))
                )
            )
            codeBuffer.removeAll()
            codeLanguage = nil
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                if codeFence.isClosing(line) {
                    appendCode()
                    activeCodeFence = nil
                } else {
                    codeBuffer.append(line)
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendText()
                activeCodeFence = codeFence
                codeLanguage = codeFence.language
            } else {
                textBuffer.append(line)
            }
        }

        if activeCodeFence != nil {
            appendCode()
        } else {
            appendText()
        }

        return segments
    }
}
