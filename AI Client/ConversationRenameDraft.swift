import Foundation

struct ConversationRenameDraft: Equatable {
    var conversationID: UUID?
    var title = ""
    var isPresented = false

    mutating func begin(conversation: AIConversation) {
        conversationID = conversation.id
        title = conversation.title
        isPresented = true
    }

    mutating func reset() {
        conversationID = nil
        title = ""
        isPresented = false
    }

    static func normalizedTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty
            ? AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
            : trimmedTitle
    }
}
