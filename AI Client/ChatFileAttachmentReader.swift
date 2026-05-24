import Foundation
import PDFKit
import UniformTypeIdentifiers

enum ChatFileAttachmentReadError: LocalizedError {
    case fileTooLarge(String, Int)
    case unsupported(String)
    case empty(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let name, let maxMegabytes):
            return "\(name) 超过 \(maxMegabytes)MB，已跳过。"
        case .unsupported(let name):
            return "\(name) 不是可读取的文本或 PDF 文件。"
        case .empty(let name):
            return "\(name) 没有提取到可用文本。"
        case .unreadable(let name):
            return "\(name) 读取失败。"
        }
    }
}

enum ChatFileAttachmentReader {
    static let maxFileByteCount = 8 * 1024 * 1024
    static let maxCharactersPerFile = 24_000

    static let supportedDocumentTypes: [UTType] = [
        .pdf,
        .plainText,
        .text,
        .sourceCode,
        .json,
        .xml,
        .html,
        .rtf,
        .commaSeparatedText
    ]

    static let dropTypeIdentifiers: [String] = {
        var identifiers = supportedDocumentTypes.map(\.identifier)
        identifiers.insert(UTType.fileURL.identifier, at: 0)
        return identifiers
    }()

    static func attachment(from url: URL) throws -> ChatFileAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey, .localizedNameKey])
        let name = resourceValues?.localizedName ?? url.lastPathComponent
        let byteCount = resourceValues?.fileSize ?? ((try? Data(contentsOf: url).count) ?? 0)
        let maxMegabytes = maxFileByteCount / 1024 / 1024

        guard byteCount <= maxFileByteCount else {
            throw ChatFileAttachmentReadError.fileTooLarge(name, maxMegabytes)
        }

        let typeIdentifier = resourceValues?.typeIdentifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
        let type = typeIdentifier.flatMap(UTType.init)
        let rawText: String

        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            rawText = try pdfText(from: url, name: name)
        } else {
            rawText = try plainText(from: url, name: name, type: type)
        }

        let normalizedText = rawText
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            throw ChatFileAttachmentReadError.empty(name)
        }

        let limitedText = String(normalizedText.prefix(maxCharactersPerFile))
        return ChatFileAttachment(
            name: name,
            typeIdentifier: typeIdentifier,
            byteCount: byteCount,
            characterCount: normalizedText.count,
            extractedText: limitedText,
            isTruncated: normalizedText.count > maxCharactersPerFile
        )
    }

    private static func pdfText(from url: URL, name: String) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ChatFileAttachmentReadError.unreadable(name)
        }

        var pages = [String]()
        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            pages.append(pageText)
        }

        return pages.joined(separator: "\n\n")
    }

    private static func plainText(from url: URL, name: String, type: UTType?) throws -> String {
        guard isTextLike(type: type, extension: url.pathExtension) else {
            throw ChatFileAttachmentReadError.unsupported(name)
        }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw ChatFileAttachmentReadError.unreadable(name)
        }

        guard let text = decodedString(from: data), looksReadable(text) else {
            throw ChatFileAttachmentReadError.unsupported(name)
        }

        return text
    }

    private static func isTextLike(type: UTType?, extension pathExtension: String) -> Bool {
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            return true
        }

        let textExtensions: Set<String> = [
            "csv", "log", "md", "markdown", "txt", "json", "jsonl", "xml",
            "yaml", "yml", "html", "htm", "css", "js", "ts", "tsx", "jsx",
            "swift", "py", "java", "c", "cc", "cpp", "h", "hpp", "m", "mm",
            "rb", "go", "rs", "php", "sh", "zsh", "sql", "toml", "ini"
        ]

        return textExtensions.contains(pathExtension.lowercased())
    }

    private static func decodedString(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii, .isoLatin1]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        return nil
    }

    private static func looksReadable(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }

        let invalidControlCount = scalars.filter { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
        }.count

        return Double(invalidControlCount) / Double(scalars.count) < 0.08
    }
}
