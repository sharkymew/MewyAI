import Foundation

nonisolated struct ChatMemoryHistoryBatch: Equatable {
    var index: Int
    var text: String
    var conversationCount: Int
    var segmentCount: Int

    var characterCount: Int {
        text.count
    }
}

nonisolated struct ChatMemoryHistoryBatchSummary: Codable, Equatable {
    var batchIndex: Int
    var summary: String
    var facts: [String]

    func withBatchIndex(_ index: Int) -> ChatMemoryHistoryBatchSummary {
        ChatMemoryHistoryBatchSummary(
            batchIndex: index,
            summary: summary,
            facts: facts
        )
    }
}

nonisolated struct ChatMemoryHistorySummaryResult: Codable, Equatable {
    var sections: [ChatMemorySummarySection]
    var operations: [ChatMemoryOperation]
}

nonisolated struct ChatMemoryHistoryConversationSummary: Identifiable, Codable, Equatable {
    var conversationID: UUID
    var fingerprint: String
    var updatedAt: Date
    var batchSummaries: [ChatMemoryHistoryBatchSummary]

    var id: UUID {
        conversationID
    }
}

nonisolated struct ChatMemoryHistorySummarySnapshot: Codable, Equatable {
    var conversationSummaries: [ChatMemoryHistoryConversationSummary]
    var result: ChatMemoryHistorySummaryResult
    var memorySnapshotEntries: [ChatMemoryEntry]
    var updatedAt: Date

    init(
        conversationSummaries: [ChatMemoryHistoryConversationSummary] = [],
        result: ChatMemoryHistorySummaryResult = ChatMemoryHistorySummaryResult(
            sections: [],
            operations: []
        ),
        memorySnapshotEntries: [ChatMemoryEntry] = [],
        updatedAt: Date = Date()
    ) {
        self.conversationSummaries = conversationSummaries
        self.result = result
        self.memorySnapshotEntries = memorySnapshotEntries
        self.updatedAt = updatedAt
    }

    var allBatchSummaries: [ChatMemoryHistoryBatchSummary] {
        conversationSummaries
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.conversationID.uuidString < rhs.conversationID.uuidString
            }
            .flatMap(\.batchSummaries)
    }
}

enum ChatMemoryHistorySummaryStore {
    private static let fileName = "ChatMemoryHistorySummary.json"
    private static let updateInProgressKey = "chatMemoryHistorySummaryUpdateInProgress"

    static let didChangeNotification = Notification.Name("ChatMemoryHistorySummaryStoreDidChange")

    static var isUpdateInProgress: Bool {
        UserDefaults.standard.bool(forKey: updateInProgressKey)
    }

    static func loadSnapshot() -> ChatMemoryHistorySummarySnapshot {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ChatMemoryHistorySummarySnapshot.self, from: data) else {
            return ChatMemoryHistorySummarySnapshot()
        }

        return snapshot
    }

    @discardableResult
    static func saveSnapshot(_ snapshot: ChatMemoryHistorySummarySnapshot) -> Bool {
        guard let fileURL,
              let data = try? JSONEncoder().encode(snapshot) else {
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
            notifyDidChange()
            return true
        } catch {
            return false
        }
    }

    static func clearPendingOperations(memorySnapshotEntries: [ChatMemoryEntry]) {
        var snapshot = loadSnapshot()
        snapshot.result.operations = []
        snapshot.memorySnapshotEntries = memorySnapshotEntries
        snapshot.updatedAt = Date()
        saveSnapshot(snapshot)
    }

    static func setUpdateInProgress(_ isInProgress: Bool) {
        guard Self.isUpdateInProgress != isInProgress else { return }
        UserDefaults.standard.set(isInProgress, forKey: updateInProgressKey)
        notifyDidChange()
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

enum ChatMemoryHistoryBatchBuilder {
    static let defaultBatchCharacterLimit = 18_000
    static let maxConversationSegmentCharacters = 12_000
    static let maxMessageCharacters = 2_400
    static let maxAttachmentTextCharacters = 1_200
    static let maxImageDescriptionCharacters = 1_000
    static let maxTitleCharacters = 120
    static let maxFileNameCharacters = 120

    static func makeBatches(
        conversations: [AIConversation],
        loadConversation: (UUID) -> AIConversation? = { ConversationStore.loadConversation(id: $0) },
        batchCharacterLimit: Int = defaultBatchCharacterLimit
    ) -> [ChatMemoryHistoryBatch] {
        let fullConversations = conversations.compactMap { conversation -> AIConversation? in
            let loadedConversation = conversation.isIndexOnly
                ? loadConversation(conversation.id) ?? conversation
                : conversation
            return hasReadableContent(loadedConversation) ? loadedConversation : nil
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }

        let segmentLimit = max(1, min(batchCharacterLimit, maxConversationSegmentCharacters))
        let segments = fullConversations.flatMap {
            renderedSegments(for: $0, segmentCharacterLimit: segmentLimit)
        }

        return packedBatches(
            from: segments,
            batchCharacterLimit: max(1, batchCharacterLimit)
        )
    }

    static func makeBatches(
        for conversation: AIConversation,
        batchCharacterLimit: Int = defaultBatchCharacterLimit
    ) -> [ChatMemoryHistoryBatch] {
        guard hasReadableContent(conversation) else { return [] }

        return packedBatches(
            from: renderedSegments(
                for: conversation,
                segmentCharacterLimit: max(1, min(batchCharacterLimit, maxConversationSegmentCharacters))
            ),
            batchCharacterLimit: max(1, batchCharacterLimit)
        )
    }

    static func fingerprint(for conversation: AIConversation) -> String {
        let messageFingerprints = conversation.messages.map { message in
            let fileFingerprint = message.fileAttachments.map { attachment in
                "\(attachment.id.uuidString):\(attachment.name.count):\(attachment.extractedText.count):\(attachment.isTruncated)"
            }
            .joined(separator: ",")
            return [
                message.id.uuidString,
                message.role,
                "\(message.content.count)",
                "\(message.imageAttachments.count)",
                "\(message.imageContextDescription.count)",
                fileFingerprint
            ].joined(separator: ":")
        }
        .joined(separator: "|")

        return [
            conversation.id.uuidString,
            "\(conversation.updatedAt.timeIntervalSince1970)",
            "\(conversation.messages.count)",
            messageFingerprints
        ].joined(separator: "|")
    }

    private static func hasReadableContent(_ conversation: AIConversation) -> Bool {
        conversation.messages.contains { renderedMessage($0) != nil }
    }

    private static func packedBatches(
        from segments: [RenderedHistorySegment],
        batchCharacterLimit: Int
    ) -> [ChatMemoryHistoryBatch] {
        var batches = [ChatMemoryHistoryBatch]()
        var currentSegments = [RenderedHistorySegment]()
        var currentLength = 0

        func appendCurrentBatchIfNeeded() {
            guard !currentSegments.isEmpty else { return }
            let text = currentSegments.map(\.text).joined(separator: "\n\n")
            batches.append(ChatMemoryHistoryBatch(
                index: batches.count + 1,
                text: text,
                conversationCount: Set(currentSegments.map(\.conversationID)).count,
                segmentCount: currentSegments.count
            ))
            currentSegments = []
            currentLength = 0
        }

        for segment in segments {
            let nextLength = currentLength + segment.text.count + (currentSegments.isEmpty ? 0 : 2)
            if !currentSegments.isEmpty, nextLength > batchCharacterLimit {
                appendCurrentBatchIfNeeded()
            }

            currentSegments.append(segment)
            currentLength += segment.text.count + (currentSegments.count == 1 ? 0 : 2)
        }

        appendCurrentBatchIfNeeded()
        return batches
    }

    private static func renderedSegments(
        for conversation: AIConversation,
        segmentCharacterLimit: Int
    ) -> [RenderedHistorySegment] {
        let messageBlocks = conversation.messages.compactMap { message in
            renderedMessage(message)
        }
        guard !messageBlocks.isEmpty else { return [] }

        var chunks = [[String]]()
        var currentChunk = [String]()
        var currentLength = 0

        for block in messageBlocks {
            let nextLength = currentLength + block.count + (currentChunk.isEmpty ? 0 : 2)
            if !currentChunk.isEmpty, nextLength > segmentCharacterLimit {
                chunks.append(currentChunk)
                currentChunk = []
                currentLength = 0
            }

            currentChunk.append(block)
            currentLength += block.count + (currentChunk.count == 1 ? 0 : 2)
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.enumerated().map { offset, chunk in
            let partText = chunks.count > 1 ? #" part="\#(offset + 1)""# : ""
            let text = """
            <conversation id="\(conversation.id.uuidString)" updated="\(dateText(conversation.updatedAt))" title="\(truncated(conversation.title, limit: maxTitleCharacters))"\(partText)>
            \(chunk.joined(separator: "\n\n"))
            </conversation>
            """
            return RenderedHistorySegment(conversationID: conversation.id, text: text)
        }
    }

    private static func renderedMessage(_ message: ChatMessage) -> String? {
        var parts = [String]()
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            parts.append(truncated(content, limit: maxMessageCharacters))
        }

        if !message.imageAttachments.isEmpty {
            let description = message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if description.isEmpty {
                parts.append("[image attached: \(message.imageAttachments.count)]")
            } else {
                parts.append("[image attached: \(truncated(description, limit: maxImageDescriptionCharacters))]")
            }
        }

        for attachment in message.fileAttachments {
            let fileName = truncated(attachment.name, limit: maxFileNameCharacters)
            let extractedText = attachment.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if extractedText.isEmpty {
                parts.append("[file attached: \(fileName)]")
            } else {
                parts.append("""
                [file attached: \(fileName)]
                \(truncated(extractedText, limit: maxAttachmentTextCharacters))
                """)
            }
        }

        guard !parts.isEmpty else { return nil }
        return "\(message.role): \(parts.joined(separator: "\n"))"
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit))) + "…"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct RenderedHistorySegment {
        let conversationID: UUID
        let text: String
    }
}

nonisolated enum ChatMemoryHistorySummaryPrompt {
    static func batchUserPrompt(
        entries: [ChatMemoryEntry],
        batch: ChatMemoryHistoryBatch,
        batchCount: Int
    ) -> String {
        """
        <existing_memories>
        \(ChatMemoryStore.numberedMemoryBlock(for: entries))
        </existing_memories>

        <history_batch index="\(batch.index)" total="\(batchCount)" characters="\(batch.characterCount)">
        \(batch.text)
        </history_batch>
        """
    }

    static func mergeUserPrompt(
        entries: [ChatMemoryEntry],
        batchSummaries: [ChatMemoryHistoryBatchSummary]
    ) -> String {
        """
        <existing_memories>
        \(ChatMemoryStore.numberedMemoryBlock(for: entries))
        </existing_memories>

        <history_batch_summaries>
        \(numberedBatchSummaries(batchSummaries))
        </history_batch_summaries>
        """
    }

    private static func numberedBatchSummaries(_ summaries: [ChatMemoryHistoryBatchSummary]) -> String {
        let blocks = summaries.enumerated().map { offset, summary in
            let facts = summary.facts.isEmpty
                ? "(no durable facts proposed)"
                : summary.facts.map { "- \($0)" }.joined(separator: "\n")
            return """
            [summary \(offset + 1), source batch \(summary.batchIndex)]
            summary: \(summary.summary)
            durable facts:
            \(facts)
            """
        }

        return blocks.isEmpty ? "(no batch summaries)" : blocks.joined(separator: "\n\n")
    }
}

nonisolated enum ChatMemoryHistorySummaryParser {
    static func batchSummary(from content: String) -> ChatMemoryHistoryBatchSummary? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        for candidate in jsonCandidates(in: trimmedContent) {
            if let summary = decodedBatchSummary(fromJSONString: candidate) {
                return summary
            }
        }

        return nil
    }

    static func result(from content: String) -> ChatMemoryHistorySummaryResult? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        for candidate in jsonCandidates(in: trimmedContent) {
            if let result = decodedResult(fromJSONString: candidate) {
                return result
            }
        }

        return nil
    }

    private static func jsonCandidates(in content: String) -> [String] {
        var candidates = [content]

        if let firstBrace = content.firstIndex(of: "{"),
           let lastBrace = content.lastIndex(of: "}"),
           firstBrace < lastBrace {
            candidates.append(String(content[firstBrace...lastBrace]))
        }

        return candidates
    }

    private static func decodedBatchSummary(fromJSONString jsonString: String) -> ChatMemoryHistoryBatchSummary? {
        guard let data = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BatchSummaryPayload.self, from: data) else {
            return nil
        }

        return payload.summary
    }

    private static func decodedResult(fromJSONString jsonString: String) -> ChatMemoryHistorySummaryResult? {
        guard let data = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(FinalSummaryPayload.self, from: data) else {
            return nil
        }

        return payload.result
    }

    private struct BatchSummaryPayload: Decodable {
        let rawSummary: String?
        let rawFacts: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rawSummary = try container.decodeIfPresent(String.self, forKey: .summary)
                ?? container.decodeIfPresent(String.self, forKey: .batchSummary)
            rawFacts = try container.decodeIfPresent([String].self, forKey: .facts)
                ?? container.decodeIfPresent([String].self, forKey: .memoryFacts)
                ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case summary
            case batchSummary = "batch_summary"
            case facts
            case memoryFacts = "memory_facts"
        }

        var summary: ChatMemoryHistoryBatchSummary? {
            let summaryText = sanitized(rawSummary)
            let facts = rawFacts.compactMap(sanitized)
            guard summaryText != nil || !facts.isEmpty else { return nil }

            return ChatMemoryHistoryBatchSummary(
                batchIndex: 0,
                summary: summaryText ?? "",
                facts: facts
            )
        }
    }

    private struct FinalSummaryPayload: Decodable {
        let hasSections: Bool
        let hasOperations: Bool
        let sections: [SectionCandidate]
        let operations: [OperationCandidate]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasSections = container.contains(.sections)
            hasOperations = container.contains(.operations)
            sections = try container.decodeIfPresent([SectionCandidate].self, forKey: .sections) ?? []
            operations = try container.decodeIfPresent([OperationCandidate].self, forKey: .operations) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case sections
            case operations
        }

        var result: ChatMemoryHistorySummaryResult? {
            guard hasSections || hasOperations else { return nil }
            return ChatMemoryHistorySummaryResult(
                sections: sections.compactMap(\.section),
                operations: operations.compactMap(\.operation)
            )
        }
    }

    private struct SectionCandidate: Decodable {
        let title: String?
        let body: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body)
                ?? container.decodeIfPresent(String.self, forKey: .content)
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case body
            case content
        }

        var section: ChatMemorySummarySection? {
            guard let title = sanitized(title),
                  let body = sanitized(body) else {
                return nil
            }

            return ChatMemorySummarySection(title: title, body: body)
        }
    }

    private struct OperationCandidate: Decodable {
        let action: String?
        let index: Int?
        let content: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try container.decodeIfPresent(String.self, forKey: .action)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            if let intIndex = try? container.decodeIfPresent(Int.self, forKey: .index) {
                index = intIndex
            } else if let stringIndex = try? container.decodeIfPresent(String.self, forKey: .index) {
                index = Int(stringIndex.trimmingCharacters(in: .whitespaces))
            } else {
                index = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case action
            case index
            case content
        }

        var operation: ChatMemoryOperation? {
            guard let action,
                  let parsedAction = ChatMemoryOperationAction(
                    rawValue: action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                  ) else {
                return nil
            }

            return ChatMemoryOperation(action: parsedAction, index: index, content: content)
        }
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
