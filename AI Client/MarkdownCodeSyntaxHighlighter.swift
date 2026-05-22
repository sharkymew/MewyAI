import SwiftUI
import MarkdownUI

struct ChatCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        guard code.count <= Self.maximumHighlightedCharacterCount else {
            return Text(code)
        }

        return ChatCodeLineHighlighter(language: language).highlight(code)
    }

    private static let maximumHighlightedCharacterCount = 20_000
}

extension CodeSyntaxHighlighter where Self == ChatCodeSyntaxHighlighter {
    static var chatCode: Self {
        ChatCodeSyntaxHighlighter()
    }
}

private struct ChatCodeLineHighlighter {
    private let rules: ChatCodeSyntaxRules

    init(language: String?) {
        rules = ChatCodeSyntaxRules(language: language)
    }

    func highlight(_ code: String) -> Text {
        let characters = Array(code)
        var index = 0
        var output = Text("")
        var plainBuffer = ""
        var segmentCount = 0

        func appendPlainBuffer() -> Bool {
            guard !plainBuffer.isEmpty else { return true }
            guard append(Text(plainBuffer)) else { return false }
            plainBuffer = ""
            return true
        }

        func append(_ text: Text) -> Bool {
            segmentCount += 1
            guard segmentCount <= Self.maximumHighlightedSegmentCount else { return false }
            output = output + text
            return true
        }

        while index < characters.count {
            if rules.supportsBlockComments, characters.matches("/*", at: index) {
                let range = blockCommentRange(in: characters, from: index)
                guard appendPlainBuffer(),
                      append(Text(String(characters[range])).foregroundColor(Self.commentColor)) else {
                    return Text(code)
                }
                index = range.upperBound
                continue
            }

            if rules.supportsPreprocessorDirectives,
               characters[index] == "#",
               isPreprocessorStart(in: characters, at: index) {
                let range = preprocessorDirectiveRange(in: characters, from: index)
                guard appendPlainBuffer(),
                      append(Text(String(characters[range])).foregroundColor(Self.keywordColor)) else {
                    return Text(code)
                }
                index = range.upperBound
                continue
            }

            if commentMarker(in: characters, at: index) != nil {
                let range = lineCommentRange(in: characters, from: index)
                guard appendPlainBuffer(),
                      append(Text(String(characters[range])).foregroundColor(Self.commentColor)) else {
                    return Text(code)
                }
                index = range.upperBound
                continue
            }

            let character = characters[index]

            if let delimiter = stringDelimiter(in: characters, at: index) {
                let range = stringRange(in: characters, from: index, delimiter: delimiter)
                guard appendPlainBuffer(),
                      append(Text(String(characters[range])).foregroundColor(Self.stringColor)) else {
                    return Text(code)
                }
                index = range.upperBound
                continue
            }

            if character.isNumber {
                let range = numberRange(in: characters, from: index)
                guard appendPlainBuffer(),
                      append(Text(String(characters[range])).foregroundColor(Self.numberColor)) else {
                    return Text(code)
                }
                index = range.upperBound
                continue
            }

            if isIdentifierStart(character) {
                let range = identifierRange(in: characters, from: index)
                let token = String(characters[range])
                let styledToken = styledIdentifier(token)
                if styledToken.isPlain {
                    plainBuffer += token
                } else {
                    guard appendPlainBuffer(), append(styledToken.text) else { return Text(code) }
                }
                index = range.upperBound
                continue
            }

            plainBuffer.append(character)
            index += 1
        }

        guard appendPlainBuffer() else { return Text(code) }
        return output
    }

    private func styledIdentifier(_ token: String) -> StyledText {
        if rules.keywords.contains(token) {
            return StyledText(text: Text(token).foregroundColor(Self.keywordColor), isPlain: false)
        }

        if ChatCodeSyntaxRules.literalKeywords.contains(token) || rules.builtins.contains(token) {
            return StyledText(text: Text(token).foregroundColor(Self.literalColor), isPlain: false)
        }

        return StyledText(text: Text(token), isPlain: true)
    }

    private func commentMarker(in characters: [Character], at index: Int) -> String? {
        rules.lineCommentMarkers.first { marker in
            characters.matches(marker, at: index)
        }
    }

    private func lineCommentRange(in characters: [Character], from start: Int) -> Range<Int> {
        var index = start
        while index < characters.count, characters[index] != "\n" {
            index += 1
        }
        return start..<index
    }

    private func blockCommentRange(in characters: [Character], from start: Int) -> Range<Int> {
        var index = start + 2
        while index < characters.count {
            if characters.matches("*/", at: index) {
                return start..<(index + 2)
            }
            index += 1
        }
        return start..<characters.count
    }

    private func isPreprocessorStart(in characters: [Character], at index: Int) -> Bool {
        var cursor = index - 1
        while cursor >= 0 {
            if characters[cursor] == "\n" {
                return true
            }
            if characters[cursor] != " " && characters[cursor] != "\t" {
                return false
            }
            cursor -= 1
        }
        return true
    }

    private func preprocessorDirectiveRange(in characters: [Character], from start: Int) -> Range<Int> {
        var index = start + 1
        while index < characters.count, isIdentifierStart(characters[index]) {
            index += 1
        }
        return start..<index
    }

    private func stringDelimiter(in characters: [Character], at index: Int) -> StringDelimiter? {
        if rules.supportsTripleQuotedStrings {
            for marker in ["\"\"\"", "'''"] where characters.matches(marker, at: index) {
                return StringDelimiter(marker: marker, allowsNewlines: true)
            }
        }
        if rules.supportsBacktickStrings, characters.matches("`", at: index) {
            return StringDelimiter(marker: "`", allowsNewlines: true)
        }
        let character = characters[index]
        if character == "\"" || character == "'" {
            return StringDelimiter(marker: String(character), allowsNewlines: false)
        }
        return nil
    }

    private func stringRange(in characters: [Character], from start: Int, delimiter: StringDelimiter) -> Range<Int> {
        var index = start + delimiter.marker.count
        var isEscaped = false

        while index < characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if characters.matches(delimiter.marker, at: index) {
                return start..<(index + delimiter.marker.count)
            } else if !delimiter.allowsNewlines, character == "\n" {
                return start..<index
            }

            index += 1
        }

        return start..<characters.count
    }

    private func numberRange(in characters: [Character], from start: Int) -> Range<Int> {
        var index = start + 1

        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "." || character == "_" || character.isHexLetter {
                index += 1
            } else {
                break
            }
        }

        return start..<index
    }

    private func identifierRange(in characters: [Character], from start: Int) -> Range<Int> {
        var index = start + 1

        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" {
                index += 1
            } else {
                break
            }
        }

        return start..<index
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static let keywordColor = Color(red: 0.58, green: 0.25, blue: 0.78)
    private static let literalColor = Color(red: 0.10, green: 0.42, blue: 0.86)
    private static let stringColor = Color(red: 0.05, green: 0.48, blue: 0.30)
    private static let numberColor = Color(red: 0.78, green: 0.33, blue: 0.12)
    private static let commentColor = Color.secondary
    private static let maximumHighlightedSegmentCount = 900

    private struct StringDelimiter {
        let marker: String
        let allowsNewlines: Bool
    }

    private struct StyledText {
        let text: Text
        let isPlain: Bool
    }
}

private extension Array where Element == Character {
    func matches(_ marker: String, at index: Int) -> Bool {
        let markerCharacters = Array(marker)
        guard index + markerCharacters.count <= count else { return false }
        return Array(self[index..<(index + markerCharacters.count)]) == markerCharacters
    }
}

private extension Character {
    var isHexLetter: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return false }
        return (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
    }
}
