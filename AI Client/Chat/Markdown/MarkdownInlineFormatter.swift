import UIKit

nonisolated enum MarkdownInlineFormatter {
    static func attributedString(
        from markdown: String,
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment
    ) -> NSAttributedString {
        let source = normalizeHTML(markdown)
        let text = NSMutableAttributedString(
            string: source,
            attributes: baseAttributes(font: font, textColor: textColor, textAlignment: textAlignment)
        )

        replaceAutolink(in: text)
        applyHTMLStyles(to: text, baseFont: font)
        replaceLink(in: text)
        replaceInlineCode(in: text, baseFont: font)
        replaceStyle(pattern: #"(?<!\\)\*\*\*(.+?)(?<!\\)\*\*\*"#, in: text, attributes: boldItalic(font))
        replaceStyle(pattern: #"(?<!\\)___(.+?)(?<!\\)___"#, in: text, attributes: boldItalic(font))
        replaceStyle(pattern: #"(?<!\\)\*\*(.+?)(?<!\\)\*\*"#, in: text, attributes: [.font: bold(font)])
        replaceStyle(pattern: #"(?<!\\)__(.+?)(?<!\\)__"#, in: text, attributes: [.font: bold(font)])
        replaceStyle(pattern: #"(?<!\\)\*(.+?)(?<!\\)\*"#, in: text, attributes: italicAttributes(font))
        replaceStyle(pattern: #"(?<!\\)_(.+?)(?<!\\)_"#, in: text, attributes: italicAttributes(font))
        replaceStyle(pattern: #"(?<!\\)~~(.+?)(?<!\\)~~"#, in: text, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        replaceStyle(pattern: #"(?<!\\)==(.+?)(?<!\\)=="#, in: text, attributes: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.45)])
        replaceStyle(pattern: #"(?<![~\\])~([^~\n]+)~(?!~)"#, in: text, attributes: [.baselineOffset: -3, .font: font.withSize(font.pointSize * 0.82)])
        replaceStyle(pattern: #"(?<![\^\\])\^([^\^\n]+)\^(?!\^)"#, in: text, attributes: [.baselineOffset: 5, .font: font.withSize(font.pointSize * 0.78)])
        replaceStyle(pattern: #"\[\^([^\]]+)\]"#, in: text, attributes: [.baselineOffset: 5, .font: font.withSize(font.pointSize * 0.78)])
        unescapeMarkdown(in: text)
        return text
    }

    private static func baseAttributes(
        font: UIFont,
        textColor: UIColor,
        textAlignment: NSTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineSpacing = 3
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    private static func normalizeHTML(_ text: String) -> String {
        var result = text
        result = replace(pattern: #"<br\s*/?>"#, in: result, template: "\n")
        result = replace(pattern: #"</p>"#, in: result, template: "\n")
        return result
    }

    private static func applyHTMLStyles(to text: NSMutableAttributedString, baseFont: UIFont) {
        replaceStyle(pattern: #"<kbd>(.*?)</kbd>"#, in: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
            .backgroundColor: UIColor.secondarySystemFill
        ])
        replaceStyle(pattern: #"<[^>]+>(.*?)</[^>]+>"#, in: text, attributes: [:])
        replaceWhole(pattern: #"</?[^>]+>"#, in: text, replacement: "")
    }

    private static func replaceLink(in text: NSMutableAttributedString) {
        replaceMatches(pattern: #"(?<!\\)\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#, in: text) { groups in
            let label = groups.value(at: 1)
            let url = groups.value(at: 2)
            return (label, linkAttributes(for: url))
        }
    }

    private static func replaceAutolink(in text: NSMutableAttributedString) {
        replaceMatches(pattern: #"(?<!\\)<(https?://[^>]+)>"#, in: text) { groups in
            let url = groups.value(at: 1)
            return (url, linkAttributes(for: url))
        }
    }

    private static func replaceInlineCode(in text: NSMutableAttributedString, baseFont: UIFont) {
        replaceStyle(pattern: #"(?<!\\)`([^`\n]+)(?<!\\)`"#, in: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
            .backgroundColor: UIColor.secondarySystemFill
        ])
    }

    private static func replaceStyle(
        pattern: String,
        in text: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        replaceMatches(pattern: pattern, in: text) { groups in
            (groups.value(at: 1), attributes)
        }
    }

    private static func replaceMatches(
        pattern: String,
        in text: NSMutableAttributedString,
        transform: ([String?]) -> (String, [NSAttributedString.Key: Any])
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
        let source = text.string
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range).reversed() {
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                guard let range = Range(match.range(at: index), in: source) else { return nil }
                return String(source[range])
            }
            let replacement = transform(groups)
            text.replaceCharacters(in: match.range(at: 0), with: replacement.0)
            text.addAttributes(replacement.1, range: NSRange(location: match.range.location, length: (replacement.0 as NSString).length))
        }
    }

    private static func replaceWhole(pattern: String, in text: NSMutableAttributedString, replacement: String) {
        replaceMatches(pattern: pattern, in: text) { _ in (replacement, [:]) }
    }

    private static func replace(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func unescapeMarkdown(in text: NSMutableAttributedString) {
        replaceMatches(pattern: #"\\([\\`*_{}\[\]()#+\-.!~|<>])"#, in: text) { groups in
            (groups.value(at: 1), [:])
        }
    }

    private static func linkAttributes(for rawURL: String) -> [NSAttributedString.Key: Any] {
        guard isSafeLink(rawURL) else { return [:] }
        return [
            .link: rawURL,
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func isSafeLink(_ rawURL: String) -> Bool {
        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme),
              components.user == nil,
              components.password == nil else {
            return false
        }
        return true
    }

    private static func bold(_ font: UIFont) -> UIFont {
        .boldSystemFont(ofSize: font.pointSize)
    }

    private static func italic(_ font: UIFont) -> UIFont {
        .italicSystemFont(ofSize: font.pointSize)
    }

    private static func boldItalic(_ font: UIFont) -> [NSAttributedString.Key: Any] {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withSymbolicTraits([.traitBold, .traitItalic]) ?? font.fontDescriptor
        return [.font: UIFont(descriptor: descriptor, size: font.pointSize), .obliqueness: 0.16]
    }

    private static func italicAttributes(_ font: UIFont) -> [NSAttributedString.Key: Any] {
        [.font: italic(font), .obliqueness: 0.16]
    }
}

private nonisolated extension Array where Element == String? {
    func value(at index: Int) -> String {
        guard indices.contains(index), let value = self[index] else { return "" }
        return value
    }
}
