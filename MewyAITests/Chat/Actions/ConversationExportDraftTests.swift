import XCTest
@testable import MewyAI

@MainActor
final class ConversationExportDraftTests: XCTestCase {
    func testPrepareBuildsMarkdownDocumentAndFileName() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let conversation = AIConversation(
            title: "Planning / Notes",
            messages: [ChatMessage(role: "user", content: "Hello")],
            updatedAt: updatedAt
        )
        var draft = ConversationExportDraft()

        draft.prepare(for: conversation)

        XCTAssertTrue(draft.isPresented)
        XCTAssertTrue(draft.document.text.contains("# Planning / Notes"))
        XCTAssertTrue(draft.document.text.contains("Hello"))
        XCTAssertEqual(draft.fileName, "Planning-Notes-\(fileDateString(updatedAt))")
    }

    func testSuccessfulCompletionClearsError() {
        var draft = ConversationExportDraft()
        draft.errorMessage = "Previous error"

        draft.handleCompletion(.success(URL(fileURLWithPath: "/tmp/export.md")))

        XCTAssertNil(draft.errorMessage)
    }

    func testCancelledCompletionLeavesErrorUnchanged() {
        var draft = ConversationExportDraft()
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

        draft.handleCompletion(.failure(error))

        XCTAssertNil(draft.errorMessage)
    }

    func testFailedCompletionStoresUserFacingMessage() {
        var draft = ConversationExportDraft()
        let error = NSError(
            domain: "ConversationExportDraftTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Disk is full"]
        )

        draft.handleCompletion(.failure(error))

        XCTAssertTrue(draft.errorMessage?.contains("Disk is full") == true)
    }

    func testClearError() {
        var draft = ConversationExportDraft()
        draft.errorMessage = "Previous error"

        draft.clearError()

        XCTAssertNil(draft.errorMessage)
    }

    private func fileDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }
}
