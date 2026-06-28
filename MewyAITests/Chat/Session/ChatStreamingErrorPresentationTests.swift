import XCTest
@testable import MewyAI

@MainActor
final class ChatStreamingErrorPresentationTests: XCTestCase {
    func testSilentPreparationFailuresDoNotCreateAssistantMessages() {
        XCTAssertNil(ChatStreamingErrorPresentation.assistantMessage(for: .emptyMessage))
        XCTAssertNil(ChatStreamingErrorPresentation.assistantMessage(for: .missingConversation))
        XCTAssertNil(ChatStreamingErrorPresentation.assistantMessage(for: .alreadyGenerating))
    }

    func testVisiblePreparationFailuresHaveAssistantMessages() {
        let failures: [ChatSessionViewModel.StreamingTurnPreparationFailure] = [
            .vertexMCPUnsupported,
            .modelToolsUnsupported,
            .noMCPTools,
            .imageWithoutDescription,
            .contextImageWithoutDescription,
            .missingBaseURL,
            .missingModel,
            .tooManyActiveRequests(limit: 3)
        ]

        for failure in failures {
            let message = ChatStreamingErrorPresentation.assistantMessage(for: failure)
            XCTAssertFalse(message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    func testTooManyActiveRequestsMessageIncludesLimit() {
        let message = ChatStreamingErrorPresentation.assistantMessage(
            for: .tooManyActiveRequests(limit: 3)
        )

        XCTAssertTrue(message?.contains("3") == true)
    }

    func testPersistentAssistantMessageTrimsOrFallsBack() {
        XCTAssertEqual(
            ChatStreamingErrorPresentation.persistentAssistantMessage(from: "  Network failed\n"),
            "Network failed"
        )

        XCTAssertFalse(
            ChatStreamingErrorPresentation.persistentAssistantMessage(from: " \n ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
    }
}
