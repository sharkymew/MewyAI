import XCTest
@testable import MewyAI

@MainActor
final class ChatAttachmentDraftTests: XCTestCase {
    func testAppendImagesRejectsUnsupportedModelWithoutMutatingAttachments() {
        var draft = ChatAttachmentDraft()
        let image = Self.imageAttachment("one")

        draft.appendPendingImageAttachments(
            [image],
            source: "selection",
            supportsImages: false
        )

        XCTAssertTrue(draft.pendingImageAttachments.isEmpty)
        XCTAssertNotNil(draft.imageSelectionError)
    }

    func testAppendImagesTrimsToRemainingCapacity() {
        var draft = ChatAttachmentDraft()
        draft.pendingImageAttachments = [
            Self.imageAttachment("existing-1"),
            Self.imageAttachment("existing-2"),
            Self.imageAttachment("existing-3")
        ]

        draft.appendPendingImageAttachments(
            [
                Self.imageAttachment("new-1"),
                Self.imageAttachment("new-2")
            ],
            source: "selection",
            supportsImages: true
        )

        XCTAssertEqual(draft.pendingImageAttachments.map(\.fileName), [
            "existing-1.jpg",
            "existing-2.jpg",
            "existing-3.jpg",
            "new-1.jpg"
        ])
        XCTAssertNotNil(draft.imageSelectionError)
    }

    func testAppendImagesReportsReadFailureForEmptyInput() {
        var draft = ChatAttachmentDraft()

        draft.appendPendingImageAttachments(
            [],
            source: "clipboard",
            supportsImages: true
        )

        XCTAssertTrue(draft.pendingImageAttachments.isEmpty)
        XCTAssertNotNil(draft.imageSelectionError)
    }

    func testAppendFilesUsesFallbackErrorWhenNoFilesWereRead() {
        var draft = ChatAttachmentDraft()

        draft.appendPendingFileAttachments(
            [],
            source: "selection",
            fallbackError: "Read failed"
        )

        XCTAssertTrue(draft.pendingFileAttachments.isEmpty)
        XCTAssertEqual(draft.imageSelectionError, "Read failed")
    }

    func testAppendFilesTrimsToRemainingCapacity() {
        var draft = ChatAttachmentDraft()
        draft.pendingFileAttachments = [
            Self.fileAttachment("one"),
            Self.fileAttachment("two"),
            Self.fileAttachment("three"),
            Self.fileAttachment("four")
        ]

        draft.appendPendingFileAttachments(
            [
                Self.fileAttachment("five"),
                Self.fileAttachment("six")
            ],
            source: "selection"
        )

        XCTAssertEqual(draft.pendingFileAttachments.map(\.name), [
            "one.txt",
            "two.txt",
            "three.txt",
            "four.txt",
            "five.txt"
        ])
        XCTAssertNotNil(draft.imageSelectionError)
    }

    func testClearRemovesAllPendingAttachmentsAndErrors() {
        var draft = ChatAttachmentDraft()
        draft.pendingImageAttachments = [Self.imageAttachment("image")]
        draft.pendingFileAttachments = [Self.fileAttachment("file")]
        draft.imageSelectionError = "error"

        draft.clear()

        XCTAssertTrue(draft.pendingImageAttachments.isEmpty)
        XCTAssertTrue(draft.pendingFileAttachments.isEmpty)
        XCTAssertNil(draft.imageSelectionError)
        XCTAssertFalse(draft.hasPendingAttachments)
    }

    func testSetEditingAttachmentsReplacesPendingAttachments() {
        var draft = ChatAttachmentDraft()
        draft.pendingImageAttachments = [Self.imageAttachment("old")]
        draft.pendingFileAttachments = [Self.fileAttachment("old")]

        draft.setEditingAttachments(
            images: [Self.imageAttachment("new-image")],
            files: [Self.fileAttachment("new-file")]
        )

        XCTAssertEqual(draft.pendingImageAttachments.map(\.fileName), ["new-image.jpg"])
        XCTAssertEqual(draft.pendingFileAttachments.map(\.name), ["new-file.txt"])
    }

    private static func imageAttachment(_ name: String) -> ChatImageAttachment {
        ChatImageAttachment(
            fileName: "\(name).jpg",
            md5: name,
            byteCount: 12
        )
    }

    private static func fileAttachment(_ name: String) -> ChatFileAttachment {
        ChatFileAttachment(
            name: "\(name).txt",
            typeIdentifier: "public.plain-text",
            byteCount: 12,
            characterCount: 5,
            extractedText: "hello",
            isTruncated: false
        )
    }
}
