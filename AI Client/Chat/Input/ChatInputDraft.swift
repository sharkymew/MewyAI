import Combine
import Foundation

@MainActor
final class ChatInputDraft: ObservableObject {
    private static let blankScalarSet = CharacterSet.whitespacesAndNewlines

    @Published var isFocused = false
    @Published private(set) var focusRequestID = 0
    @Published private(set) var textRevision = 0
    @Published private(set) var measuredLineCount = 1
    @Published private(set) var hasSubmittableText = false

    private(set) var text = ""

    var showsExpandedInputButton: Bool {
        measuredLineCount > 3
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateFromTextView(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
    }

    func updateFromExpandedTextView(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
        textRevision += 1
    }

    func updateMeasuredLineCount(_ lineCount: Int) {
        let lineCount = max(lineCount, 1)
        guard measuredLineCount != lineCount else { return }
        measuredLineCount = lineCount
    }

    func setText(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
        textRevision += 1
    }

    func clearText() {
        setText("")
    }

    func clearAndResignFocus() {
        clearText()
        isFocused = false
        focusRequestID += 1
    }

    func requestFocus() {
        isFocused = true
        focusRequestID += 1
    }

    func resignFocus() {
        isFocused = false
        focusRequestID += 1
    }

    private func updateSubmittableTextState() {
        let newValue = text.unicodeScalars.contains { !Self.blankScalarSet.contains($0) }
        if hasSubmittableText != newValue {
            hasSubmittableText = newValue
        }
    }
}
