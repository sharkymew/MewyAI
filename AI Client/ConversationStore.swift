import Foundation

struct ChatImageAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var dataURL: String

    init(id: UUID = UUID(), dataURL: String) {
        self.id = id
        self.dataURL = dataURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dataURL = try container.decode(String.self, forKey: .dataURL)
    }
}

struct ChatFileAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var typeIdentifier: String?
    var byteCount: Int
    var characterCount: Int
    var extractedText: String
    var isTruncated: Bool

    init(
        id: UUID = UUID(),
        name: String,
        typeIdentifier: String?,
        byteCount: Int,
        characterCount: Int,
        extractedText: String,
        isTruncated: Bool
    ) {
        self.id = id
        self.name = name
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.characterCount = characterCount
        self.extractedText = extractedText
        self.isTruncated = isTruncated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        typeIdentifier = try container.decodeIfPresent(String.self, forKey: .typeIdentifier)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        extractedText = try container.decode(String.self, forKey: .extractedText)
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? extractedText.count
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let role: String
    var content: String
    var imageAttachments: [ChatImageAttachment] = []
    var imageContextDescription: String = ""
    var fileAttachments: [ChatFileAttachment] = []
    var contentChunks: [String] = []
    var reasoningContent: String = ""
    var reasoningChunks: [String] = []
    var isReasoningExpanded: Bool = false
    var isStopped: Bool = false

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        imageAttachments: [ChatImageAttachment] = [],
        imageContextDescription: String = "",
        fileAttachments: [ChatFileAttachment] = [],
        contentChunks: [String] = [],
        reasoningContent: String = "",
        reasoningChunks: [String] = [],
        isReasoningExpanded: Bool = false,
        isStopped: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageAttachments = imageAttachments
        self.imageContextDescription = imageContextDescription
        self.fileAttachments = fileAttachments
        self.contentChunks = contentChunks
        self.reasoningContent = reasoningContent
        self.reasoningChunks = reasoningChunks
        self.isReasoningExpanded = isReasoningExpanded
        self.isStopped = isStopped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        imageAttachments = try container.decodeIfPresent([ChatImageAttachment].self, forKey: .imageAttachments) ?? []
        imageContextDescription = try container.decodeIfPresent(String.self, forKey: .imageContextDescription) ?? ""
        fileAttachments = try container.decodeIfPresent([ChatFileAttachment].self, forKey: .fileAttachments) ?? []
        contentChunks = try container.decodeIfPresent([String].self, forKey: .contentChunks) ?? []
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent) ?? ""
        reasoningChunks = try container.decodeIfPresent([String].self, forKey: .reasoningChunks) ?? []
        isReasoningExpanded = try container.decodeIfPresent(Bool.self, forKey: .isReasoningExpanded) ?? false
        isStopped = try container.decodeIfPresent(Bool.self, forKey: .isStopped) ?? false
    }

    var normalized: ChatMessage {
        var message = self
        if message.content.isEmpty, !message.contentChunks.isEmpty {
            message.content = message.contentChunks.joined()
        }
        if !message.reasoningContent.isEmpty {
            message.reasoningChunks = []
        }
        message.contentChunks = []
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

    var hasInformation: Bool {
        !messages.isEmpty
    }
}

enum ConversationStore {
    private static let conversationsKey = "savedConversations"
    private static let selectedConversationIDKey = "selectedConversationID"
    private static let conversationsFileName = "Conversations.json"

    static func loadConversations() -> [AIConversation] {
        if let fileURL = conversationsFileURL,
           let data = try? Data(contentsOf: fileURL),
           let conversations = decodedConversations(from: data) {
            UserDefaults.standard.removeObject(forKey: conversationsKey)
            return conversations
        }

        if let data = UserDefaults.standard.data(forKey: conversationsKey),
           let conversations = decodedConversations(from: data) {
            saveConversations(conversations)
            return conversations
        }

        return [AIConversation()]
    }

    static func saveConversations(_ conversations: [AIConversation], synchronize: Bool = false) {
        let normalizedConversations = conversations.map(\.normalized)
        guard let data = try? JSONEncoder().encode(normalizedConversations) else { return }

        if writeProtectedConversations(data) {
            UserDefaults.standard.removeObject(forKey: conversationsKey)
        } else {
            UserDefaults.standard.set(data, forKey: conversationsKey)
        }

        if synchronize {
            UserDefaults.standard.synchronize()
        }
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

    private static var conversationsFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(conversationsFileName, isDirectory: false)
    }

    private static func decodedConversations(from data: Data) -> [AIConversation]? {
        guard let conversations = try? JSONDecoder().decode([AIConversation].self, from: data),
              !conversations.isEmpty else {
            return nil
        }

        return conversations
            .map(\.normalized)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func writeProtectedConversations(_ data: Data) -> Bool {
        guard let fileURL = conversationsFileURL else { return false }

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }
}
