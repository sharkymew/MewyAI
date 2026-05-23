import SwiftUI
import UIKit

nonisolated struct MarkdownRenderStyle: @unchecked Sendable {
    let textColor: UIColor
    let baseFont: UIFont
    let textAlignment: NSTextAlignment
    let userInterfaceStyle: UIUserInterfaceStyle
    let displayScale: CGFloat
    let signature: String

    init(
        textColor: UIColor,
        baseFont: UIFont,
        textAlignment: NSTextAlignment,
        userInterfaceStyle: UIUserInterfaceStyle = .light,
        displayScale: CGFloat = 1
    ) {
        self.textColor = textColor
        self.baseFont = baseFont
        self.textAlignment = textAlignment
        self.userInterfaceStyle = userInterfaceStyle
        self.displayScale = displayScale
        signature = [
            baseFont.fontName,
            "\(Int(baseFont.pointSize * 10))",
            "\(textAlignment.rawValue)",
            "\(userInterfaceStyle.rawValue)",
            "\(Int(displayScale * 100))",
            Self.colorSignature(for: textColor, userInterfaceStyle: userInterfaceStyle)
        ].joined(separator: ":")
    }

    var resolvedTextColor: UIColor {
        textColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: userInterfaceStyle))
    }

    private static func colorSignature(
        for color: UIColor,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> String {
        let resolvedColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: userInterfaceStyle))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "\(type(of: color))"
        }

        return [
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255),
            Int(alpha * 255)
        ].map(String.init).joined(separator: ",")
    }
}

nonisolated struct PreparedMarkdownBlock: Identifiable, @unchecked Sendable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text(PreparedMarkdownLine)
        case quote(PreparedMarkdownQuote)
        case table(PreparedMarkdownTable)
        case divider
    }
}

nonisolated struct PreparedMarkdownLine: @unchecked Sendable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let textAlignment: NSTextAlignment
    let attributedText: NSAttributedString
}

nonisolated struct PreparedMarkdownQuote: @unchecked Sendable {
    let lines: [PreparedMarkdownQuoteLine]
}

nonisolated struct PreparedMarkdownQuoteLine: Identifiable, @unchecked Sendable {
    let id: Int
    let depth: Int
    let line: PreparedMarkdownLine
}

nonisolated struct PreparedMarkdownTable: @unchecked Sendable {
    let header: PreparedMarkdownTableRow
    let rows: [PreparedMarkdownTableRow]
    let columnWidths: [CGFloat]
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var columnCount: Int {
        columnWidths.count
    }

    func columnWidth(at index: Int) -> CGFloat {
        columnWidths.value(at: index)
    }
}

nonisolated struct PreparedMarkdownTableRow: Identifiable, @unchecked Sendable {
    let id: Int
    let cells: [PreparedMarkdownTableCell]
    let height: CGFloat
}

nonisolated struct PreparedMarkdownTableCell: Identifiable, @unchecked Sendable {
    let id: Int
    let attributedText: NSAttributedString
    let isHeader: Bool
}

nonisolated struct PreparedMarkdownBlockCache: @unchecked Sendable {
    fileprivate var blocksBySignature: [String: PreparedMarkdownBlock] = [:]
    fileprivate var textBlocksBySignature: [String: [PreparedMarkdownBlock]] = [:]

    nonisolated init() {}

    private static let maximumBlockEntryCount = 180
    private static let maximumTextEntryCount = 96
}

nonisolated struct PreparedMarkdownBlockRenderResult: @unchecked Sendable {
    let blocks: [PreparedMarkdownBlock]
    let cache: PreparedMarkdownBlockCache
}

enum PreparedMarkdownBlockRenderer {
    nonisolated static func renderBlocks(
        markdown: String,
        style: MarkdownRenderStyle
    ) async -> [PreparedMarkdownBlock] {
        await renderBlocks(markdown: markdown, style: style, cache: PreparedMarkdownBlockCache()).blocks
    }

    nonisolated static func renderBlocks(
        markdown: String,
        style: MarkdownRenderStyle,
        cache previousCache: PreparedMarkdownBlockCache
    ) async -> PreparedMarkdownBlockRenderResult {
        var preparedBlocks: [PreparedMarkdownBlock] = []
        var nextCache = PreparedMarkdownBlockCache()
        for block in MarkdownBlockParser.parse(markdown) {
            let signature = signature(for: block, style: style)
            if let cachedBlock = previousCache.blocksBySignature[signature] {
                let preparedBlock = PreparedMarkdownBlock(id: block.id, kind: cachedBlock.kind)
                preparedBlocks.append(preparedBlock)
                nextCache.store(preparedBlock, for: signature)
                continue
            }

            let preparedBlock: PreparedMarkdownBlock
            switch block.kind {
            case let .text(text, textStyle):
                preparedBlock = PreparedMarkdownBlock(
                    id: block.id,
                    kind: .text(await renderLine(text: text, textStyle: textStyle, renderStyle: style))
                )
            case let .quote(text):
                preparedBlock = PreparedMarkdownBlock(
                    id: block.id,
                    kind: .quote(await renderQuote(text, renderStyle: style))
                )
            case let .table(table):
                preparedBlock = PreparedMarkdownBlock(
                    id: block.id,
                    kind: .table(await renderTable(table, renderStyle: style))
                )
            case .divider:
                preparedBlock = PreparedMarkdownBlock(id: block.id, kind: .divider)
            }
            preparedBlocks.append(preparedBlock)
            nextCache.store(preparedBlock, for: signature)
        }

        return PreparedMarkdownBlockRenderResult(blocks: preparedBlocks, cache: nextCache)
    }

    private nonisolated static func signature(
        for block: MarkdownBlock,
        style: MarkdownRenderStyle
    ) -> String {
        switch block.kind {
        case let .text(text, textStyle):
            return [
                style.signature,
                "text",
                textStyle.signature,
                "\(text.count)",
                "\(text.hashValue)"
            ].joined(separator: ":")
        case let .quote(text):
            return [
                style.signature,
                "quote",
                "\(text.count)",
                "\(text.hashValue)"
            ].joined(separator: ":")
        case let .table(table):
            let value = table.signature
            return [
                style.signature,
                "table",
                "\(value.count)",
                "\(value.hashValue)"
            ].joined(separator: ":")
        case .divider:
            return [style.signature, "divider"].joined(separator: ":")
        }
    }

    private nonisolated static func renderLine(
        text: String,
        textStyle: MarkdownTextStyle,
        renderStyle: MarkdownRenderStyle
    ) async -> PreparedMarkdownLine {
        let font = textStyle.font(baseFont: renderStyle.baseFont)
        let lineStyle = MarkdownRenderStyle(
            textColor: renderStyle.textColor,
            baseFont: font,
            textAlignment: renderStyle.textAlignment,
            userInterfaceStyle: renderStyle.userInterfaceStyle,
            displayScale: renderStyle.displayScale
        )
        let attributedText: NSAttributedString
        if ChatLaTeXSegmentParser.containsInlineMath(in: text) {
            attributedText = await LaTeXInlineAttributedRenderer.attributedString(
                from: text,
                font: font,
                textColor: renderStyle.textColor,
                textAlignment: renderStyle.textAlignment,
                renderStyle: lineStyle
            )
        } else {
            attributedText = MarkdownInlineFormatter.attributedString(
                from: text,
                font: font,
                textColor: renderStyle.textColor,
                textAlignment: renderStyle.textAlignment
            )
        }

        return PreparedMarkdownLine(
            text: text,
            font: font,
            textColor: renderStyle.textColor,
            textAlignment: renderStyle.textAlignment,
            attributedText: attributedText
        )
    }

    private nonisolated static func renderQuote(
        _ text: String,
        renderStyle: MarkdownRenderStyle
    ) async -> PreparedMarkdownQuote {
        let quoteStyle = MarkdownRenderStyle(
            textColor: .secondaryLabel,
            baseFont: renderStyle.baseFont,
            textAlignment: renderStyle.textAlignment,
            userInterfaceStyle: renderStyle.userInterfaceStyle,
            displayScale: renderStyle.displayScale
        )
        var lines: [PreparedMarkdownQuoteLine] = []
        for (index, rawText) in text.components(separatedBy: .newlines).enumerated() {
            let parsedLine = quoteLine(from: rawText)
            lines.append(PreparedMarkdownQuoteLine(
                id: index,
                depth: parsedLine.depth,
                line: await renderLine(text: parsedLine.text, textStyle: .paragraph, renderStyle: quoteStyle)
            ))
        }
        return PreparedMarkdownQuote(lines: lines)
    }

    private nonisolated static func quoteLine(from rawText: String) -> (depth: Int, text: String) {
        var value = rawText.trimmingCharacters(in: .whitespaces)
        var level = 0
        while value.first == ">" {
            level += 1
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return (max(level, 1), value)
    }

    private nonisolated static func renderTable(
        _ table: MarkdownTable,
        renderStyle: MarkdownRenderStyle
    ) async -> PreparedMarkdownTable {
        let columnCount = table.columnCount
        let headerFont = UIFont.boldSystemFont(ofSize: renderStyle.baseFont.pointSize)
        let bodyFont = renderStyle.baseFont
        let headerCells = await renderTableCells(
            table.headers,
            columnCount: columnCount,
            font: headerFont,
            isHeader: true,
            renderStyle: renderStyle
        )
        var bodyCells: [[PreparedMarkdownTableCell]] = []
        for row in table.rows {
            bodyCells.append(await renderTableCells(
                row,
                columnCount: columnCount,
                font: bodyFont,
                isHeader: false,
                renderStyle: renderStyle
            ))
        }

        let columnWidths = (0..<columnCount).map { columnIndex in
            let headerWidth = measuredWidth(for: headerCells[columnIndex].attributedText)
            let rowWidth = bodyCells
                .map { measuredWidth(for: $0[columnIndex].attributedText) }
                .max() ?? TableMetrics.minimumColumnWidth
            return min(
                max(max(headerWidth, rowWidth), TableMetrics.minimumColumnWidth),
                TableMetrics.maximumColumnWidth
            )
        }

        let header = PreparedMarkdownTableRow(
            id: -1,
            cells: headerCells,
            height: rowHeight(for: headerCells, font: headerFont, columnWidths: columnWidths)
        )
        let rows = bodyCells.enumerated().map { rowIndex, cells in
            PreparedMarkdownTableRow(
                id: rowIndex,
                cells: cells,
                height: rowHeight(for: cells, font: bodyFont, columnWidths: columnWidths)
            )
        }

        return PreparedMarkdownTable(
            header: header,
            rows: rows,
            columnWidths: columnWidths,
            horizontalPadding: TableMetrics.horizontalPadding,
            verticalPadding: TableMetrics.verticalPadding
        )
    }

    private nonisolated static func renderTableCells(
        _ values: [String],
        columnCount: Int,
        font: UIFont,
        isHeader: Bool,
        renderStyle: MarkdownRenderStyle
    ) async -> [PreparedMarkdownTableCell] {
        let cellStyle = MarkdownRenderStyle(
            textColor: renderStyle.textColor,
            baseFont: font,
            textAlignment: .left,
            userInterfaceStyle: renderStyle.userInterfaceStyle,
            displayScale: renderStyle.displayScale
        )
        var cells: [PreparedMarkdownTableCell] = []
        for columnIndex in 0..<columnCount {
            let attributedText = await LaTeXInlineAttributedRenderer.attributedString(
                from: values.value(at: columnIndex),
                font: font,
                textColor: renderStyle.textColor,
                textAlignment: .left,
                renderStyle: cellStyle
            )
            cells.append(PreparedMarkdownTableCell(
                id: columnIndex,
                attributedText: attributedText,
                isHeader: isHeader
            ))
        }
        return cells
    }

    private nonisolated static func measuredWidth(for attributedText: NSAttributedString) -> CGFloat {
        let bounds = attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.width)
    }

    private nonisolated static func rowHeight(
        for cells: [PreparedMarkdownTableCell],
        font: UIFont,
        columnWidths: [CGFloat]
    ) -> CGFloat {
        let contentHeight = cells.enumerated()
            .map { columnIndex, cell in
                measuredHeight(
                    for: cell.attributedText,
                    width: columnWidths.value(at: columnIndex)
                )
            }
            .max() ?? font.lineHeight
        return ceil(max(contentHeight, font.lineHeight) + TableMetrics.verticalPadding * 2)
    }

    private nonisolated static func measuredHeight(
        for attributedText: NSAttributedString,
        width: CGFloat
    ) -> CGFloat {
        let bounds = attributedText.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }

    private nonisolated enum TableMetrics {
        static let minimumColumnWidth: CGFloat = 72
        static let maximumColumnWidth: CGFloat = 320
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 7
    }
}

nonisolated extension PreparedMarkdownBlockCache {
    func blocks(forTextSignature signature: String) -> [PreparedMarkdownBlock]? {
        textBlocksBySignature[signature]
    }

    fileprivate mutating func store(_ block: PreparedMarkdownBlock, for signature: String) {
        if blocksBySignature.count >= Self.maximumBlockEntryCount,
           let key = blocksBySignature.keys.first {
            blocksBySignature.removeValue(forKey: key)
        }
        blocksBySignature[signature] = block
    }

    mutating func store(_ blocks: [PreparedMarkdownBlock], forTextSignature signature: String) {
        if textBlocksBySignature.count >= Self.maximumTextEntryCount,
           let key = textBlocksBySignature.keys.first {
            textBlocksBySignature.removeValue(forKey: key)
        }
        textBlocksBySignature[signature] = blocks
    }

    mutating func merge(_ cache: PreparedMarkdownBlockCache) {
        for (signature, block) in cache.blocksBySignature {
            store(block, for: signature)
        }
        for (signature, blocks) in cache.textBlocksBySignature {
            store(blocks, forTextSignature: signature)
        }
    }
}

#if DEBUG
nonisolated extension PreparedMarkdownBlockCache {
    var diagnosticBlockEntryCount: Int {
        blocksBySignature.count
    }

    var diagnosticTextEntryCount: Int {
        textBlocksBySignature.count
    }
}
#endif

struct SelectableMarkdownTextView: View {
    let blocks: [PreparedMarkdownBlock]

    init(blocks: [PreparedMarkdownBlock]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: PreparedMarkdownBlock) -> some View {
        switch block.kind {
        case let .text(line):
            MarkdownSelectableLine(line: line)
        case .divider:
            Divider()
                .padding(.vertical, 8)
        case let .quote(quote):
            MarkdownQuoteView(quote: quote)
        case let .table(table):
            MarkdownTableView(table: table)
        }
    }
}

private struct MarkdownSelectableLine: View {
    let line: PreparedMarkdownLine

    var body: some View {
        if ChatLaTeXSegmentParser.containsInlineMath(in: line.text) {
            LaTeXInlineTextView(
                text: line.text,
                textColor: line.textColor,
                font: line.font,
                textAlignment: line.textAlignment
            )
        } else {
            SelectableAttributedTextView(
                attributedText: line.attributedText,
                textAlignment: line.textAlignment
            )
        }
    }
}

private struct MarkdownQuoteView: View {
    let quote: PreparedMarkdownQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(quote.lines) { line in
                HStack(alignment: .top, spacing: 7) {
                    ForEach(0..<line.depth, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 3)
                    }
                    MarkdownSelectableLine(line: line.line)
                }
            }
        }
    }
}

private struct MarkdownTableView: View {
    let table: PreparedMarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow(alignment: .top) {
                    ForEach(table.header.cells) { cell in
                        tableCell(
                            cell,
                            width: table.columnWidth(at: cell.id),
                            height: table.header.height
                        )
                    }
                }

                ForEach(table.rows) { row in
                    GridRow(alignment: .top) {
                        ForEach(row.cells) { cell in
                            tableCell(
                                cell,
                                width: table.columnWidth(at: cell.id),
                                height: row.height
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func tableCell(
        _ cell: PreparedMarkdownTableCell,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        MarkdownTableCell(
            cell: cell,
            width: width,
            height: height,
            horizontalPadding: table.horizontalPadding,
            verticalPadding: table.verticalPadding
        )
    }
}

private struct MarkdownTableCell: View {
    let cell: PreparedMarkdownTableCell
    let width: CGFloat
    let height: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        SelectableAttributedTextView(attributedText: cell.attributedText, textAlignment: .left)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(height: height, alignment: .topLeading)
            .background(cell.isHeader ? Color.secondary.opacity(0.10) : Color.clear)
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

private nonisolated enum MarkdownTextStyle {
    case paragraph
    case heading(Int)
    case list

    nonisolated var signature: String {
        switch self {
        case .paragraph:
            return "paragraph"
        case let .heading(level):
            return "heading:\(level)"
        case .list:
            return "list"
        }
    }

    nonisolated func font(baseFont: UIFont) -> UIFont {
        switch self {
        case .paragraph, .list:
            return baseFont
        case let .heading(level):
            let sizes: [CGFloat: CGFloat] = [1: 12, 2: 9, 3: 6, 4: 3, 5: 1, 6: 0]
            return .boldSystemFont(ofSize: baseFont.pointSize + (sizes[CGFloat(level)] ?? 0))
        }
    }
}

private nonisolated struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]

    nonisolated var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    nonisolated var signature: String {
        ([headers] + rows)
            .map { $0.joined(separator: "\u{1F}") }
            .joined(separator: "\u{1E}")
    }
}

private nonisolated enum MarkdownBlockParser {
    nonisolated static func parse(_ markdown: String) -> [MarkdownBlock] {
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

private nonisolated extension Array where Element == String {
    func value(at index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}

private nonisolated extension Array where Element == CGFloat {
    func value(at index: Int) -> CGFloat {
        indices.contains(index) ? self[index] : 0
    }
}
