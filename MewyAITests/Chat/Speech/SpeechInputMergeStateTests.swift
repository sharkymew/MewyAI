import XCTest
@testable import MewyAI

@MainActor
final class SpeechInputMergeStateTests: XCTestCase {
    func testMergedTextTrimsSpeechAndAddsSeparatorWhenNeeded() {
        XCTAssertEqual(
            SpeechInputMergeState.mergedText(baseText: "Hello", speechText: " world "),
            "Hello world"
        )
        XCTAssertEqual(
            SpeechInputMergeState.mergedText(baseText: "Hello ", speechText: "world"),
            "Hello world"
        )
    }

    func testMergedTextUsesSpeechOnlyWhenBaseIsBlank() {
        XCTAssertEqual(
            SpeechInputMergeState.mergedText(baseText: "   ", speechText: " hello "),
            "hello"
        )
    }

    func testEmptyTranscriptDoesNotReturnMergedTextAndTracksCurrentInput() {
        var state = SpeechInputMergeState()
        state.reset(baseText: "draft")

        let merged = state.mergedText(for: "   ", currentText: "edited draft")

        XCTAssertNil(merged)
        XCTAssertEqual(state.baseText, "draft")
        XCTAssertEqual(state.lastTranscript, "")
        XCTAssertEqual(state.lastMergedText, "edited draft")
    }

    func testFirstTranscriptUsesCurrentTextWhenDraftChangedAfterRecordingStarted() {
        var state = SpeechInputMergeState()
        state.reset(baseText: "initial")

        let merged = state.mergedText(for: "speech", currentText: "manual edit")

        XCTAssertEqual(merged, "manual edit speech")
        XCTAssertEqual(state.baseText, "manual edit")
        XCTAssertEqual(state.lastTranscript, "speech")
        XCTAssertEqual(state.lastMergedText, "manual edit speech")
    }

    func testNextTranscriptKeepsOriginalBaseWhenInputMatchesLastMergedText() {
        var state = SpeechInputMergeState()
        state.reset(baseText: "initial")

        let first = state.mergedText(for: "one", currentText: "initial")
        let second = state.mergedText(for: "two", currentText: first ?? "")

        XCTAssertEqual(first, "initial one")
        XCTAssertEqual(second, "initial two")
        XCTAssertEqual(state.baseText, "initial")
    }

    func testNextTranscriptUpdatesBaseWhenUserEditedMergedInput() {
        var state = SpeechInputMergeState()
        state.reset(baseText: "initial")

        _ = state.mergedText(for: "one", currentText: "initial")
        let second = state.mergedText(for: "two", currentText: "manual edit")

        XCTAssertEqual(second, "manual edit two")
        XCTAssertEqual(state.baseText, "manual edit")
    }
}
