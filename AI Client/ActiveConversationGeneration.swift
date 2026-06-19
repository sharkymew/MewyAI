import Foundation
import SwiftUI

@MainActor
final class ActiveConversationGeneration {
    let conversationID: UUID
    let assistantMessageID: UUID
    let service: AIService
    let tokenBuffer = StreamingTokenBuffer()
    var hasReasoning = false
    var hasContent = false
    var reasoningIsExpanded = false
    var didCollapseReasoningAfterThinking = false
    var isFlushScheduled = false
    var flushTask: Task<Void, Never>?

    init(conversationID: UUID, assistantMessageID: UUID, service: AIService) {
        self.conversationID = conversationID
        self.assistantMessageID = assistantMessageID
        self.service = service
    }

    func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }
}
