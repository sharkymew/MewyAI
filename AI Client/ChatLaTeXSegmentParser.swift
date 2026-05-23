import Foundation

nonisolated enum ChatLaTeXSegment: Sendable, Equatable {
    case text(String)
    case math(formula: String, displayMode: Bool)
}

nonisolated enum ChatLaTeXSegmentParser {
    static func split(_ text: String) -> [ChatLaTeXSegment] {
        guard mayContainMath(in: text) else { return [.text(text)] }

        var segments: [ChatLaTeXSegment] = []
        var index = text.startIndex
        var textStart = text.startIndex

        func appendText(upTo end: String.Index) {
            guard textStart < end else { return }
            segments.append(.text(String(text[textStart..<end])))
        }

        func appendMath(from start: String.Index, to end: String.Index, formula: String, displayMode: Bool) {
            appendText(upTo: start)
            segments.append(.math(formula: formula, displayMode: displayMode))
            textStart = end
            index = end
        }

        while index < text.endIndex {
            if let codeEnd = inlineCodeEnd(in: text, from: index) {
                index = codeEnd
                continue
            }

            if let match = displayMathMatch(in: text, at: index) {
                appendMath(
                    from: index,
                    to: match.endIndex,
                    formula: match.formula,
                    displayMode: true
                )
                continue
            }

            index = text.index(after: index)
        }

        appendText(upTo: text.endIndex)
        return mergedTextSegments(segments)
    }

    static func containsInlineMath(in text: String) -> Bool {
        guard mayContainMath(in: text) else { return false }

        var index = text.startIndex
        while index < text.endIndex {
            if let codeEnd = inlineCodeEnd(in: text, from: index) {
                index = codeEnd
                continue
            }

            if let match = displayMathMatch(in: text, at: index) {
                index = match.endIndex
                continue
            }

            if inlineMathMatch(in: text, at: index) != nil {
                return true
            }

            index = text.index(after: index)
        }

        return false
    }

    private static func mayContainMath(in text: String) -> Bool {
        text.contains("$")
            || text.contains(#"\("#)
            || text.contains(#"\["#)
            || text.contains(#"\begin{"#)
    }

    private static func displayMathMatch(
        in text: String,
        at index: String.Index
    ) -> (formula: String, endIndex: String.Index)? {
        if hasPrefix("$$", in: text, at: index),
           !isEscaped(index, in: text),
           let closing = closingDelimiter("$$", in: text, from: text.index(index, offsetBy: 2)) {
            let formulaStart = text.index(index, offsetBy: 2)
            return (
                String(text[formulaStart..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                closing.upperBound
            )
        }

        if hasPrefix(#"\["#, in: text, at: index),
           !isEscaped(index, in: text),
           let closing = closingDelimiter(#"\]"#, in: text, from: text.index(index, offsetBy: 2)) {
            let formulaStart = text.index(index, offsetBy: 2)
            return (
                String(text[formulaStart..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                closing.upperBound
            )
        }

        if let environment = mathEnvironmentOpening(in: text, at: index),
           let closing = closingDelimiter(#"\end{\#(environment.name)}"#, in: text, from: environment.contentStart) {
            return (
                String(text[index..<closing.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                closing.upperBound
            )
        }

        return nil
    }

    private static func inlineMathMatch(
        in text: String,
        at index: String.Index
    ) -> (formula: String, endIndex: String.Index)? {
        if hasPrefix(#"\("#, in: text, at: index),
           !isEscaped(index, in: text),
           let closing = closingDelimiter(#"\)"#, in: text, from: text.index(index, offsetBy: 2)) {
            let formulaStart = text.index(index, offsetBy: 2)
            let formula = String(text[formulaStart..<closing.lowerBound])
            guard !formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (formula, closing.upperBound)
        }

        guard text[index] == "$",
              !hasPrefix("$$", in: text, at: index),
              isValidInlineDollarOpening(index, in: text),
              let closing = closingInlineDollar(in: text, from: text.index(after: index)) else {
            return nil
        }

        let formula = String(text[text.index(after: index)..<closing])
        guard !formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !containsUnescapedSingleDollar(formula),
              !formula.contains("\n") else {
            return nil
        }
        return (formula, text.index(after: closing))
    }

    private static func mathEnvironmentOpening(
        in text: String,
        at index: String.Index
    ) -> (name: String, contentStart: String.Index)? {
        let prefix = #"\begin{"#
        guard hasPrefix(prefix, in: text, at: index), !isEscaped(index, in: text) else { return nil }

        let nameStart = text.index(index, offsetBy: prefix.count)
        guard let nameEnd = text[nameStart...].firstIndex(of: "}") else { return nil }

        let name = String(text[nameStart..<nameEnd])
        guard displayMathEnvironments.contains(name) else { return nil }
        return (name, text.index(after: nameEnd))
    }

    private static func inlineCodeEnd(in text: String, from index: String.Index) -> String.Index? {
        guard text[index] == "`" else { return nil }

        let tickCount = runLength(of: "`", in: text, from: index)
        let delimiter = String(repeating: "`", count: tickCount)
        let searchStart = text.index(index, offsetBy: tickCount)
        guard let closing = text.range(of: delimiter, range: searchStart..<text.endIndex) else {
            return text.endIndex
        }
        return closing.upperBound
    }

    private static func closingDelimiter(
        _ delimiter: String,
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var searchStart = start
        while searchStart < text.endIndex,
              let range = text.range(of: delimiter, range: searchStart..<text.endIndex) {
            if !isEscaped(range.lowerBound, in: text) {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func closingInlineDollar(in text: String, from start: String.Index) -> String.Index? {
        var searchStart = start
        while searchStart < text.endIndex,
              let range = text.range(of: "$", range: searchStart..<text.endIndex) {
            let candidate = range.lowerBound
            if !isEscaped(candidate, in: text),
               !hasPrefix("$$", in: text, at: candidate),
               isValidInlineDollarClosing(candidate, in: text) {
                return candidate
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func isValidInlineDollarOpening(_ index: String.Index, in text: String) -> Bool {
        guard !isEscaped(index, in: text) else { return false }
        let next = text.index(after: index)
        guard next < text.endIndex else { return false }
        return !text[next].isWhitespace && text[next] != "$"
    }

    private static func isValidInlineDollarClosing(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return false }
        let previous = text.index(before: index)
        if text[previous].isWhitespace { return false }

        let next = text.index(after: index)
        if next < text.endIndex, text[next].isNumber {
            return false
        }
        return true
    }

    private static func containsUnescapedSingleDollar(_ text: String) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$",
               !isEscaped(index, in: text),
               !hasPrefix("$$", in: text, at: index) {
                return true
            }
            index = text.index(after: index)
        }
        return false
    }

    private static func hasPrefix(_ prefix: String, in text: String, at index: String.Index) -> Bool {
        text[index...].hasPrefix(prefix)
    }

    private static func runLength(of character: Character, in text: String, from index: String.Index) -> Int {
        var count = 0
        var cursor = index
        while cursor < text.endIndex, text[cursor] == character {
            count += 1
            cursor = text.index(after: cursor)
        }
        return count
    }

    private static func isEscaped(_ index: String.Index, in text: String) -> Bool {
        var slashCount = 0
        var cursor = index

        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }

        return slashCount % 2 == 1
    }

    private static func mergedTextSegments(_ segments: [ChatLaTeXSegment]) -> [ChatLaTeXSegment] {
        var merged: [ChatLaTeXSegment] = []

        for segment in segments {
            switch (merged.last, segment) {
            case let (.text(previous), .text(current)):
                merged.removeLast()
                merged.append(.text(previous + current))
            default:
                merged.append(segment)
            }
        }

        return merged
    }

    private static let displayMathEnvironments: Set<String> = [
        "equation",
        "equation*",
        "align",
        "align*",
        "aligned",
        "alignedat",
        "alignat",
        "alignat*",
        "gather",
        "gather*",
        "gathered",
        "multline",
        "multline*",
        "split",
        "cases",
        "matrix",
        "pmatrix",
        "bmatrix",
        "Bmatrix",
        "vmatrix",
        "Vmatrix",
        "smallmatrix",
        "array",
        "subarray",
        "CD"
    ]
}
