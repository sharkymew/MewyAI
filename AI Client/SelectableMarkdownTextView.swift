import SwiftUI
import UIKit

struct SelectableMarkdownTextView: View {
    let markdown: String
    var textColor: UIColor = .label
    var baseFont: UIFont = .preferredFont(forTextStyle: .body)
    var textAlignment: NSTextAlignment = .left

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .text(text, style):
            MarkdownSelectableLine(
                text: text,
                style: style,
                textColor: textColor,
                baseFont: baseFont,
                textAlignment: textAlignment
            )
        case .divider:
            Divider()
                .padding(.vertical, 8)
        case let .quote(text):
            MarkdownQuoteView(
                text: text,
                textColor: .secondaryLabel,
                baseFont: baseFont,
                textAlignment: textAlignment
            )
        case let .table(table):
            MarkdownTableView(table: table, textColor: textColor, baseFont: baseFont)
        }
    }
}

private struct MarkdownSelectableLine: View {
    let text: String
    let style: MarkdownTextStyle
    let textColor: UIColor
    let baseFont: UIFont
    let textAlignment: NSTextAlignment

    var body: some View {
        let font = style.font(baseFont: baseFont)

        if ChatLaTeXSegmentParser.containsInlineMath(in: text) {
            LaTeXInlineTextView(
                text: text,
                textColor: textColor,
                font: font,
                textAlignment: textAlignment
            )
        } else {
            SelectableAttributedTextView(
                attributedText: MarkdownInlineFormatter.attributedString(
                    from: text,
                    font: font,
                    textColor: textColor,
                    textAlignment: textAlignment
                ),
                textAlignment: textAlignment
            )
        }
    }
}

private struct MarkdownQuoteView: View {
    let text: String
    let textColor: UIColor
    let baseFont: UIFont
    let textAlignment: NSTextAlignment

    private var lines: [MarkdownQuoteLine] {
        text.components(separatedBy: .newlines).enumerated().map { index, line in
            MarkdownQuoteLine(id: index, rawText: line)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 7) {
                    ForEach(0..<line.depth, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 3)
                    }
                    MarkdownSelectableLine(
                        text: line.text,
                        style: .paragraph,
                        textColor: textColor,
                        baseFont: baseFont,
                        textAlignment: textAlignment
                    )
                }
            }
        }
    }
}

private struct MarkdownQuoteLine: Identifiable {
    let id: Int
    let depth: Int
    let text: String

    init(id: Int, rawText: String) {
        self.id = id
        var value = rawText.trimmingCharacters(in: .whitespaces)
        var level = 0
        while value.first == ">" {
            level += 1
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        depth = max(level, 1)
        text = value
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let textColor: UIColor
    let baseFont: UIFont

    private let minimumColumnWidth: CGFloat = 72
    private let maximumColumnWidth: CGFloat = 320
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 7

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow(alignment: .top) {
                    ForEach(0..<table.columnCount, id: \.self) { index in
                        cell(
                            table.headers.value(at: index),
                            isHeader: true,
                            width: columnWidth(at: index),
                            height: headerRowHeight()
                        )
                    }
                }

                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    GridRow(alignment: .top) {
                        ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                            cell(
                                table.rows[rowIndex].value(at: columnIndex),
                                isHeader: false,
                                width: columnWidth(at: columnIndex),
                                height: rowHeight(at: rowIndex)
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func cell(_ text: String, isHeader: Bool, width: CGFloat, height: CGFloat) -> some View {
        MarkdownTableCell(
            text: text,
            textColor: textColor,
            font: font(isHeader: isHeader),
            width: width,
            height: height,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            isHeader: isHeader
        )
    }

    private func columnWidth(at index: Int) -> CGFloat {
        let headerWidth = measuredWidth(for: table.headers.value(at: index), font: font(isHeader: true))
        let rowWidth = table.rows
            .map { measuredWidth(for: $0.value(at: index), font: font(isHeader: false)) }
            .max() ?? minimumColumnWidth
        return min(max(max(headerWidth, rowWidth), minimumColumnWidth), maximumColumnWidth)
    }

    private func measuredWidth(for markdown: String, font: UIFont) -> CGFloat {
        let attributedText = MarkdownInlineFormatter.attributedString(
            from: markdown,
            font: font,
            textColor: textColor,
            textAlignment: .left
        )
        let bounds = attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.width)
    }

    private func headerRowHeight() -> CGFloat {
        rowHeight(for: table.headers, isHeader: true)
    }

    private func rowHeight(at index: Int) -> CGFloat {
        rowHeight(for: table.rows[index], isHeader: false)
    }

    private func rowHeight(for cells: [String], isHeader: Bool) -> CGFloat {
        let font = font(isHeader: isHeader)
        let contentHeight = (0..<table.columnCount)
            .map { columnIndex in
                measuredHeight(
                    for: cells.value(at: columnIndex),
                    font: font,
                    width: columnWidth(at: columnIndex)
                )
            }
            .max() ?? font.lineHeight
        return ceil(max(contentHeight, font.lineHeight) + verticalPadding * 2)
    }

    private func measuredHeight(for markdown: String, font: UIFont, width: CGFloat) -> CGFloat {
        let attributedText = MarkdownInlineFormatter.attributedString(
            from: markdown.isEmpty ? " " : markdown,
            font: font,
            textColor: textColor,
            textAlignment: .left
        )
        let bounds = attributedText.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }

    private func font(isHeader: Bool) -> UIFont {
        isHeader ? .boldSystemFont(ofSize: baseFont.pointSize) : baseFont
    }
}

private struct MarkdownTableCell: View {
    let text: String
    let textColor: UIColor
    let font: UIFont
    let width: CGFloat
    let height: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let isHeader: Bool

    private var attributedText: NSAttributedString {
        MarkdownInlineFormatter.attributedString(
            from: text,
            font: font,
            textColor: textColor,
            textAlignment: .left
        )
    }

    var body: some View {
        SelectableAttributedTextView(attributedText: attributedText, textAlignment: .left)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(height: height, alignment: .topLeading)
            .background(isHeader ? Color.secondary.opacity(0.10) : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text(String, MarkdownTextStyle)
        case quote(String)
        case table(MarkdownTable)
        case divider
    }
}

private enum MarkdownTextStyle {
    case paragraph
    case heading(Int)
    case list

    func font(baseFont: UIFont) -> UIFont {
        switch self {
        case .paragraph, .list:
            return baseFont
        case let .heading(level):
            let sizes: [CGFloat: CGFloat] = [1: 12, 2: 9, 3: 6, 4: 3, 5: 1, 6: 0]
            return .boldSystemFont(ofSize: baseFont.pointSize + (sizes[CGFloat(level)] ?? 0))
        }
    }
}

private struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            } else if let table = table(from: lines, at: index) {
                blocks.append(.init(id: blocks.count, kind: .table(table.value)))
                index = table.nextIndex
            } else if isDivider(lines[index]) {
                blocks.append(.init(id: blocks.count, kind: .divider))
                index += 1
            } else if let heading = heading(from: lines[index]) {
                blocks.append(.init(id: blocks.count, kind: .text(heading.text, .heading(heading.level))))
                index += 1
            } else if isQuote(lines[index]) {
                let result = collect(lines: lines, from: index, while: isQuote(_:))
                blocks.append(.init(id: blocks.count, kind: .quote(result.text)))
                index = result.nextIndex
            } else if let list = listLine(from: lines[index]) {
                blocks.append(.init(id: blocks.count, kind: .text(list, .list)))
                index += 1
            } else {
                let result = collectParagraph(lines: lines, from: index)
                blocks.append(.init(id: blocks.count, kind: .text(result.text, .paragraph)))
                index = result.nextIndex
            }
        }

        return blocks
    }

    private static func collectParagraph(lines: [String], from start: Int) -> (text: String, nextIndex: Int) {
        var index = start
        var result: [String] = []

        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  table(from: lines, at: index) == nil,
                  !isDivider(line),
                  heading(from: line) == nil,
                  !isQuote(line),
                  listLine(from: line) == nil else {
                break
            }
            result.append(line)
            index += 1
        }

        return (result.joined(separator: "\n"), index)
    }

    private static func collect(
        lines: [String],
        from start: Int,
        while shouldInclude: (String) -> Bool
    ) -> (text: String, nextIndex: Int) {
        var index = start
        var result: [String] = []
        while index < lines.count, shouldInclude(lines[index]) {
            result.append(lines[index])
            index += 1
        }
        return (result.joined(separator: "\n"), index)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else { return nil }
        return (level, String(trimmed.dropFirst(level + 1)))
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" }
            || trimmed.allSatisfy { $0 == "*" }
            || trimmed.allSatisfy { $0 == "_" }
    }

    private nonisolated static func isQuote(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func listLine(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil {
            let checked = trimmed.contains("[x]") || trimmed.contains("[X]")
            return "\(checked ? "☑" : "☐") " + String(trimmed.dropFirst(6))
        }
        if trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
            return "• " + String(trimmed.dropFirst(2))
        }
        if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            return String(trimmed[range]) + String(trimmed[range.upperBound...])
        }
        return nil
    }

    private static func table(from lines: [String], at index: Int) -> (value: MarkdownTable, nextIndex: Int)? {
        guard index + 1 < lines.count, isTableSeparator(lines[index + 1]) else { return nil }
        let headers = cells(in: lines[index])
        guard headers.count >= 2 else { return nil }

        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count, lines[cursor].contains("|") {
            let row = cells(in: lines[cursor])
            if !row.isEmpty { rows.append(row) }
            cursor += 1
        }

        return (MarkdownTable(headers: headers, rows: rows), cursor)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let parts = cells(in: line)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private extension Array where Element == String {
    func value(at index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}
