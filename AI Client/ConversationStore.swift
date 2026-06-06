import Foundation

struct ChatImageAttachment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fileName: String?
    var md5: String?
    var byteCount: Int
    var mimeType: String
    var dataURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case md5
        case byteCount
        case mimeType
        case dataURL
    }

    nonisolated init(
        id: UUID = UUID(),
        fileName: String,
        md5: String,
        byteCount: Int,
        mimeType: String = "image/jpeg"
    ) {
        self.id = id
        self.fileName = fileName
        self.md5 = md5
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.dataURL = nil
    }

    nonisolated init(id: UUID = UUID(), dataURL: String) {
        self.id = id
        self.fileName = nil
        self.md5 = nil
        self.byteCount = 0
        self.mimeType = Self.mimeType(from: dataURL) ?? "image/jpeg"
        self.dataURL = dataURL
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        md5 = try container.decodeIfPresent(String.self, forKey: .md5)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        dataURL = try container.decodeIfPresent(String.self, forKey: .dataURL)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? dataURL.flatMap(Self.mimeType(from:))
            ?? "image/jpeg"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(md5, forKey: .md5)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(mimeType, forKey: .mimeType)
        if fileName == nil {
            try container.encodeIfPresent(dataURL, forKey: .dataURL)
        }
    }

    nonisolated private static func mimeType(from dataURL: String) -> String? {
        guard dataURL.hasPrefix("data:"),
              let semicolonIndex = dataURL.firstIndex(of: ";") else {
            return nil
        }

        let startIndex = dataURL.index(dataURL.startIndex, offsetBy: 5)
        guard startIndex < semicolonIndex else { return nil }
        return String(dataURL[startIndex..<semicolonIndex])
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

struct ChatToolCall: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var displayName: String
    var argumentsJSON: String
    var mcpServerID: UUID?
    var mcpServerName: String
    var mcpToolName: String

    init(
        id: String,
        name: String,
        displayName: String,
        argumentsJSON: String,
        mcpServerID: UUID? = nil,
        mcpServerName: String = "",
        mcpToolName: String = ""
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.argumentsJSON = argumentsJSON
        self.mcpServerID = mcpServerID
        self.mcpServerName = mcpServerName
        self.mcpToolName = mcpToolName
    }
}

struct ChatToolResult: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var toolCallID: String
    var name: String
    var content: String
    var isError: Bool

    init(
        id: UUID = UUID(),
        toolCallID: String,
        name: String,
        content: String,
        isError: Bool = false
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.name = name
        self.content = content
        self.isError = isError
    }
}

struct ChatToolExchange: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var assistantContent: String
    var reasoningContent: String
    var toolCalls: [ChatToolCall]
    var toolResults: [ChatToolResult]

    init(
        id: UUID = UUID(),
        assistantContent: String = "",
        reasoningContent: String = "",
        toolCalls: [ChatToolCall] = [],
        toolResults: [ChatToolResult] = []
    ) {
        self.id = id
        self.assistantContent = assistantContent
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolResults = toolResults
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
    var toolExchanges: [ChatToolExchange] = []
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
        toolExchanges: [ChatToolExchange] = [],
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
        self.toolExchanges = toolExchanges
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
        toolExchanges = try container.decodeIfPresent([ChatToolExchange].self, forKey: .toolExchanges) ?? []
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
        message.toolExchanges = message.toolExchanges.filter { !$0.toolCalls.isEmpty || !$0.toolResults.isEmpty }
        message.contentChunks = []
        return message
    }
}

struct ChatMessageRevision: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var messages: [ChatMessage]

    init(id: UUID = UUID(), messages: [ChatMessage]) {
        self.id = id
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }

    var normalized: ChatMessageRevision {
        var revision = self
        revision.messages = messages.map(\.normalized)
        return revision
    }
}

struct ChatMessageRevisionGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var selectedRevisionID: UUID
    var revisions: [ChatMessageRevision]

    init(
        id: UUID,
        selectedRevisionID: UUID,
        revisions: [ChatMessageRevision]
    ) {
        self.id = id
        self.selectedRevisionID = selectedRevisionID
        self.revisions = revisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        revisions = try container.decodeIfPresent([ChatMessageRevision].self, forKey: .revisions) ?? []
        selectedRevisionID = try container.decodeIfPresent(UUID.self, forKey: .selectedRevisionID)
            ?? revisions.first?.id
            ?? UUID()
    }

    var normalized: ChatMessageRevisionGroup {
        var group = self
        group.revisions = revisions
            .map(\.normalized)
            .filter { revision in
                revision.messages.contains { $0.id == id && $0.role == "user" }
            }

        if !group.revisions.contains(where: { $0.id == group.selectedRevisionID }),
           let firstRevisionID = group.revisions.first?.id {
            group.selectedRevisionID = firstRevisionID
        }

        return group
    }
}

struct AIConversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
    var messages: [ChatMessage] = []
    var messageRevisionGroups: [ChatMessageRevisionGroup] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var hasGeneratedTitle: Bool = false
    var isPinned: Bool = false
    var activeSkillIDs: [UUID] = []
    var activeMCPServerIDs: [UUID] = []

    init(
        id: UUID = UUID(),
        title: String = AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat"),
        messages: [ChatMessage] = [],
        messageRevisionGroups: [ChatMessageRevisionGroup] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        hasGeneratedTitle: Bool = false,
        isPinned: Bool = false,
        activeSkillIDs: [UUID] = [],
        activeMCPServerIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.messageRevisionGroups = messageRevisionGroups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hasGeneratedTitle = hasGeneratedTitle
        self.isPinned = isPinned
        self.activeSkillIDs = activeSkillIDs
        self.activeMCPServerIDs = activeMCPServerIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        messageRevisionGroups = try container.decodeIfPresent([ChatMessageRevisionGroup].self, forKey: .messageRevisionGroups) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        hasGeneratedTitle = try container.decodeIfPresent(Bool.self, forKey: .hasGeneratedTitle) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        activeSkillIDs = try container.decodeIfPresent([UUID].self, forKey: .activeSkillIDs) ?? []
        activeMCPServerIDs = try container.decodeIfPresent([UUID].self, forKey: .activeMCPServerIDs) ?? []
    }

    var normalized: AIConversation {
        var conversation = self
        conversation.messages = messages.map(\.normalized)
        conversation.messageRevisionGroups = messageRevisionGroups
            .map(\.normalized)
            .filter { !$0.revisions.isEmpty }
        return conversation
    }

    var hasInformation: Bool {
        !messages.isEmpty
    }

    nonisolated var allStoredMessages: [ChatMessage] {
        messages + messageRevisionGroups.flatMap { group in
            group.revisions.flatMap(\.messages)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case messages
        case messageRevisionGroups
        case createdAt
        case updatedAt
        case hasGeneratedTitle
        case isPinned
        case activeSkillIDs
        case activeMCPServerIDs
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
            let migratedConversations = migratedConversationsForStorage(conversations)
            if migratedConversations != conversations {
                saveConversations(migratedConversations)
            }
            UserDefaults.standard.removeObject(forKey: conversationsKey)
            return migratedConversations
        }

        if let data = UserDefaults.standard.data(forKey: conversationsKey),
           let conversations = decodedConversations(from: data) {
            let migratedConversations = migratedConversationsForStorage(conversations)
            saveConversations(migratedConversations)
            return migratedConversations
        }

        return [AIConversation()]
    }

    @discardableResult
    static func saveConversations(_ conversations: [AIConversation], synchronize: Bool = false) -> Bool {
        let storageConversations = migratedConversationsForStorage(conversations)
        guard let data = try? JSONEncoder().encode(storageConversations) else { return false }

        guard writeProtectedConversations(data) else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: conversationsKey)

        if synchronize {
            UserDefaults.standard.synchronize()
        }
        return true
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

    static func clearSelectedConversationID() {
        UserDefaults.standard.removeObject(forKey: selectedConversationIDKey)
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

    private static func migratedConversationsForStorage(_ conversations: [AIConversation]) -> [AIConversation] {
        ConversationImageStore.migratedLegacyImages(in: conversations.map(\.normalized))
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
