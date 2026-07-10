import UIKit
import XCTest
import ZIPFoundation
@testable import MewyAI

@MainActor
final class KnowledgeDocumentProcessorTests: XCTestCase {
    func testPlainTextHTMLRTFAndPDFExtraction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let textURL = directory.appendingPathComponent("notes.md")
        try Data("# 标题\n\nSwift knowledge base".utf8).write(to: textURL)
        let htmlURL = directory.appendingPathComponent("page.html")
        try Data("<html><body><h1>HTML title</h1><p>HTML body</p></body></html>".utf8).write(to: htmlURL)
        let rtfURL = directory.appendingPathComponent("page.rtf")
        try Data(#"{\rtf1\ansi RTF body}"#.utf8).write(to: rtfURL)
        let pdfURL = directory.appendingPathComponent("page.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        try renderer.writePDF(to: pdfURL) { context in
            context.beginPage()
            ("Searchable PDF body" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [
                .font: UIFont.systemFont(ofSize: 18)
            ])
        }

        let text = try await KnowledgeDocumentProcessor.extract(from: textURL)
        let html = try await KnowledgeDocumentProcessor.extract(from: htmlURL)
        let rtf = try await KnowledgeDocumentProcessor.extract(from: rtfURL)
        let pdf = try await KnowledgeDocumentProcessor.extract(from: pdfURL)

        XCTAssertTrue(text.text.contains("Swift knowledge base"))
        XCTAssertTrue(html.text.contains("HTML title"))
        XCTAssertTrue(html.text.contains("HTML body"))
        XCTAssertTrue(rtf.text.contains("RTF body"))
        XCTAssertTrue(pdf.text.contains("Searchable PDF body"))
        XCTAssertEqual(pdf.segments.first?.location, "Page 1")
    }

    func testDOCXExtractsHeadingsParagraphsAndTables() async throws {
        let url = temporaryDirectory().appendingPathComponent("sample.docx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try makeArchive(at: url, entries: [
            "word/document.xml": Data("""
            <w:document xmlns:w="w"><w:body>
              <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Overview</w:t></w:r></w:p>
              <w:p><w:r><w:t>Document paragraph</w:t></w:r></w:p>
              <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell A</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>Cell B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            </w:body></w:document>
            """.utf8)
        ])

        let document = try await KnowledgeDocumentProcessor.extract(from: url)

        XCTAssertTrue(document.text.contains("# Overview"))
        XCTAssertTrue(document.text.contains("Document paragraph"))
        XCTAssertTrue(document.text.contains("Cell A"))
        XCTAssertTrue(document.text.contains("Cell B"))
        XCTAssertEqual(document.segments.first?.location, "Document")
    }

    func testXLSXExtractsSheetNamesCoordinatesSharedStringsFormulasAndValues() async throws {
        let url = temporaryDirectory().appendingPathComponent("sample.xlsx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try makeArchive(at: url, entries: [
            "xl/workbook.xml": Data("""
            <workbook xmlns:r="r"><sheets><sheet name="Budget" sheetId="1" r:id="rId1"/></sheets></workbook>
            """.utf8),
            "xl/_rels/workbook.xml.rels": Data("""
            <Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>
            """.utf8),
            "xl/sharedStrings.xml": Data("""
            <sst><si><t>Revenue</t></si></sst>
            """.utf8),
            "xl/worksheets/sheet1.xml": Data("""
            <worksheet><sheetData><row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1"><f>SUM(B2:B3)</f><v>42</v></c>
            </row></sheetData></worksheet>
            """.utf8)
        ])

        let document = try await KnowledgeDocumentProcessor.extract(from: url)

        XCTAssertEqual(document.segments.first?.location, "Budget")
        XCTAssertTrue(document.text.contains("A1: Revenue"))
        XCTAssertTrue(document.text.contains("B1: =SUM(B2:B3) -> 42"))
    }

    func testPPTXExtractsSlidesInOrderAndSpeakerNotes() async throws {
        let url = temporaryDirectory().appendingPathComponent("sample.pptx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try makeArchive(at: url, entries: [
            "ppt/slides/slide2.xml": Data("<p:sld xmlns:p=\"p\" xmlns:a=\"a\"><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:sld>".utf8),
            "ppt/slides/slide1.xml": Data("<p:sld xmlns:p=\"p\" xmlns:a=\"a\"><a:p><a:r><a:t>First</a:t></a:r></a:p></p:sld>".utf8),
            "ppt/notesSlides/notesSlide1.xml": Data("<p:notes xmlns:p=\"p\" xmlns:a=\"a\"><a:p><a:r><a:t>Speaker note</a:t></a:r></a:p></p:notes>".utf8)
        ])

        let document = try await KnowledgeDocumentProcessor.extract(from: url)

        XCTAssertEqual(document.segments.map(\.location), ["Slide 1", "Slide 2"])
        XCTAssertTrue(document.segments[0].text.contains("First"))
        XCTAssertTrue(document.segments[0].text.contains("Speaker note"))
        XCTAssertTrue(document.segments[1].text.contains("Second"))
    }

    func testRejectsCorruptEncryptedEmptyAndOversizedFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let corruptURL = directory.appendingPathComponent("corrupt.docx")
        try Data("not a zip".utf8).write(to: corruptURL)
        let encryptedURL = directory.appendingPathComponent("encrypted.docx")
        try makeArchive(at: encryptedURL, entries: ["EncryptedPackage": Data("secret".utf8)])
        let emptyURL = directory.appendingPathComponent("empty.txt")
        try Data().write(to: emptyURL)
        let oversizedURL = directory.appendingPathComponent("oversized.txt")
        FileManager.default.createFile(atPath: oversizedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversizedURL)
        try handle.truncate(atOffset: UInt64(KnowledgeDocumentProcessor.maxFileByteCount + 1))
        try handle.close()

        await assertProcessingError(.unsafeArchive("corrupt.docx"), url: corruptURL)
        await assertProcessingError(.unsafeArchive("encrypted.docx"), url: encryptedURL)
        await assertProcessingError(.empty("empty.txt"), url: emptyURL)
        await assertProcessingError(.tooLarge("oversized.txt"), url: oversizedURL)
    }

    private func assertProcessingError(
        _ expected: KnowledgeDocumentProcessingError,
        url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await KnowledgeDocumentProcessor.extract(from: url)
            XCTFail("Expected processing to fail", file: file, line: line)
        } catch let error as KnowledgeDocumentProcessingError {
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeArchive(at url: URL, entries: [String: Data]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            }
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeDocumentProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
