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
            return AppLocalizations.format(
                "fileAttachment.error.tooLarge",
                defaultValue: "%@ is larger than %d MB and was skipped.",
                arguments: [name, maxMegabytes]
            )
        case .unsupported(let name):
            return AppLocalizations.format(
                "fileAttachment.error.unsupported",
                defaultValue: "%@ is not a readable text or PDF file.",
                arguments: [name]
            )
        case .empty(let name):
            return AppLocalizations.format(
                "fileAttachment.error.empty",
                defaultValue: "No usable text was extracted from %@.",
                arguments: [name]
            )
        case .unreadable(let name):
            return AppLocalizations.format(
                "fileAttachment.error.unreadable",
                defaultValue: "Failed to read %@.",
                arguments: [name]
            )
        }
    }
}

enum ChatFileAttachmentReader {
    nonisolated static let maxFileByteCount = 8 * 1024 * 1024
    nonisolated static let maxCharactersPerFile = 24_000
    nonisolated static let maxPDFPageCount = 80

    nonisolated static let supportedDocumentTypes: [UTType] = [
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

    nonisolated static let dropTypeIdentifiers: [String] = {
        var identifiers = supportedDocumentTypes.map(\.identifier)
        identifiers.insert(UTType.fileURL.identifier, at: 0)
        return identifiers
    }()

    static func attachment(from url: URL) throws -> ChatFileAttachment {
        guard url.isFileURL else {
            throw ChatFileAttachmentReadError.unreadable(url.lastPathComponent.isEmpty
                ? AppLocalizations.string("fileAttachment.defaultName", defaultValue: "File")
                : url.lastPathComponent)
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey, .localizedNameKey])
        let name = resourceValues?.localizedName ?? url.lastPathComponent
        guard let byteCount = fileByteCount(for: url, resourceValues: resourceValues) else {
            throw ChatFileAttachmentReadError.unreadable(name)
        }
        let maxMegabytes = maxFileByteCount / 1024 / 1024

        guard byteCount <= maxFileByteCount else {
            throw ChatFileAttachmentReadError.fileTooLarge(name, maxMegabytes)
        }

        let typeIdentifier = resourceValues?.typeIdentifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
        let type = typeIdentifier.flatMap(UTType.init)
        let rawText: String
        let wasExtractionTruncated: Bool

        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            let result = try pdfText(from: url, name: name)
            rawText = result.text
            wasExtractionTruncated = result.wasTruncated
        } else {
            rawText = try plainText(from: url, name: name, type: type)
            wasExtractionTruncated = false
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
            isTruncated: wasExtractionTruncated || normalizedText.count > maxCharactersPerFile
        )
    }

    private static func pdfText(from url: URL, name: String) throws -> (text: String, wasTruncated: Bool) {
        guard let document = PDFDocument(url: url) else {
            throw ChatFileAttachmentReadError.unreadable(name)
        }

        var pages = [String]()
        var characterCount = 0
        let pageLimit = min(document.pageCount, maxPDFPageCount)
        for pageIndex in 0..<pageLimit {
            guard let pageText = document.page(at: pageIndex)?.string,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            pages.append(pageText)
            characterCount += pageText.count
            if characterCount >= maxCharactersPerFile {
                return (pages.joined(separator: "\n\n"), true)
            }
        }

        return (pages.joined(separator: "\n\n"), document.pageCount > maxPDFPageCount)
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

    private static func fileByteCount(for url: URL, resourceValues: URLResourceValues?) -> Int? {
        if let fileSize = resourceValues?.fileSize {
            return fileSize
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
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
