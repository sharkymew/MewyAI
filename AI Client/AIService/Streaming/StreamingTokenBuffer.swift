import Foundation

@MainActor
final class StreamingTokenBuffer {
    private var pendingReasoningChunks: [String] = []
    private var pendingContentChunks: [String] = []

    var hasPendingReasoningText: Bool {
        !pendingReasoningChunks.isEmpty
    }

    var hasPendingContentText: Bool {
        !pendingContentChunks.isEmpty
    }

    var reasoningChunksSnapshot: [String] {
        pendingReasoningChunks
    }

    func appendReasoning(_ text: String) {
        pendingReasoningChunks.append(text)
    }

    func appendContent(_ text: String) {
        pendingContentChunks.append(text)
    }

    func consumePendingReasoningChunks() -> [String] {
        let chunks = pendingReasoningChunks
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        return chunks
    }

    func consumePendingContentText() -> String {
        let text = pendingContentChunks.joined()
        pendingContentChunks.removeAll(keepingCapacity: true)
        return text
    }

    func clearPendingTokens() {
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        pendingContentChunks.removeAll(keepingCapacity: true)
    }

    func reset() {
        clearPendingTokens()
    }
}
