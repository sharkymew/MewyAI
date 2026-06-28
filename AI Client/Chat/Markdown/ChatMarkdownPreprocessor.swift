import Foundation
import SwiftUI

enum ChatMarkdownPreprocessor {
    nonisolated static func preprocess(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = splitByCodeFence(normalized)
        return segments
            .map { segment in
                segment.isCode ? segment.text : preprocessMarkdownText(segment.text)
            }
            .joined()
    }

    private nonisolated static func preprocessMarkdownText(_ text: String) -> String {
        var processed = text
        processed = stripLaTeXDocumentShell(from: processed)
        processed = removeHTMLComments(from: processed)
        processed = removeTOCLines(from: processed)
        processed = transformCustomContainers(in: processed)
        processed = normalizeTables(in: processed)
        processed = transformInlineExtensions(in: processed)
        processed = stripAttributeLists(from: processed)
        processed = appendFootnotes(in: processed)
        return processed
    }

    private nonisolated static func splitByCodeFence(_ content: String) -> [(text: String, isCode: Bool)] {
        let lines = content.components(separatedBy: "\n")
        var segments: [(text: String, isCode: Bool)] = []
        var buffer: [String] = []
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendBuffer(isCode: Bool, appendsTrailingNewline: Bool) {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: "\n") + (appendsTrailingNewline ? "\n" : "")
            segments.append((text, isCode))
            buffer = []
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                buffer.append(line)
                if codeFence.isClosing(line) {
                    appendBuffer(isCode: true, appendsTrailingNewline: true)
                    activeCodeFence = nil
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendBuffer(isCode: false, appendsTrailingNewline: true)
                activeCodeFence = codeFence
                buffer.append(line)
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            segments.append((buffer.joined(separator: "\n"), activeCodeFence != nil))
        }
        return segments
    }

    private nonisolated static func stripLaTeXDocumentShell(from text: String) -> String {
        var result = text

        if let beginRange = result.range(
            of: #"\\begin\{document\}"#,
            options: .regularExpression
        ) {
            let bodyStart = beginRange.upperBound
            if let endRange = result.range(
                of: #"\\end\{document\}"#,
                options: .regularExpression,
                range: bodyStart..<result.endIndex
            ) {
                result = String(result[bodyStart..<endRange.lowerBound])
            } else {
                result = String(result[bodyStart...])
            }
        }

        result = result.replacingOccurrences(
            of: #"(?m)^\s*\\(?:documentclass|usepackage)\b(?:\[[^\]]*\])?\{[^}]*\}\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?m)^\s*\\(?:begin|end)\{document\}\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func removeHTMLComments(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func removeTOCLines(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?mi)^\s*\[(?:toc|TOC)\]\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func transformCustomContainers(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var containerTitle: String?
        var containerLines: [String] = []

        func flushContainer() {
            guard let containerTitle else { return }
            result.append("> **\(containerTitle)**")
            result.append(contentsOf: containerLines.map { $0.isEmpty ? ">" : "> \($0)" })
            containerLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":::") {
                if containerTitle == nil {
                    let rawTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    containerTitle = rawTitle.isEmpty
                        ? AppLocalizations.string("markdown.container.defaultTitle", defaultValue: "Note")
                        : rawTitle
                    containerLines = []
                } else {
                    flushContainer()
                    containerTitle = nil
                }
                continue
            }

            if containerTitle != nil {
                containerLines.append(line)
            } else {
                result.append(line)
            }
        }

        flushContainer()
        return result.joined(separator: "\n")
    }

    private nonisolated static func normalizeTables(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if isTableHeader(lines: lines, at: index) {
                if let previous = result.last, !previous.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }

                var tableLines: [String] = []
                let columnCount = tableCellCount(in: lines[index])
                while index < lines.count, looksLikeTableLine(lines[index]) {
                    tableLines.append(normalizedTableLine(lines[index], columnCount: columnCount))
                    index += 1
                }
                result.append(contentsOf: tableLines)

                if index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }
                continue
            }

            result.append(lines[index])
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private nonisolated static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count,
              looksLikeTableLine(lines[index]) else {
            return false
        }
        return isTableSeparatorLine(lines[index + 1])
    }

    private nonisolated static func looksLikeTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") || trimmed.contains("｜")
    }

    private nonisolated static func normalizedTableLine(_ line: String) -> String {
        normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func normalizedTableLine(_ line: String, columnCount: Int) -> String {
        let cells = normalizedTableCells(in: line)
        guard !cells.isEmpty else { return normalizedTableLine(line) }

        let normalizedCells: [String]
        if isTableSeparatorLine(line) {
            normalizedCells = normalizedSeparatorCells(from: cells, columnCount: columnCount)
        } else {
            normalizedCells = normalizedDataCells(from: cells, columnCount: columnCount)
        }

        return "| " + normalizedCells.joined(separator: " | ") + " |"
    }

    private nonisolated static func normalizedTableText(_ line: String) -> String {
        line
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    private nonisolated static func normalizedTableCells(in line: String) -> [String] {
        let normalized = normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))

        return normalized
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private nonisolated static func tableCellCount(in line: String) -> Int {
        max(normalizedTableCells(in: line).count, 1)
    }

    private nonisolated static func normalizedDataCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount))
        while normalizedCells.count < columnCount {
            normalizedCells.append("")
        }
        return normalizedCells
    }

    private nonisolated static func normalizedSeparatorCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount)).map { cell in
            let compact = cell.filter { !$0.isWhitespace }
            let leftAligned = compact.hasPrefix(":")
            let rightAligned = compact.hasSuffix(":")
            let marker = String(repeating: "-", count: max(3, compact.filter { $0 == "-" }.count))

            switch (leftAligned, rightAligned) {
            case (true, true):
                return ":" + marker + ":"
            case (true, false):
                return ":" + marker
            case (false, true):
                return marker + ":"
            case (false, false):
                return marker
            }
        }

        while normalizedCells.count < columnCount {
            normalizedCells.append("---")
        }
        return normalizedCells
    }

    private nonisolated static func isTableSeparatorLine(_ line: String) -> Bool {
        let cells = normalizedTableCells(in: line)

        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.filter { !$0.isWhitespace }
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private nonisolated static func transformInlineExtensions(in text: String) -> String {
        var processed = text
        processed = processed.replacingOccurrences(
            of: #"==([^=\n]+)=="#,
            with: "**$1**",
            options: .regularExpression
        )
        processed = processed.replacingOccurrences(
            of: #"<u>(.*?)</u>"#,
            with: "_$1_",
            options: [.regularExpression, .caseInsensitive]
        )
        return processed
    }

    private nonisolated static func stripAttributeLists(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+\{[#.][^}\n]*\}"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func appendFootnotes(in text: String) -> String {
        var footnotes: [(id: String, body: String)] = []
        var bodyLines: [String] = []
        let pattern = #"^\[\^([^\]]+)\]:\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        for line in text.components(separatedBy: "\n") {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
                  match.numberOfRanges == 3,
                  let idRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line) else {
                bodyLines.append(line)
                continue
            }

            footnotes.append((String(line[idRange]), String(line[bodyRange])))
        }

        guard !footnotes.isEmpty else { return text }
        let renderedFootnotes = footnotes.map { "[^\($0.id)]: \($0.body)" }.joined(separator: "\n")
        return bodyLines.joined(separator: "\n") + "\n\n---\n\n" + renderedFootnotes
    }
}
