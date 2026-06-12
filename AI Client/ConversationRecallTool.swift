import Foundation

/// Built-in read-only agent tools that let the model consult the user's past
/// conversations on demand ("passive memory"). Unlike MCP tools they execute
/// locally against the in-memory conversation list and never require approval.
enum ConversationRecallTool {
    static let serverID = UUID(uuidString: "5EC0A11D-C4A7-4E8A-9B1F-0C2D3E4F5A6B")!
    static let searchFunctionName = "chat_history_search"
    static let readFunctionName = "chat_history_read"

    static let defaultSearchResultCount = 5
    static let maxSearchResultCount = 10
    static let maxExcerptsPerConversation = 3
    static let excerptPrefixCharacters = 60
    static let excerptSuffixCharacters = 140
    static let readPageCharacters = 6_000
    static let recentConversationIndexLimit = 15
    static let indexTitleCharacterLimit = 60

    /// System prompt appendix announcing the recall tools. Includes an index
    /// of recent conversations so the model can see that relevant history
    /// exists — without it, models rarely think to search on their own.
    static func promptAppendix(
        conversations: [AIConversation],
        excludedConversationIDs: Set<UUID>
    ) -> String {
        let recentConversations = conversations
            .filter { !excludedConversationIDs.contains($0.id) && !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(recentConversationIndexLimit)

        let indexLines = recentConversations.map { conversation -> String in
            let trimmedTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedTitle.count > indexTitleCharacterLimit
                ? String(trimmedTitle.prefix(indexTitleCharacterLimit)) + "…"
                : trimmedTitle
            return "[\(conversation.id.uuidString.prefix(8))] \(dateText(conversation.updatedAt)) · \(title)"
        }

        let indexBlock = indexLines.isEmpty
            ? "The user has no other stored conversations yet."
            : """
            Recent conversations (newest first; the bracketed id prefix works as conversation_id for chat_history_read):
            \(indexLines.joined(separator: "\n"))
            """

        return """


        <chat_history_recall>
        You can consult the user's previous conversations in this app at any time, without asking permission:
        - chat_history_search: keyword search across all past conversations (titles, messages, attachment text). Omit query to list recent conversations.
        - chat_history_read: read one conversation's transcript by conversation_id; long transcripts are paginated via page.

        Be proactive. Past conversations are your primary source of context about the user, their projects, and earlier decisions. Search BEFORE answering whenever:
        - the user refers to anything from before, even vaguely ("那个方案", "上次的 bug", "the file we discussed", or simply continuing earlier work);
        - the request touches an ongoing project, prior decision, or preference that may have been discussed;
        - knowing what was already said could change or improve your answer;
        - you are unsure whether relevant history exists — a search is local and nearly free, so default to searching instead of guessing or asking the user to repeat context.
        Skip the tools only for clearly self-contained requests (translations, generic facts, tasks with all context provided).
        If a conversation in the index below looks relevant, read it directly. When past context shapes your answer, briefly mention which conversation it came from.

        \(indexBlock)
        </chat_history_recall>
        """
    }

    // MARK: - Definitions

    static func definitions(excludingFunctionNames usedFunctionNames: Set<String> = []) -> [AgentToolDefinition] {
        let definitions = [
            AgentToolDefinition(
                functionName: searchFunctionName,
                displayName: AppLocalizations.string(
                    "recallTool.search.displayName",
                    defaultValue: "Search chat history"
                ),
                description: "Search the user's past conversations in this app. Returns matching conversations with conversation_id, title, last-updated date and matched excerpts. Use space-separated keywords in the user's language. Omit query to list the most recent conversations.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Space-separated keywords. A conversation ranks higher when it matches more keywords. Omit or leave empty to list recent conversations.")
                        ]),
                        "max_results": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of conversations to return, 1-\(maxSearchResultCount). Default \(defaultSearchResultCount).")
                        ])
                    ])
                ]),
                mcpServerID: serverID,
                mcpServerName: "chat_history",
                mcpServerURL: "",
                mcpToolName: searchFunctionName,
                requiresApproval: false,
                authorizationToken: ""
            ),
            AgentToolDefinition(
                functionName: readFunctionName,
                displayName: AppLocalizations.string(
                    "recallTool.read.displayName",
                    defaultValue: "Read chat history"
                ),
                description: "Read the transcript of one past conversation, identified by the exact conversation_id returned by chat_history_search. Long conversations are paginated; pass page (1-based) to read more.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "conversation_id": .object([
                            "type": .string("string"),
                            "description": .string("The conversation_id value from chat_history_search results.")
                        ]),
                        "page": .object([
                            "type": .string("integer"),
                            "description": .string("1-based page number of the transcript. Default 1.")
                        ])
                    ]),
                    "required": .array([.string("conversation_id")])
                ]),
                mcpServerID: serverID,
                mcpServerName: "chat_history",
                mcpServerURL: "",
                mcpToolName: readFunctionName,
                requiresApproval: false,
                authorizationToken: ""
            )
        ]

        return definitions.filter { !usedFunctionNames.contains($0.functionName) }
    }

    static func isRecallTool(_ tool: AgentToolDefinition) -> Bool {
        tool.mcpServerID == serverID
    }

    // MARK: - Execution

    static func execute(
        functionName: String,
        argumentsJSON: String,
        conversations: [AIConversation],
        excludedConversationIDs: Set<UUID>
    ) -> AgentToolCallResult {
        let arguments = RecallArguments(fromJSON: argumentsJSON)
        let candidates = conversations
            .filter { !excludedConversationIDs.contains($0.id) && $0.hasInformation }
            .sorted { $0.updatedAt > $1.updatedAt }

        switch functionName {
        case searchFunctionName:
            return AgentToolCallResult(
                content: searchResultText(arguments: arguments, candidates: candidates),
                isError: false
            )
        case readFunctionName:
            return readResult(arguments: arguments, candidates: candidates)
        default:
            return AgentToolCallResult(
                content: "Unknown chat history tool: \(functionName)",
                isError: true
            )
        }
    }

    // MARK: - Search

    private static func searchResultText(
        arguments: RecallArguments,
        candidates: [AIConversation]
    ) -> String {
        guard !candidates.isEmpty else {
            return "The user has no other stored conversations yet."
        }

        let limit = min(max(arguments.maxResults ?? defaultSearchResultCount, 1), maxSearchResultCount)
        let terms = queryTerms(from: arguments.query ?? "")

        guard !terms.isEmpty else {
            let lines = candidates.prefix(limit).enumerated().map { index, conversation in
                """
                [\(index + 1)] conversation_id: \(conversation.id.uuidString)
                    title: \(conversation.title)
                    updated: \(dateText(conversation.updatedAt)) · \(conversation.messages.count) messages
                """
            }
            return "Most recent conversations (newest first):\n\n" + lines.joined(separator: "\n")
        }

        let scored = candidates.compactMap { conversation -> (conversation: AIConversation, score: Int)? in
            guard let score = matchScore(for: conversation, terms: terms) else { return nil }
            return (conversation, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.conversation.updatedAt > rhs.conversation.updatedAt
        }
        .prefix(limit)

        guard !scored.isEmpty else {
            return "No past conversations matched \"\(terms.joined(separator: " "))\". Try fewer or different keywords, or omit query to list recent conversations."
        }

        let blocks = scored.enumerated().map { index, match -> String in
            var lines = [
                "[\(index + 1)] conversation_id: \(match.conversation.id.uuidString)",
                "    title: \(match.conversation.title)",
                "    updated: \(dateText(match.conversation.updatedAt))"
            ]

            let excerpts = matchedExcerpts(in: match.conversation, terms: terms)
            if !excerpts.isEmpty {
                lines.append("    matched excerpts:")
                lines.append(contentsOf: excerpts.map { "    - \($0)" })
            }
            return lines.joined(separator: "\n")
        }

        return "Found \(scored.count) matching conversation(s), best match first. Use chat_history_read with a conversation_id for the full transcript.\n\n"
            + blocks.joined(separator: "\n")
    }

    static func queryTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」『』")) }
            .filter { !$0.isEmpty }
    }

    /// Returns nil when no term matches. Conversations matching more distinct
    /// terms always rank above ones matching fewer, regardless of hit counts.
    private static func matchScore(for conversation: AIConversation, terms: [String]) -> Int? {
        var matchedTermCount = 0
        var score = 0

        for term in terms {
            var termMatched = false
            if found(term, in: conversation.title) {
                termMatched = true
                score += 5
            }

            var messageHits = 0
            for message in conversation.messages where messageHits < 5 {
                if segments(of: message).contains(where: { found(term, in: $0.text) }) {
                    messageHits += 1
                }
            }
            if messageHits > 0 {
                termMatched = true
                score += messageHits
            }

            if termMatched {
                matchedTermCount += 1
            }
        }

        guard matchedTermCount > 0 else { return nil }
        return matchedTermCount * 100 + score
    }

    private static func matchedExcerpts(in conversation: AIConversation, terms: [String]) -> [String] {
        var excerpts = [String]()

        for message in conversation.messages {
            guard excerpts.count < maxExcerptsPerConversation else { break }

            for segment in segments(of: message) {
                guard let range = firstRange(of: terms, in: segment.text) else { continue }
                excerpts.append("\(segment.label): \(excerpt(around: range, in: segment.text))")
                break
            }
        }

        return excerpts
    }

    private static func segments(of message: ChatMessage) -> [(label: String, text: String)] {
        var segments = [(label: String, text: String)]()
        if !message.content.isEmpty {
            segments.append((message.role, message.content))
        }
        if !message.imageContextDescription.isEmpty {
            segments.append(("image (hidden description)", message.imageContextDescription))
        }
        for attachment in message.fileAttachments where !attachment.extractedText.isEmpty {
            segments.append(("file \(attachment.name)", attachment.extractedText))
        }
        return segments
    }

    private static func firstRange(of terms: [String], in text: String) -> Range<String.Index>? {
        terms.lazy
            .compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func excerpt(around range: Range<String.Index>, in text: String) -> String {
        let start = text.index(
            range.lowerBound,
            offsetBy: -excerptPrefixCharacters,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            range.lowerBound,
            offsetBy: excerptSuffixCharacters,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        let collapsed = text[start..<end]
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let prefixMark = start > text.startIndex ? "…" : ""
        let suffixMark = end < text.endIndex ? "…" : ""
        return "\(prefixMark)\(collapsed)\(suffixMark)"
    }

    private static func found(_ term: String, in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Read

    private static func readResult(
        arguments: RecallArguments,
        candidates: [AIConversation]
    ) -> AgentToolCallResult {
        guard let identifier = arguments.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else {
            return AgentToolCallResult(
                content: "Missing conversation_id. Call chat_history_search first and pass the exact conversation_id from its results.",
                isError: true
            )
        }

        guard let conversation = conversation(withIdentifier: identifier, in: candidates) else {
            return AgentToolCallResult(
                content: "No conversation found for conversation_id \"\(identifier)\". Call chat_history_search to get valid IDs.",
                isError: true
            )
        }

        let pages = transcriptPages(for: conversation)
        guard !pages.isEmpty else {
            return AgentToolCallResult(
                content: "This conversation has no readable text content.",
                isError: true
            )
        }

        let page = arguments.page ?? 1
        guard page >= 1, page <= pages.count else {
            return AgentToolCallResult(
                content: "Page \(page) is out of range; this conversation has \(pages.count) page(s).",
                isError: true
            )
        }

        var header = """
        title: \(conversation.title)
        updated: \(dateText(conversation.updatedAt))
        page \(page) of \(pages.count)
        """
        if page < pages.count {
            header += " (call chat_history_read again with \"page\": \(page + 1) for more)"
        }

        return AgentToolCallResult(
            content: header + "\n---\n" + pages[page - 1],
            isError: false
        )
    }

    private static func conversation(
        withIdentifier identifier: String,
        in candidates: [AIConversation]
    ) -> AIConversation? {
        if let id = UUID(uuidString: identifier) {
            return candidates.first { $0.id == id }
        }

        let uppercasedPrefix = identifier.uppercased()
        let prefixMatches = candidates.filter { $0.id.uuidString.hasPrefix(uppercasedPrefix) }
        return prefixMatches.count == 1 ? prefixMatches[0] : nil
    }

    static func transcriptPages(for conversation: AIConversation) -> [String] {
        let lines = conversation.messages.compactMap { message -> String? in
            var parts = [String]()
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                parts.append(content)
            }
            if !message.imageAttachments.isEmpty {
                let description = message.imageContextDescription
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append(description.isEmpty
                    ? "[image attached]"
                    : "[image attached: \(String(description.prefix(200)))]")
            }
            for attachment in message.fileAttachments {
                parts.append("[file attached: \(attachment.name)]")
            }
            guard !parts.isEmpty else { return nil }

            let line = "\(message.role): \(parts.joined(separator: "\n"))"
            guard line.count > readPageCharacters else { return line }
            return String(line.prefix(readPageCharacters)) + "…"
        }

        var pages = [String]()
        var currentLines = [String]()
        var currentLength = 0

        for line in lines {
            if !currentLines.isEmpty, currentLength + line.count > readPageCharacters {
                pages.append(currentLines.joined(separator: "\n\n"))
                currentLines = []
                currentLength = 0
            }
            currentLines.append(line)
            currentLength += line.count + 2
        }
        if !currentLines.isEmpty {
            pages.append(currentLines.joined(separator: "\n\n"))
        }

        return pages
    }

    // MARK: - Helpers

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct RecallArguments {
        var query: String?
        var maxResults: Int?
        var conversationID: String?
        var page: Int?

        init(fromJSON json: String) {
            guard let data = json.data(using: .utf8),
                  case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                return
            }

            query = Self.string(object["query"])
            maxResults = Self.integer(object["max_results"])
            conversationID = Self.string(object["conversation_id"])
            page = Self.integer(object["page"])
        }

        private static func string(_ value: JSONValue?) -> String? {
            guard case .string(let string)? = value else { return nil }
            return string
        }

        private static func integer(_ value: JSONValue?) -> Int? {
            switch value {
            case .number(let number):
                return Int(number)
            case .string(let string):
                return Int(string.trimmingCharacters(in: .whitespaces))
            default:
                return nil
            }
        }
    }
}
