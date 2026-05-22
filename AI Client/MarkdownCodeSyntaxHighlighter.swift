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
    private let language: String
    private let keywords: Set<String>
    private let lineCommentMarkers: [String]

    init(language: String?) {
        let normalized = language?
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first
            .map(String.init) ?? ""

        self.language = normalized
        self.keywords = Self.keywords(for: normalized)
        self.lineCommentMarkers = Self.lineCommentMarkers(for: normalized)
    }

    func highlight(_ code: String) -> Text {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output = Text("")

        for (index, line) in lines.enumerated() {
            output = output + highlightLine(line)
            if index < lines.count - 1 {
                output = output + Text("\n")
            }
        }

        return output
    }

    private func highlightLine(_ line: String) -> Text {
        let characters = Array(line)
        var index = 0
        var output = Text("")

        while index < characters.count {
            if commentMarker(in: characters, at: index) != nil {
                let comment = String(characters[index...])
                return output + Text(comment).foregroundColor(Self.commentColor)
            }

            let character = characters[index]

            if isStringDelimiter(character) {
                let range = stringRange(in: characters, from: index, delimiter: character)
                output = output + Text(String(characters[range])).foregroundColor(Self.stringColor)
                index = range.upperBound
                continue
            }

            if character.isNumber {
                let range = numberRange(in: characters, from: index)
                output = output + Text(String(characters[range])).foregroundColor(Self.numberColor)
                index = range.upperBound
                continue
            }

            if isIdentifierStart(character) {
                let range = identifierRange(in: characters, from: index)
                let token = String(characters[range])
                output = output + styledIdentifier(token)
                index = range.upperBound
                continue
            }

            output = output + Text(String(character))
            index += 1
        }

        return output
    }

    private func styledIdentifier(_ token: String) -> Text {
        if keywords.contains(token) {
            return Text(token).foregroundColor(Self.keywordColor)
        }

        if Self.literalKeywords.contains(token) {
            return Text(token).foregroundColor(Self.literalColor)
        }

        return Text(token)
    }

    private func commentMarker(in characters: [Character], at index: Int) -> String? {
        lineCommentMarkers.first { marker in
            characters.matches(marker, at: index)
        }
    }

    private func stringRange(in characters: [Character], from start: Int, delimiter: Character) -> Range<Int> {
        var index = start + 1
        var isEscaped = false

        while index < characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == delimiter {
                return start..<(index + 1)
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

    private func isStringDelimiter(_ character: Character) -> Bool {
        if character == "\"" || character == "'" {
            return true
        }

        return language == "javascript" || language == "js" || language == "typescript" || language == "ts"
            ? character == "`"
            : false
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func lineCommentMarkers(for language: String) -> [String] {
        switch language {
        case "python", "py", "ruby", "rb", "shell", "sh", "bash", "zsh", "yaml", "yml", "toml":
            return ["#"]
        case "sql":
            return ["--"]
        default:
            return ["//", "#"]
        }
    }

    private static func keywords(for language: String) -> Set<String> {
        switch language {
        case "swift":
            return swiftKeywords
        case "python", "py":
            return pythonKeywords
        case "javascript", "js", "typescript", "ts", "tsx", "jsx":
            return javaScriptKeywords
        case "json":
            return []
        default:
            return sharedKeywords
        }
    }

    private static let keywordColor = Color(red: 0.58, green: 0.25, blue: 0.78)
    private static let literalColor = Color(red: 0.10, green: 0.42, blue: 0.86)
    private static let stringColor = Color(red: 0.05, green: 0.48, blue: 0.30)
    private static let numberColor = Color(red: 0.78, green: 0.33, blue: 0.12)
    private static let commentColor = Color.secondary

    private static let literalKeywords: Set<String> = [
        "true", "false", "nil", "null", "none", "None", "True", "False", "undefined"
    ]

    private static let sharedKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "defer", "do", "else", "enum", "extension", "final", "for", "func",
        "function", "guard", "if", "import", "in", "let", "private", "public", "return",
        "static", "struct", "switch", "throw", "throws", "try", "var", "while"
    ]

    private static let swiftKeywords: Set<String> = sharedKeywords.union([
        "actor", "associatedtype", "convenience", "didSet", "dynamic", "get", "inout",
        "internal", "isolated", "mutating", "nonisolated", "open", "override", "protocol",
        "required", "self", "Self", "set", "some", "super", "typealias", "where", "willSet"
    ])

    private static let pythonKeywords: Set<String> = sharedKeywords.union([
        "and", "assert", "def", "del", "elif", "except", "finally", "from", "global",
        "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "with", "yield"
    ])

    private static let javaScriptKeywords: Set<String> = sharedKeywords.union([
        "abstract", "any", "boolean", "constructor", "debugger", "declare", "export",
        "extends", "implements", "interface", "namespace", "new", "of", "readonly",
        "require", "string", "symbol", "this", "type", "typeof", "void"
    ])
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
