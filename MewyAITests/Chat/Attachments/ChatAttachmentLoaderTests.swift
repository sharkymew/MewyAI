import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import MewyAI

@MainActor
final class ChatAttachmentLoaderTests: XCTestCase {
    func testImagePixelCountUsesImageScale() {
        let image = UIImage(
            size: CGSize(width: 10, height: 20),
            scale: 2
        )

        XCTAssertEqual(ChatAttachmentLoader.imagePixelCount(image), 800)
    }

    func testImageDataWithinLimitsRejectsNonImageData() {
        XCTAssertFalse(ChatAttachmentLoader.imageDataIsWithinLimits(Data("not an image".utf8)))
    }

    func testImageDataWithinLimitsAcceptsSmallImageData() throws {
        let data = try XCTUnwrap(Self.imageData(width: 8, height: 8))

        XCTAssertTrue(ChatAttachmentLoader.imageDataIsWithinLimits(data))
    }

    func testImageAttachmentFromImageCreatesInlineDataURLWhenNotStoredLocally() throws {
        let image = UIImage(size: CGSize(width: 16, height: 16), scale: 1)

        let attachment = try XCTUnwrap(ChatAttachmentLoader.imageAttachment(
            from: image,
            storesLocally: false
        ))

        XCTAssertNil(attachment.fileName)
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertTrue(attachment.dataURL?.hasPrefix("data:image/jpeg;base64,") == true)
        XCTAssertGreaterThan(attachment.byteCount, 0)
    }

    func testFileByteCountRejectsDirectories() throws {
        XCTAssertNil(ChatAttachmentLoader.fileByteCount(for: FileManager.default.temporaryDirectory))
    }

    func testReadableFileIdentifierRecognizesSupportedTypes() {
        XCTAssertTrue(ChatAttachmentLoader.isReadableFileIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(ChatAttachmentLoader.isReadableFileIdentifier(UTType.plainText.identifier))
        XCTAssertFalse(ChatAttachmentLoader.isReadableFileIdentifier(UTType.image.identifier))
    }

    func testProviderTypeDetectionSeparatesImagesAndReadableFiles() {
        let imageProvider = NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.png.identifier)
        let textProvider = NSItemProvider(item: "hello" as NSString, typeIdentifier: UTType.plainText.identifier)

        XCTAssertTrue(ChatAttachmentLoader.providerContainsImage(imageProvider))
        XCTAssertFalse(ChatAttachmentLoader.providerContainsReadableFile(imageProvider))

        XCTAssertFalse(ChatAttachmentLoader.providerContainsImage(textProvider))
        XCTAssertTrue(ChatAttachmentLoader.providerContainsReadableFile(textProvider))
    }

    func testFileAttachmentsFromURLsReturnsReadableFilesAndFirstError() throws {
        let directory = try makeTemporaryDirectory()
        let readableURL = directory.appendingPathComponent("notes.txt")
        let unreadableURL = directory.appendingPathComponent("image.bin")
        try "hello".write(to: readableURL, atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: unreadableURL)

        let result = ChatAttachmentLoader.fileAttachments(from: [unreadableURL, readableURL])

        XCTAssertEqual(result.attachments.map(\.name), ["notes.txt"])
        XCTAssertNotNil(result.firstError)
    }

    func testFileAttachmentsFromURLsHonorsMaxCount() throws {
        let directory = try makeTemporaryDirectory()
        let firstURL = directory.appendingPathComponent("one.txt")
        let secondURL = directory.appendingPathComponent("two.txt")
        try "one".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two".write(to: secondURL, atomically: true, encoding: .utf8)

        let result = ChatAttachmentLoader.fileAttachments(
            from: [firstURL, secondURL],
            maxCount: 1
        )

        XCTAssertEqual(result.attachments.map(\.name), ["one.txt"])
        XCTAssertNil(result.firstError)
    }

    private static func imageData(width: CGFloat, height: CGFloat) -> Data? {
        UIImage(size: CGSize(width: width, height: height), scale: 1)
            .pngData()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private extension UIImage {
    convenience init(size: CGSize, scale: CGFloat) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        guard let cgImage = image.cgImage else {
            self.init()
            return
        }

        self.init(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
