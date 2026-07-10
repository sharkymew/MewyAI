import CryptoKit
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision
import ZIPFoundation

nonisolated enum KnowledgeDocumentProcessingError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case tooLarge(String)
    case tooManyPages(String)
    case tooMuchText(String)
    case tooManyChunks(String)
    case unsafeArchive(String)
    case empty(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "无法读取 \(name)。"
        case .unsupported(let name):
            return "暂不支持 \(name) 的文件格式。"
        case .tooLarge(let name):
            return "\(name) 超过 50 MB 限制。"
        case .tooManyPages(let name):
            return "\(name) 超过 300 页限制。"
        case .tooMuchText(let name):
            return "\(name) 提取后的文本超过 500 万字符限制。"
        case .tooManyChunks(let name):
            return "导入 \(name) 后知识库会超过 10,000 个分块限制。"
        case .unsafeArchive(let name):
            return "\(name) 的 Office 归档损坏、加密或展开体积异常。"
        case .empty(let name):
            return "没有从 \(name) 提取到可用文本。"
        case .duplicate(let name):
            return "\(name) 与知识库中已有文件内容相同，已跳过。"
        }
    }
}

nonisolated struct ExtractedKnowledgeDocument {
    struct Segment: Equatable {
        var text: String
        var location: String
    }

    var name: String
    var typeIdentifier: String?
    var byteCount: Int
    var contentHash: String
    var segments: [Segment]

    var text: String {
        segments.map(\.text).joined(separator: "\n\n")
    }
}

nonisolated enum KnowledgeDocumentProcessor {
    static let maxFileByteCount = 50 * 1024 * 1024
    static let maxExtractedCharacters = 5_000_000
    static let maxPDFPageCount = 300
    static let maxArchiveEntries = 10_000
    static let maxArchiveExpandedByteCount: UInt64 = 200 * 1024 * 1024

    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [
            .pdf, .plainText, .text, .sourceCode, .json, .xml, .html, .rtf,
            .commaSeparatedText, .image
        ]
        for fileExtension in ["docx", "xlsx", "pptx"] {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        return types
    }()

    static func extract(from url: URL) async throws -> ExtractedKnowledgeDocument {
        guard url.isFileURL else {
            throw KnowledgeDocumentProcessingError.unreadable(url.lastPathComponent)
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey, .localizedNameKey])
        let name = values?.localizedName ?? url.lastPathComponent
        guard let byteCount = values?.fileSize ?? fileByteCount(for: url),
              byteCount <= maxFileByteCount,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            if (values?.fileSize ?? 0) > maxFileByteCount {
                throw KnowledgeDocumentProcessingError.tooLarge(name)
            }
            throw KnowledgeDocumentProcessingError.unreadable(name)
        }

        let fileExtension = url.pathExtension.lowercased()
        let typeIdentifier = values?.typeIdentifier ?? UTType(filenameExtension: fileExtension)?.identifier
        let type = typeIdentifier.flatMap(UTType.init)
        let segments: [ExtractedKnowledgeDocument.Segment]

        if fileExtension == "docx" {
            segments = try extractDOCX(from: url, name: name)
        } else if fileExtension == "xlsx" {
            segments = try extractXLSX(from: url, name: name)
        } else if fileExtension == "pptx" {
            segments = try extractPPTX(from: url, name: name)
        } else if type?.conforms(to: .pdf) == true || fileExtension == "pdf" {
            segments = try await extractPDF(from: url, name: name)
        } else if type?.conforms(to: .image) == true {
            segments = try await extractImage(from: data, name: name)
        } else if type?.conforms(to: .rtf) == true || fileExtension == "rtf" {
            segments = try extractAttributed(data: data, documentType: .rtf, name: name)
        } else if type?.conforms(to: .html) == true || ["html", "htm"].contains(fileExtension) {
            segments = try extractAttributed(data: data, documentType: .html, name: name)
        } else if isTextLike(type: type, fileExtension: fileExtension),
                  let text = decodedString(from: data),
                  looksReadable(text) {
            segments = [ExtractedKnowledgeDocument.Segment(text: text, location: "")]
        } else {
            throw KnowledgeDocumentProcessingError.unsupported(name)
        }

        let normalizedSegments = segments.compactMap { segment -> ExtractedKnowledgeDocument.Segment? in
            let text = normalize(segment.text)
            guard !text.isEmpty else { return nil }
            return ExtractedKnowledgeDocument.Segment(text: text, location: segment.location)
        }
        guard !normalizedSegments.isEmpty else {
            throw KnowledgeDocumentProcessingError.empty(name)
        }
        let characterCount = normalizedSegments.reduce(0) { $0 + $1.text.count }
        guard characterCount <= maxExtractedCharacters else {
            throw KnowledgeDocumentProcessingError.tooMuchText(name)
        }

        return ExtractedKnowledgeDocument(
            name: name,
            typeIdentifier: typeIdentifier,
            byteCount: byteCount,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            segments: normalizedSegments
        )
    }

    private static func extractPDF(from url: URL, name: String) async throws -> [ExtractedKnowledgeDocument.Segment] {
        guard let document = PDFDocument(url: url) else {
            throw KnowledgeDocumentProcessingError.unreadable(name)
        }
        guard document.pageCount <= maxPDFPageCount else {
            throw KnowledgeDocumentProcessingError.tooManyPages(name)
        }

        var segments = [ExtractedKnowledgeDocument.Segment]()
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count < 40 {
                let thumbnail = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
                if let cgImage = thumbnail.cgImage,
                   let recognized = try? await recognizeText(in: cgImage),
                   !recognized.isEmpty {
                    text = recognized
                }
            }
            if !text.isEmpty {
                segments.append(.init(text: text, location: "Page \(index + 1)"))
            }
        }
        return segments
    }

    private static func extractImage(from data: Data, name: String) async throws -> [ExtractedKnowledgeDocument.Segment] {
        guard imageDataIsWithinLimits(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw KnowledgeDocumentProcessingError.unreadable(name)
        }
        let text = try await recognizeText(in: image)
        return [.init(text: text, location: "Image")]
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }

    private static func extractAttributed(
        data: Data,
        documentType: NSAttributedString.DocumentType,
        name: String
    ) throws -> [ExtractedKnowledgeDocument.Segment] {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ) else {
            throw KnowledgeDocumentProcessingError.unreadable(name)
        }
        return [.init(text: attributed.string, location: "")]
    }

    private static func extractDOCX(from url: URL, name: String) throws -> [ExtractedKnowledgeDocument.Segment] {
        let archive = try validatedArchive(at: url, name: name)
        guard let data = try archiveData("word/document.xml", archive: archive, name: name) else {
            throw KnowledgeDocumentProcessingError.unreadable(name)
        }
        return [.init(text: OOXMLTextParser.text(from: data), location: "Document")]
    }

    private static func extractPPTX(from url: URL, name: String) throws -> [ExtractedKnowledgeDocument.Segment] {
        let archive = try validatedArchive(at: url, name: name)
        let slidePaths = archive
            .filter { $0.path.hasPrefix("ppt/slides/slide") && $0.path.hasSuffix(".xml") }
            .map(\.path)
            .sorted(by: naturalPathOrder)
        return try slidePaths.enumerated().compactMap { index, path in
            guard let slideData = try archiveData(path, archive: archive, name: name) else { return nil }
            var text = OOXMLTextParser.text(from: slideData)
            let notesPath = "ppt/notesSlides/notesSlide\(index + 1).xml"
            if let notesData = try archiveData(notesPath, archive: archive, name: name) {
                let notes = OOXMLTextParser.text(from: notesData)
                if !notes.isEmpty { text += "\n\nNotes:\n\(notes)" }
            }
            return .init(text: text, location: "Slide \(index + 1)")
        }
    }

    private static func extractXLSX(from url: URL, name: String) throws -> [ExtractedKnowledgeDocument.Segment] {
        let archive = try validatedArchive(at: url, name: name)
        let sharedStrings: [String]
        if let data = try archiveData("xl/sharedStrings.xml", archive: archive, name: name) {
            sharedStrings = SharedStringsParser.strings(from: data)
        } else {
            sharedStrings = []
        }

        let workbookSheets = try xlsxWorkbookSheets(archive: archive, name: name)
        let fallbackSheetPaths = archive
            .filter { $0.path.hasPrefix("xl/worksheets/sheet") && $0.path.hasSuffix(".xml") }
            .map { (name: "", path: $0.path) }
            .sorted { naturalPathOrder($0.path, $1.path) }
        let sheets = workbookSheets.isEmpty ? fallbackSheetPaths : workbookSheets
        return try sheets.enumerated().compactMap { index, sheet in
            let path = sheet.path
            guard let data = try archiveData(path, archive: archive, name: name) else { return nil }
            return .init(
                text: WorksheetParser.text(from: data, sharedStrings: sharedStrings),
                location: sheet.name.isEmpty ? "Sheet \(index + 1)" : sheet.name
            )
        }
    }

    private static func xlsxWorkbookSheets(
        archive: Archive,
        name: String
    ) throws -> [(name: String, path: String)] {
        guard let workbookData = try archiveData("xl/workbook.xml", archive: archive, name: name),
              let relationshipsData = try archiveData(
                "xl/_rels/workbook.xml.rels",
                archive: archive,
                name: name
              ) else {
            return []
        }
        let relationships = WorkbookRelationshipsParser.relationships(from: relationshipsData)
        return WorkbookSheetsParser.sheets(from: workbookData).compactMap { sheet in
            guard var target = relationships[sheet.relationshipID] else { return nil }
            target = target.replacingOccurrences(of: "\\", with: "/")
            guard !target.contains("..") else { return nil }
            if target.hasPrefix("/") { target.removeFirst() }
            let path = target.hasPrefix("xl/") ? target : "xl/\(target)"
            guard path.hasPrefix("xl/worksheets/"), path.hasSuffix(".xml") else { return nil }
            return (sheet.name, path)
        }
    }

    private static func validatedArchive(at url: URL, name: String) throws -> Archive {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw KnowledgeDocumentProcessingError.unsafeArchive(name)
        }
        var entryCount = 0
        var expandedSize: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard expandedSize <= maxArchiveExpandedByteCount,
                  entry.uncompressedSize <= maxArchiveExpandedByteCount - expandedSize else {
                throw KnowledgeDocumentProcessingError.unsafeArchive(name)
            }
            expandedSize += entry.uncompressedSize
            let hasAbnormalExpansion = entry.uncompressedSize > 10 * 1024 * 1024
                && entry.compressedSize > 0
                && entry.uncompressedSize / entry.compressedSize > 1_000
            guard entryCount <= maxArchiveEntries,
                  expandedSize <= maxArchiveExpandedByteCount,
                  !hasAbnormalExpansion,
                  entry.path != "EncryptedPackage",
                  entry.path != "EncryptionInfo",
                  entry.type == .file || entry.type == .directory else {
                throw KnowledgeDocumentProcessingError.unsafeArchive(name)
            }
        }
        return archive
    }

    private static func archiveData(
        _ path: String,
        archive: Archive,
        name: String
    ) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        guard entry.type == .file,
              entry.uncompressedSize <= maxArchiveExpandedByteCount else {
            throw KnowledgeDocumentProcessingError.unsafeArchive(name)
        }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        } catch {
            throw KnowledgeDocumentProcessingError.unsafeArchive(name)
        }
    }

    private static func naturalPathOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTextLike(type: UTType?, fileExtension: String) -> Bool {
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            return true
        }
        return [
            "csv", "log", "md", "markdown", "txt", "json", "jsonl", "xml", "yaml", "yml",
            "html", "htm", "css", "js", "ts", "tsx", "jsx", "swift", "py", "java", "c",
            "cc", "cpp", "h", "hpp", "m", "mm", "rb", "go", "rs", "php", "sh", "zsh",
            "sql", "toml", "ini"
        ].contains(fileExtension)
    }

    private static func decodedString(from data: Data) -> String? {
        for encoding in [
            String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii, .isoLatin1
        ] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private static func looksReadable(_ text: String) -> Bool {
        guard !text.unicodeScalars.isEmpty else { return false }
        let invalidControlCount = text.unicodeScalars.reduce(0) { count, scalar in
            let isInvalid = CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
            return count + (isInvalid ? 1 : 0)
        }
        return Double(invalidControlCount) / Double(text.unicodeScalars.count) < 0.08
    }

    private static func fileByteCount(for url: URL) -> Int? {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) {
            guard values.isRegularFile != false else { return nil }
            if let fileSize = values.fileSize { return fileSize }
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private static func imageDataIsWithinLimits(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }
        let pixels = Int64(width.intValue) * Int64(height.intValue)
        return pixels > 0 && pixels <= 24_000_000
    }
}

nonisolated enum KnowledgeChunker {
    static let targetCharacters = 1_200
    static let overlapCharacters = 200

    static func chunks(from document: ExtractedKnowledgeDocument) -> [KnowledgeChunk] {
        var chunks = [KnowledgeChunk]()
        for segment in document.segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            var start = text.startIndex
            while start < text.endIndex {
                let targetEnd = text.index(start, offsetBy: targetCharacters, limitedBy: text.endIndex) ?? text.endIndex
                let end = preferredBoundary(in: text, start: start, targetEnd: targetEnd)
                let chunkText = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunkText.isEmpty {
                    chunks.append(KnowledgeChunk(index: chunks.count, text: chunkText, location: segment.location))
                }
                guard end < text.endIndex else { break }
                start = text.index(end, offsetBy: -overlapCharacters, limitedBy: start) ?? end
                if start == end { break }
            }
        }
        return chunks
    }

    private static func preferredBoundary(
        in text: String,
        start: String.Index,
        targetEnd: String.Index
    ) -> String.Index {
        guard targetEnd < text.endIndex else { return text.endIndex }
        let searchStart = text.index(targetEnd, offsetBy: -300, limitedBy: start) ?? start
        let range = searchStart..<targetEnd
        for marker in ["\n\n", "\n", "。", ". ", "！", "？"] {
            if let match = text.range(of: marker, options: .backwards, range: range) {
                return match.upperBound
            }
        }
        return targetEnd
    }
}

private nonisolated final class OOXMLTextParser: NSObject, XMLParserDelegate {
    private var output = ""
    private var capturesText = false
    private var headingLevel: Int?
    private var wroteParagraphText = false

    static func text(from data: Data) -> String {
        let delegate = OOXMLTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.output
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "p" {
            headingLevel = nil
            wroteParagraphText = false
        } else if localName == "pStyle" {
            let style = attributeDict["w:val"] ?? attributeDict["val"] ?? ""
            if style.lowercased().hasPrefix("heading") {
                headingLevel = Int(style.drop { !$0.isNumber }) ?? 1
            }
        } else if localName == "t" {
            capturesText = true
            if !wroteParagraphText {
                if let headingLevel {
                    output += String(repeating: "#", count: min(max(headingLevel, 1), 6)) + " "
                }
                wroteParagraphText = true
            }
        }
        if localName == "tab" { output += "\t" }
        if localName == "br" { output += "\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesText { output += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "p" || localName == "tr" { output += "\n" }
        if localName == "tc" { output += "\t" }
        if localName == "t" { capturesText = false }
    }
}

private nonisolated final class WorkbookSheetsParser: NSObject, XMLParserDelegate {
    struct Sheet {
        var name: String
        var relationshipID: String
    }

    private var output = [Sheet]()

    static func sheets(from data: Data) -> [Sheet] {
        let delegate = WorkbookSheetsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.output
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "sheet",
              let name = attributeDict["name"],
              let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] else { return }
        output.append(Sheet(name: name, relationshipID: relationshipID))
    }
}

private nonisolated final class WorkbookRelationshipsParser: NSObject, XMLParserDelegate {
    private var output = [String: String]()

    static func relationships(from data: Data) -> [String: String] {
        let delegate = WorkbookRelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.output
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "Relationship",
              let id = attributeDict["Id"],
              let target = attributeDict["Target"] else { return }
        output[id] = target
    }
}

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings = [String]()
    private var current = ""
    private var capturesText = false

    static func strings(from data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "si" { current = "" }
        capturesText = localName == "t"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesText { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "si" { strings.append(current) }
        if localName == "t" { capturesText = false }
    }
}

private nonisolated final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var output = ""
    private var cellReference = ""
    private var cellType = ""
    private var value = ""
    private var formula = ""
    private var capturesValue = false
    private var capturesFormula = false
    private var capturesInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func text(from data: Data, sharedStrings: [String]) -> String {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.output
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "c" {
            cellReference = attributeDict["r"] ?? ""
            cellType = attributeDict["t"] ?? ""
            value = ""
            formula = ""
        }
        capturesValue = localName == "v"
        capturesFormula = localName == "f"
        capturesInlineText = localName == "t"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesValue || capturesInlineText { value += string }
        if capturesFormula { formula += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "c" {
            var displayValue = value
            if cellType == "s", let index = Int(value), sharedStrings.indices.contains(index) {
                displayValue = sharedStrings[index]
            }
            if !formula.isEmpty {
                displayValue = "=\(formula)" + (displayValue.isEmpty ? "" : " -> \(displayValue)")
            }
            if !displayValue.isEmpty {
                output += "\(cellReference): \(displayValue)\n"
            }
        }
        if localName == "v" { capturesValue = false }
        if localName == "f" { capturesFormula = false }
        if localName == "t" { capturesInlineText = false }
    }
}
