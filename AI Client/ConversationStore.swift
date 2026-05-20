import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let role: String
    var content: String
    var contentChunks: [String] = []
    var reasoningContent: String = ""
    var reasoningChunks: [String] = []
    var isReasoningExpanded: Bool = false
    var isStopped: Bool = false
    
    var normalized: ChatMessage {
        var message = self
        if message.content.isEmpty, !message.contentChunks.isEmpty {
            message.content = message.contentChunks.joined()
        }
        if message.reasoningContent.isEmpty, !message.reasoningChunks.isEmpty {
            message.reasoningContent = message.reasoningChunks.joined()
        }
        message.contentChunks = []
        message.reasoningChunks = []
        return message
    }
}

struct AIConversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var hasGeneratedTitle: Bool = false
    
    var normalized: AIConversation {
        var conversation = self
        conversation.messages = messages.map(\.normalized)
        return conversation
    }
}

enum ConversationStore {
    private static let conversationsKey = "savedConversations"
    private static let selectedConversationIDKey = "selectedConversationID"
    
    static func loadConversations() -> [AIConversation] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let conversations = try? JSONDecoder().decode([AIConversation].self, from: data),
              !conversations.isEmpty else {
            return [AIConversation()]
        }
        
        return conversations
            .map(\.normalized)
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    static func saveConversations(_ conversations: [AIConversation]) {
        let normalizedConversations = conversations.map(\.normalized)
        guard let data = try? JSONEncoder().encode(normalizedConversations) else { return }
        UserDefaults.standard.set(data, forKey: conversationsKey)
    }
    
    static func loadSelectedConversationID() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: selectedConversationIDKey) else {
            return nil
        }
        
        return UUID(uuidString: idString)
    }
    
    static func saveSelectedConversationID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: selectedConversationIDKey)
    }
}
