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
    var usage: ChatUsage?
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
        usage: ChatUsage? = nil,
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
        self.usage = usage
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
        usage = try container.decodeIfPresent(ChatUsage.self, forKey: .usage)
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
    var indexedMessageCount: Int?

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
        activeMCPServerIDs: [UUID] = [],
        indexedMessageCount: Int? = nil
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
        self.indexedMessageCount = indexedMessageCount
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
        indexedMessageCount = nil
    }

    var normalized: AIConversation {
        var conversation = self
        conversation.messages = messages.map(\.normalized)
        conversation.messageRevisionGroups = messageRevisionGroups
            .map(\.normalized)
            .filter { !$0.revisions.isEmpty }
        return conversation
    }

    nonisolated var hasInformation: Bool {
        storedMessageCount > 0
    }

    nonisolated var storedMessageCount: Int {
        indexedMessageCount ?? messages.count
    }

    nonisolated var isIndexOnly: Bool {
        indexedMessageCount != nil && messages.isEmpty
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
    private static let conversationsDirectoryName = "Conversations"
    private static let conversationIndexFileName = "Index.json"

    nonisolated private struct ConversationIndex: Codable, Equatable {
        var version: Int
        var conversations: [ConversationIndexEntry]
    }

    nonisolated private struct ConversationIndexEntry: Codable, Equatable {
        var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var hasGeneratedTitle: Bool
        var isPinned: Bool
        var activeSkillIDs: [UUID]
        var activeMCPServerIDs: [UUID]
        var messageCount: Int

        init(_ conversation: AIConversation) {
            id = conversation.id
            title = conversation.title
            createdAt = conversation.createdAt
            updatedAt = conversation.updatedAt
            hasGeneratedTitle = conversation.hasGeneratedTitle
            isPinned = conversation.isPinned
            activeSkillIDs = conversation.activeSkillIDs
            activeMCPServerIDs = conversation.activeMCPServerIDs
            messageCount = conversation.storedMessageCount
        }
    }

    static func loadConversations() -> [AIConversation] {
        loadConversations(fileManager: .default)
    }

    static func loadConversationsForStartup() -> [AIConversation] {
        loadConversationsForStartup(
            selectedConversationID: loadSelectedConversationID(),
            fileManager: .default
        )
    }

    static func loadConversationsForStartup(
        selectedConversationID: UUID?,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation] {
        var conversations = loadConversationList(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard !conversations.isEmpty else {
            return [AIConversation()]
        }

        let conversationIDToLoad = selectedConversationID.flatMap { selectedID in
            conversations.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? conversations.first?.id

        if let conversationIDToLoad,
           let loadedConversation = loadConversation(
            id: conversationIDToLoad,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
           ) {
            if let index = conversations.firstIndex(where: { $0.id == loadedConversation.id }) {
                conversations[index] = loadedConversation
            } else {
                conversations.insert(loadedConversation, at: 0)
            }
        }

        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func loadConversationList(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation] {
        if let indexedConversations = loadSplitConversationList(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) {
            UserDefaults.standard.removeObject(forKey: conversationsKey)
            return indexedConversations
        }

        return loadConversations(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
    }

    static func loadConversation(
        id: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> AIConversation? {
        if let splitConversation = loadSplitConversation(
            id: id,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) {
            return splitConversation
        }

        if let fileURL = conversationsFileURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL),
           let data = try? Data(contentsOf: fileURL),
           let conversations = decodedConversations(from: data) {
            return conversations.first { $0.id == id }
        }

        if let data = UserDefaults.standard.data(forKey: conversationsKey),
           let conversations = decodedConversations(from: data) {
            return conversations.first { $0.id == id }
        }

        return nil
    }

    static func loadConversations(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation] {
        if let splitConversations = loadSplitConversations(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) {
            UserDefaults.standard.removeObject(forKey: conversationsKey)
            return splitConversations
        }

        if let fileURL = conversationsFileURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL),
           let data = try? Data(contentsOf: fileURL),
           let conversations = decodedConversations(from: data) {
            let migratedConversations = migratedConversationsForStorage(conversations)
            saveConversations(
                migratedConversations,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            UserDefaults.standard.removeObject(forKey: conversationsKey)
            return migratedConversations
        }

        if let data = UserDefaults.standard.data(forKey: conversationsKey),
           let conversations = decodedConversations(from: data) {
            let migratedConversations = migratedConversationsForStorage(conversations)
            saveConversations(
                migratedConversations,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            return migratedConversations
        }

        return [AIConversation()]
    }

    @discardableResult
    static func saveConversations(
        _ conversations: [AIConversation],
        synchronize: Bool = false,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        let storageConversations = migratedConversationsForStorage(conversations)
        guard writeSplitConversations(
            storageConversations,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL,
            removesStaleFiles: true
        ) else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: conversationsKey)

        if synchronize {
            UserDefaults.standard.synchronize()
        }
        return true
    }

    @discardableResult
    static func saveConversation(
        _ conversation: AIConversation,
        in conversations: [AIConversation],
        synchronize: Bool = false,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        let mergedConversations = conversations.map { storedConversation in
            storedConversation.id == conversation.id ? conversation : storedConversation
        }
        guard mergedConversations.contains(where: { $0.id == conversation.id }) else {
            return saveConversations(
                conversations + [conversation],
                synchronize: synchronize,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
        }

        let storageConversations = migratedConversationsForStorage(mergedConversations)
        guard let storedConversation = storageConversations.first(where: { $0.id == conversation.id }) else {
            return false
        }

        let didWriteConversationFile = storedConversation.isIndexOnly || writeSplitConversation(
            storedConversation,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard didWriteConversationFile,
              writeSplitConversationIndex(
                storageConversations,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
              ) else {
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

    private static func applicationSupportURL(
        fileManager: FileManager,
        override: URL?
    ) -> URL? {
        override ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static func conversationsFileURL(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> URL? {
        self.applicationSupportURL(fileManager: fileManager, override: applicationSupportURL)?
            .appendingPathComponent(conversationsFileName, isDirectory: false)
    }

    private static func conversationsDirectoryURL(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> URL? {
        self.applicationSupportURL(fileManager: fileManager, override: applicationSupportURL)?
            .appendingPathComponent(conversationsDirectoryName, isDirectory: true)
    }

    private static func conversationIndexURL(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> URL? {
        conversationsDirectoryURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL)?
            .appendingPathComponent(conversationIndexFileName, isDirectory: false)
    }

    private static func conversationFileURL(
        for id: UUID,
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> URL? {
        conversationsDirectoryURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL)?
            .appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private static func decodedConversations(from data: Data) -> [AIConversation]? {
        let jsonData = decompressedStorageData(from: data)
        guard let conversations = try? JSONDecoder().decode([AIConversation].self, from: jsonData),
              !conversations.isEmpty else {
            return nil
        }

        return conversations
            .map(\.normalized)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // Conversations.json holds LZFSE-compressed JSON; installs that predate
    // compression stored plain JSON, so both formats must stay readable.
    private static let lzfseMagicPrefix = Data("bvx".utf8)

    static func compressedStorageData(from data: Data) -> Data {
        guard let compressed = try? (data as NSData).compressed(using: .lzfse) as Data,
              compressed.count < data.count else {
            return data
        }
        return compressed
    }

    static func decompressedStorageData(from data: Data) -> Data {
        guard data.starts(with: lzfseMagicPrefix),
              let decompressed = try? (data as NSData).decompressed(using: .lzfse) as Data else {
            return data
        }
        return decompressed
    }

    private static func migratedConversationsForStorage(_ conversations: [AIConversation]) -> [AIConversation] {
        ConversationImageStore.migratedLegacyImages(in: conversations.map(\.normalized))
    }

    private static func loadSplitConversations(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> [AIConversation]? {
        guard let index = loadSplitIndex(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else {
            return nil
        }

        let conversations = index.conversations.compactMap { entry -> AIConversation? in
            loadSplitConversation(
                id: entry.id,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
        }

        guard conversations.count == index.conversations.count else { return nil }
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func loadSplitConversationList(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> [AIConversation]? {
        guard let index = loadSplitIndex(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else {
            return nil
        }

        return index.conversations
            .map { indexedConversation(from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func loadSplitIndex(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> ConversationIndex? {
        guard let indexURL = conversationIndexURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ),
              let indexData = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(ConversationIndex.self, from: indexData),
              !index.conversations.isEmpty else {
            return nil
        }

        return index
    }

    private static func loadSplitConversation(
        id: UUID,
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> AIConversation? {
        guard let fileURL = conversationFileURL(
            for: id,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let jsonData = decompressedStorageData(from: data)
        return try? JSONDecoder().decode(AIConversation.self, from: jsonData).normalized
    }

    private static func indexedConversation(from entry: ConversationIndexEntry) -> AIConversation {
        AIConversation(
            id: entry.id,
            title: entry.title,
            messages: [],
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            hasGeneratedTitle: entry.hasGeneratedTitle,
            isPinned: entry.isPinned,
            activeSkillIDs: entry.activeSkillIDs,
            activeMCPServerIDs: entry.activeMCPServerIDs,
            indexedMessageCount: entry.messageCount
        )
    }

    private static func writeSplitConversations(
        _ conversations: [AIConversation],
        fileManager: FileManager,
        applicationSupportURL: URL?,
        removesStaleFiles: Bool
    ) -> Bool {
        guard !conversations.isEmpty,
              let directoryURL = conversationsDirectoryURL(
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
              ) else {
            return false
        }

        do {
            try createProtectedDirectory(directoryURL, fileManager: fileManager)
            for conversation in conversations where !conversation.isIndexOnly {
                try writeSplitConversationThrowing(
                    conversation,
                    fileManager: fileManager,
                    applicationSupportURL: applicationSupportURL
                )
            }
            try writeSplitConversationIndexThrowing(
                conversations,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            if removesStaleFiles {
                try removeStaleConversationFiles(
                    keeping: Set(conversations.map(\.id)),
                    in: directoryURL,
                    fileManager: fileManager
                )
            }
            return true
        } catch {
            return false
        }
    }

    private static func writeSplitConversation(
        _ conversation: AIConversation,
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> Bool {
        do {
            try writeSplitConversationThrowing(
                conversation,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            return true
        } catch {
            return false
        }
    }

    private static func writeSplitConversationIndex(
        _ conversations: [AIConversation],
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> Bool {
        do {
            try writeSplitConversationIndexThrowing(
                conversations,
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            return true
        } catch {
            return false
        }
    }

    private static func writeSplitConversationThrowing(
        _ conversation: AIConversation,
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) throws {
        guard let fileURL = conversationFileURL(
            for: conversation.id,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try createProtectedDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
        let data = try JSONEncoder().encode(conversation)
        try writeProtectedData(compressedStorageData(from: data), to: fileURL, fileManager: fileManager)
    }

    private static func writeSplitConversationIndexThrowing(
        _ conversations: [AIConversation],
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) throws {
        guard let fileURL = conversationIndexURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let index = ConversationIndex(
            version: 1,
            conversations: conversations
                .sorted { $0.updatedAt > $1.updatedAt }
                .map(ConversationIndexEntry.init)
        )
        let data = try JSONEncoder().encode(index)
        try writeProtectedData(data, to: fileURL, fileManager: fileManager)
    }

    private static func removeStaleConversationFiles(
        keeping retainedIDs: Set<UUID>,
        in directoryURL: URL,
        fileManager: FileManager
    ) throws {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in fileURLs where fileURL.pathExtension == "json" && fileURL.lastPathComponent != conversationIndexFileName {
            let idString = fileURL.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: idString),
                  !retainedIDs.contains(id) else {
                continue
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    private static func createProtectedDirectory(_ directoryURL: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    private static func writeProtectedData(_ data: Data, to fileURL: URL, fileManager: FileManager) throws {
        try createProtectedDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }

    private static func writeProtectedConversations(
        _ data: Data,
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> Bool {
        guard let fileURL = conversationsFileURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else { return false }

        do {
            try writeProtectedData(data, to: fileURL, fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }
}
