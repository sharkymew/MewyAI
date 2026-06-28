import Foundation
import SwiftUI

struct ChatMarkdownCodeFence {
    let marker: Character
    let length: Int
    let language: String?

    nonisolated static func opening(in line: String) -> ChatMarkdownCodeFence? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first, marker == "`" || marker == "~" else { return nil }

        let length = trimmedLine.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }

        let language = trimmedLine
            .dropFirst(length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)

        return ChatMarkdownCodeFence(marker: marker, length: length, language: language)
    }

    nonisolated func isClosing(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let closingLength = trimmedLine.prefix { $0 == marker }.count
        guard closingLength >= length else { return false }
        return trimmedLine.dropFirst(closingLength).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
