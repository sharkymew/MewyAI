import Foundation

/// Pure matching logic for the sidebar conversation search. A conversation
/// matches when every whitespace-separated query term occurs (case- and
/// diacritic-insensitively) in its title, any current or revision message,
/// attached file text, or hidden image context description.
nonisolated enum ConversationSearchFilter {
    static func queryTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func filtered(_ conversations: [AIConversation], query: String) -> [AIConversation] {
        let terms = queryTerms(from: query)
        guard !terms.isEmpty else { return conversations }
        return conversations.filter { matches($0, queryTerms: terms) }
    }

    static func matches(_ conversation: AIConversation, query: String) -> Bool {
        matches(conversation, queryTerms: queryTerms(from: query))
    }

    static func matches(_ conversation: AIConversation, queryTerms: [String]) -> Bool {
        queryTerms.allSatisfy { term in
            contains(conversation, term: term)
        }
    }

    private static func contains(_ conversation: AIConversation, term: String) -> Bool {
        if found(term, in: conversation.title) {
            return true
        }

        return conversation.allStoredMessages.contains { message in
            matches(message, term: term)
        }
    }

    private static func matches(_ message: ChatMessage, term: String) -> Bool {
        if found(term, in: message.content) {
            return true
        }
        if message.content.isEmpty, message.contentChunks.contains(where: { found(term, in: $0) }) {
            return true
        }
        if found(term, in: message.imageContextDescription) {
            return true
        }

        return message.fileAttachments.contains { attachment in
            found(term, in: attachment.name) || found(term, in: attachment.extractedText)
        }
    }

    private static func found(_ term: String, in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
