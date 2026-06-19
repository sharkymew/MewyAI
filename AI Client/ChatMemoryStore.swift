import Foundation

nonisolated struct ChatMemoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var content: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceConversationID: UUID?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceConversationID: UUID? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceConversationID = sourceConversationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sourceConversationID = try container.decodeIfPresent(UUID.self, forKey: .sourceConversationID)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt
        case updatedAt
        case sourceConversationID
    }
}

nonisolated enum ChatMemoryOperationAction: String, Codable, Equatable {
    case add
    case update
    case delete
}

nonisolated struct ChatMemoryOperation: Codable, Equatable {
    var action: ChatMemoryOperationAction
    var index: Int?
    var content: String?
}

enum ChatMemoryStore {
    static let memoryEnabledKey = "globalMemoryEnabled"
    static let defaultMemoryEnabled = true
    static let historyRecallEnabledKey = "chatHistoryRecallEnabled"
    static let defaultHistoryRecallEnabled = true
    nonisolated static let maxEntryCount = 200
    nonisolated static let maxEntryCharacters = 400
    nonisolated static let maxExchangeCharacters = 4_000
    private static let memoriesFileName = "ChatMemories.json"

    static var isMemoryEnabled: Bool {
        if UserDefaults.standard.object(forKey: memoryEnabledKey) == nil {
            return defaultMemoryEnabled
        }
        return UserDefaults.standard.bool(forKey: memoryEnabledKey)
    }

    static func loadEntries() -> [ChatMemoryEntry] {
        guard let fileURL = memoriesFileURL,
              let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([ChatMemoryEntry].self, from: data) else {
            return []
        }

        return entries.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @discardableResult
    static func saveEntries(_ entries: [ChatMemoryEntry]) -> Bool {
        guard let fileURL = memoriesFileURL,
              let data = try? JSONEncoder().encode(entries) else {
            return false
        }

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

    static func clearEntries() {
        saveEntries([])
    }

    private static var memoriesFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(memoriesFileName, isDirectory: false)
    }

    // MARK: - Prompt rendering

    nonisolated static func promptAppendix(for entries: [ChatMemoryEntry]) -> String {
        let lines = numberedMemoryLines(for: entries)
        guard !lines.isEmpty else { return "" }

        return """


        <user_memory>
        Long-term memories about the user, distilled from previous conversations in this app. Each line shows the date it was last updated. Treat them as background context: use them when relevant, ignore them when not. Do not recite this list or mention the memory system unless the user asks about it.
        \(lines.joined(separator: "\n"))
        </user_memory>
        """
    }

    nonisolated static func extractionUserPrompt(
        entries: [ChatMemoryEntry],
        userText: String,
        assistantText: String
    ) -> String {
        return """
        <existing_memories>
        \(numberedMemoryBlock(for: entries))
        </existing_memories>

        <latest_exchange>
        user: \(truncatedExchangeText(userText))
        assistant: \(truncatedExchangeText(assistantText))
        </latest_exchange>
        """
    }

    nonisolated static func summaryUserPrompt(entries: [ChatMemoryEntry]) -> String {
        """
        <existing_memories>
        \(numberedMemoryBlock(for: entries))
        </existing_memories>
        """
    }

    nonisolated static func managementUserPrompt(
        entries: [ChatMemoryEntry],
        userInstruction: String
    ) -> String {
        """
        <existing_memories>
        \(numberedMemoryBlock(for: entries))
        </existing_memories>

        <user_instruction>
        \(truncatedExchangeText(userInstruction))
        </user_instruction>
        """
    }

    nonisolated static func numberedMemoryBlock(for entries: [ChatMemoryEntry]) -> String {
        let lines = numberedMemoryLines(for: entries)
        return lines.isEmpty ? "(no memories yet)" : lines.joined(separator: "\n")
    }

    private nonisolated static func numberedMemoryLines(for entries: [ChatMemoryEntry]) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return entries.enumerated().compactMap { index, entry in
            let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return "\(index + 1). [\(dateFormatter.string(from: entry.updatedAt))] \(content)"
        }
    }

    private nonisolated static func truncatedExchangeText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxExchangeCharacters else { return trimmed }
        return String(trimmed.prefix(maxExchangeCharacters)) + "…"
    }

    // MARK: - Applying extraction operations

    /// Applies model-produced operations to the current entry list.
    /// `snapshotIDs` are the entry IDs that were rendered (1-based) into the
    /// extraction prompt; indexes in `operations` refer to that snapshot, so
    /// entries changed by a concurrent extraction are matched by ID, not position.
    nonisolated static func applying(
        _ operations: [ChatMemoryOperation],
        to entries: [ChatMemoryEntry],
        snapshotIDs: [UUID],
        sourceConversationID: UUID?,
        date: Date = Date()
    ) -> [ChatMemoryEntry] {
        var updatedEntries = entries

        for operation in operations {
            switch operation.action {
            case .add:
                guard let content = sanitizedMemoryContent(operation.content) else { continue }
                guard !updatedEntries.contains(where: { $0.content == content }) else { continue }
                updatedEntries.append(ChatMemoryEntry(
                    content: content,
                    createdAt: date,
                    updatedAt: date,
                    sourceConversationID: sourceConversationID
                ))
            case .update:
                guard let content = sanitizedMemoryContent(operation.content),
                      let entryID = snapshotID(at: operation.index, in: snapshotIDs),
                      let entryIndex = updatedEntries.firstIndex(where: { $0.id == entryID }) else {
                    continue
                }
                updatedEntries[entryIndex].content = content
                updatedEntries[entryIndex].updatedAt = date
            case .delete:
                guard let entryID = snapshotID(at: operation.index, in: snapshotIDs) else { continue }
                updatedEntries.removeAll { $0.id == entryID }
            }
        }

        if updatedEntries.count > maxEntryCount {
            let sortedByAge = updatedEntries.sorted { $0.updatedAt > $1.updatedAt }
            let keptIDs = Set(sortedByAge.prefix(maxEntryCount).map(\.id))
            updatedEntries.removeAll { !keptIDs.contains($0.id) }
        }

        return updatedEntries
    }

    private nonisolated static func snapshotID(at index: Int?, in snapshotIDs: [UUID]) -> UUID? {
        guard let index, index >= 1, index <= snapshotIDs.count else { return nil }
        return snapshotIDs[index - 1]
    }

    private nonisolated static func sanitizedMemoryContent(_ content: String?) -> String? {
        guard let content else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxEntryCharacters else { return trimmed }
        return String(trimmed.prefix(maxEntryCharacters)) + "…"
    }
}
