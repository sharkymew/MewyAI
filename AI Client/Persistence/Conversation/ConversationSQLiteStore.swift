import Foundation
import SQLite3

/// SQLite-backed conversation storage. The JSON payload keeps the existing
/// Codable model compatible while SQLite owns indexing, atomic writes, and search.
enum ConversationSQLiteStore {
    private static let databaseFileName = "Conversations.sqlite"
    private static let schemaVersion = 1
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private struct ConversationRecord {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let hasGeneratedTitle: Bool
        let isPinned: Bool
        let messageCount: Int
        let body: Data
        let searchCorpus: String
        let messageSearchCorpus: String
    }

    static func databaseExists(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard let url = databaseURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    static func isHealthy(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard databaseExists(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return false
        }

        return withDatabase(
            createsIfNeeded: false,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            scalarString(database, sql: "PRAGMA quick_check") == "ok"
                && (scalarInt(database, sql: "SELECT COUNT(*) FROM pragma_foreign_key_check") ?? 1) == 0
        } ?? false
    }

    static func loadConversations(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation]? {
        guard databaseExists(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return nil
        }

        return withDatabase(
            createsIfNeeded: false,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            guard let records = queryRecords(database, sql: """
                SELECT id, title, created_at, updated_at, has_generated_title, is_pinned,
                       message_count, body, search_corpus, message_search_corpus
                FROM conversations
                ORDER BY updated_at DESC, created_at DESC
                """) else {
                return nil
            }
            var conversations: [AIConversation] = []
            for record in records {
                if let conversation = decodeConversation(record) {
                    conversations.append(conversation)
                }
            }
            return conversations
        }
    }

    static func loadConversationList(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation]? {
        guard databaseExists(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return nil
        }

        return withDatabase(
            createsIfNeeded: false,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            prepare(database, sql: """
                SELECT id, title, created_at, updated_at, has_generated_title, is_pinned, message_count
                FROM conversations
                ORDER BY updated_at DESC, created_at DESC
                """).flatMap { statement in
                defer { sqlite3_finalize(statement) }
                var conversations: [AIConversation] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let id = uuid(at: 0, in: statement) else { continue }
                    conversations.append(AIConversation(
                        id: id,
                        title: string(at: 1, in: statement) ?? "",
                        messages: [],
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                        hasGeneratedTitle: sqlite3_column_int(statement, 4) != 0,
                        isPinned: sqlite3_column_int(statement, 5) != 0,
                        indexedMessageCount: Int(sqlite3_column_int64(statement, 6))
                    ))
                }
                return conversations
            }
        }
    }

    static func loadConversation(
        id: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> AIConversation? {
        guard databaseExists(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return nil
        }

        return withDatabase(
            createsIfNeeded: false,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            prepare(database, sql: """
                SELECT id, title, created_at, updated_at, has_generated_title, is_pinned,
                       message_count, body, search_corpus, message_search_corpus
                FROM conversations
                WHERE id = ?
                """).flatMap { statement in
                defer { sqlite3_finalize(statement) }
                guard bind(id.uuidString, at: 1, to: statement) else { return nil }
                guard sqlite3_step(statement) == SQLITE_ROW,
                      let record = record(from: statement) else {
                    return nil
                }
                return decodeConversation(record)
            }
        }
    }

    static func loadConversationsForStartup(
        selectedConversationID: UUID?,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [AIConversation]? {
        guard var conversations = loadConversationList(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ), !conversations.isEmpty else {
            return nil
        }

        let idToLoad = selectedConversationID.flatMap { selectedID in
            conversations.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? conversations.first?.id

        if let idToLoad,
           let loaded = loadConversation(
            id: idToLoad,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
           ), let index = conversations.firstIndex(where: { $0.id == idToLoad }) {
            conversations[index] = loaded
        }

        return conversations
    }

    @discardableResult
    static func saveConversations(
        _ conversations: [AIConversation],
        synchronize: Bool = false,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard !conversations.isEmpty else { return false }

        return withDatabase(
            createsIfNeeded: true,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            if synchronize, !execute(database, sql: "PRAGMA synchronous = FULL") {
                return false
            }
            defer {
                if synchronize {
                    _ = execute(database, sql: "PRAGMA synchronous = NORMAL")
                }
            }
            guard execute(database, sql: "BEGIN IMMEDIATE") else { return false }
            let didSave = conversations.allSatisfy { upsert($0, in: database) }
                && removeConversations(notIn: Set(conversations.map(\.id.uuidString)), database: database)
            guard didSave, execute(database, sql: "COMMIT") else {
                _ = execute(database, sql: "ROLLBACK")
                return false
            }
            return true
        } ?? false
    }

    @discardableResult
    static func saveConversation(
        _ conversation: AIConversation,
        synchronize: Bool = false,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        withDatabase(
            createsIfNeeded: true,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            if synchronize, !execute(database, sql: "PRAGMA synchronous = FULL") {
                return false
            }
            defer {
                if synchronize {
                    _ = execute(database, sql: "PRAGMA synchronous = NORMAL")
                }
            }
            guard execute(database, sql: "BEGIN IMMEDIATE") else { return false }
            guard upsert(conversation, in: database), execute(database, sql: "COMMIT") else {
                _ = execute(database, sql: "ROLLBACK")
                return false
            }
            return true
        } ?? false
    }

    /// Returns nil when SQLite has not been activated yet, so callers can use
    /// the legacy in-memory matcher during the one-time migration window.
    static func searchConversationIDs(
        query: String,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Set<UUID>? {
        guard databaseExists(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return nil
        }

        let terms = normalizedTerms(from: query)
        guard !terms.isEmpty else { return nil }

        return withDatabase(
            createsIfNeeded: false,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) { database in
            let longTerms = terms.filter { $0.unicodeScalars.count >= 3 }
            let candidates: [(UUID, String)]?
            if !longTerms.isEmpty, hasFTS(database) {
                let matchQuery = longTerms
                    .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                    .joined(separator: " AND ")
                candidates = querySearchRows(
                    database,
                    sql: """
                        SELECT conversations.id, conversations.search_corpus
                        FROM conversation_fts
                        JOIN conversations ON conversations.row_id = conversation_fts.rowid
                        WHERE conversation_fts MATCH ?
                        ORDER BY conversations.updated_at DESC, conversations.created_at DESC
                        """,
                    bind: matchQuery
                )
            } else {
                candidates = querySearchRows(
                    database,
                    sql: "SELECT id, search_corpus FROM conversations ORDER BY updated_at DESC, created_at DESC",
                    bind: nil
                )
            }

            return Set((candidates ?? []).compactMap { id, corpus in
                terms.allSatisfy { corpus.contains($0) } ? id : nil
            })
        }
    }

    private static func upsert(_ input: AIConversation, in database: OpaquePointer) -> Bool {
        if input.isIndexOnly {
            return updateIndexOnly(input, in: database)
        }

        let conversation = input.normalized
        guard let encoded = try? JSONEncoder().encode(conversation) else { return false }
        let body = ConversationStore.compressedStorageData(from: encoded)
        let messageCorpus = normalizedMessageCorpus(for: conversation)
        let searchCorpus = normalizedSearchText(conversation.title) + "\n" + messageCorpus

        guard let statement = prepare(database, sql: """
            INSERT INTO conversations (
                id, title, created_at, updated_at, has_generated_title, is_pinned,
                message_count, body, search_corpus, message_search_corpus
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                has_generated_title = excluded.has_generated_title,
                is_pinned = excluded.is_pinned,
                message_count = excluded.message_count,
                body = excluded.body,
                search_corpus = excluded.search_corpus,
                message_search_corpus = excluded.message_search_corpus
            """) else { return false }
        defer { sqlite3_finalize(statement) }

        return bind(conversation.id.uuidString, at: 1, to: statement)
            && bind(conversation.title, at: 2, to: statement)
            && sqlite3_bind_double(statement, 3, conversation.createdAt.timeIntervalSince1970) == SQLITE_OK
            && sqlite3_bind_double(statement, 4, conversation.updatedAt.timeIntervalSince1970) == SQLITE_OK
            && sqlite3_bind_int(statement, 5, conversation.hasGeneratedTitle ? 1 : 0) == SQLITE_OK
            && sqlite3_bind_int(statement, 6, conversation.isPinned ? 1 : 0) == SQLITE_OK
            && sqlite3_bind_int64(statement, 7, Int64(conversation.storedMessageCount)) == SQLITE_OK
            && bind(body, at: 8, to: statement)
            && bind(searchCorpus, at: 9, to: statement)
            && bind(messageCorpus, at: 10, to: statement)
            && sqlite3_step(statement) == SQLITE_DONE
    }

    private static func updateIndexOnly(_ conversation: AIConversation, in database: OpaquePointer) -> Bool {
        guard let statement = prepare(database, sql: """
            UPDATE conversations
            SET title = ?,
                created_at = ?,
                updated_at = ?,
                has_generated_title = ?,
                is_pinned = ?,
                message_count = ?,
                search_corpus = ? || char(10) || message_search_corpus
            WHERE id = ?
            """) else { return false }
        defer { sqlite3_finalize(statement) }

        let title = normalizedSearchText(conversation.title)
        guard bind(conversation.title, at: 1, to: statement),
              sqlite3_bind_double(statement, 2, conversation.createdAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_bind_double(statement, 3, conversation.updatedAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_bind_int(statement, 4, conversation.hasGeneratedTitle ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_int(statement, 5, conversation.isPinned ? 1 : 0) == SQLITE_OK,
              sqlite3_bind_int64(statement, 6, Int64(conversation.storedMessageCount)) == SQLITE_OK,
              bind(title, at: 7, to: statement),
              bind(conversation.id.uuidString, at: 8, to: statement),
              sqlite3_step(statement) == SQLITE_DONE else {
            return false
        }

        return sqlite3_changes(database) == 1
    }

    private static func removeConversations(notIn identifiers: Set<String>, database: OpaquePointer) -> Bool {
        guard let statement = prepare(database, sql: "DELETE FROM conversations WHERE id = ?") else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        guard let rows = querySearchRows(
            database,
            sql: "SELECT id, '' FROM conversations",
            bind: nil
        ) else { return false }

        for (id, _) in rows where !identifiers.contains(id.uuidString) {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            guard bind(id.uuidString, at: 1, to: statement), sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        return true
    }

    private static func decodeConversation(_ record: ConversationRecord) -> AIConversation? {
        let data = ConversationStore.decompressedStorageData(from: record.body)
        return try? JSONDecoder().decode(AIConversation.self, from: data).normalized
    }

    private static func record(from statement: OpaquePointer) -> ConversationRecord? {
        guard let id = uuid(at: 0, in: statement),
              let body = data(at: 7, in: statement) else {
            return nil
        }
        return ConversationRecord(
            id: id,
            title: string(at: 1, in: statement) ?? "",
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            hasGeneratedTitle: sqlite3_column_int(statement, 4) != 0,
            isPinned: sqlite3_column_int(statement, 5) != 0,
            messageCount: Int(sqlite3_column_int64(statement, 6)),
            body: body,
            searchCorpus: string(at: 8, in: statement) ?? "",
            messageSearchCorpus: string(at: 9, in: statement) ?? ""
        )
    }

    private static func queryRecords(_ database: OpaquePointer, sql: String) -> [ConversationRecord]? {
        guard let statement = prepare(database, sql: sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        var records: [ConversationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = record(from: statement) {
                records.append(record)
            }
        }
        return records
    }

    private static func querySearchRows(
        _ database: OpaquePointer,
        sql: String,
        bind value: String?
    ) -> [(UUID, String)]? {
        guard let statement = prepare(database, sql: sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        if let value, !bind(value, at: 1, to: statement) {
            return nil
        }

        var rows: [(UUID, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = uuid(at: 0, in: statement) else { continue }
            rows.append((id, string(at: 1, in: statement) ?? ""))
        }
        return rows
    }

    private static func normalizedMessageCorpus(for conversation: AIConversation) -> String {
        var values: [String] = []
        for message in conversation.allStoredMessages {
            values.append(message.content)
            values.append(message.imageContextDescription)
            if message.content.isEmpty {
                values.append(contentsOf: message.contentChunks)
            }
            for attachment in message.fileAttachments {
                values.append(attachment.name)
                values.append(attachment.extractedText)
            }
        }

        var normalizedValues: [String] = []
        for value in values {
            let normalized = normalizedSearchText(value)
            if !normalized.isEmpty {
                normalizedValues.append(normalized)
            }
        }
        return normalizedValues.joined(separator: "\n")
    }

    private static func normalizedTerms(from query: String) -> [String] {
        var terms: [String] = []
        for part in query.split(whereSeparator: \.isWhitespace) {
            let normalized = normalizedSearchText(String(part))
            if !normalized.isEmpty {
                terms.append(normalized)
            }
        }
        return terms
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    private static func databaseURL(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) -> URL? {
        let directory = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return directory?.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    private static func withDatabase<T>(
        createsIfNeeded: Bool,
        fileManager: FileManager,
        applicationSupportURL: URL?,
        _ body: @MainActor (OpaquePointer) -> T?
    ) -> T? {
        guard let url = databaseURL(fileManager: fileManager, applicationSupportURL: applicationSupportURL) else {
            return nil
        }

        if !createsIfNeeded, !fileManager.fileExists(atPath: url.path) {
            return nil
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        } catch {
            return nil
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        guard configure(database), migrateIfNeeded(database) else { return nil }
        applyCompleteFileProtection(to: url, fileManager: fileManager)
        return body(database)
    }

    private static func configure(_ database: OpaquePointer) -> Bool {
        execute(database, sql: "PRAGMA foreign_keys = ON")
            && execute(database, sql: "PRAGMA journal_mode = WAL")
            && execute(database, sql: "PRAGMA synchronous = NORMAL")
            && execute(database, sql: "PRAGMA busy_timeout = 3000")
    }

    private static func migrateIfNeeded(_ database: OpaquePointer) -> Bool {
        guard let version = scalarInt(database, sql: "PRAGMA user_version") else { return false }
        if version > schemaVersion { return false }
        guard version == 0 else { return true }

        let schema = [
            """
            CREATE TABLE IF NOT EXISTS conversations (
                row_id INTEGER PRIMARY KEY,
                id TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                has_generated_title INTEGER NOT NULL CHECK(has_generated_title IN (0, 1)),
                is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),
                message_count INTEGER NOT NULL CHECK(message_count >= 0),
                body BLOB NOT NULL,
                search_corpus TEXT NOT NULL,
                message_search_corpus TEXT NOT NULL
            ) STRICT
            """,
            "CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC, created_at DESC)",
            "CREATE INDEX IF NOT EXISTS idx_conversations_pinned_updated ON conversations(updated_at DESC, created_at DESC) WHERE is_pinned = 1"
        ]

        guard execute(database, sql: "BEGIN IMMEDIATE"), schema.allSatisfy({ execute(database, sql: $0) }) else {
            _ = execute(database, sql: "ROLLBACK")
            return false
        }

        let hasSearch = createFTSIfAvailable(database)
        let didSetVersion = execute(database, sql: "PRAGMA user_version = \(schemaVersion)")
        guard didSetVersion, execute(database, sql: "COMMIT") else {
            _ = execute(database, sql: "ROLLBACK")
            return false
        }

        if !hasSearch {
            return true
        }
        return true
    }

    private static func createFTSIfAvailable(_ database: OpaquePointer) -> Bool {
        let statements = [
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS conversation_fts USING fts5(
                search_corpus,
                content = 'conversations',
                content_rowid = 'row_id',
                tokenize = 'trigram'
            )
            """,
            """
            CREATE TRIGGER IF NOT EXISTS conversations_fts_insert
            AFTER INSERT ON conversations BEGIN
                INSERT INTO conversation_fts(rowid, search_corpus)
                VALUES (new.row_id, new.search_corpus);
            END
            """,
            """
            CREATE TRIGGER IF NOT EXISTS conversations_fts_delete
            AFTER DELETE ON conversations BEGIN
                INSERT INTO conversation_fts(conversation_fts, rowid, search_corpus)
                VALUES ('delete', old.row_id, old.search_corpus);
            END
            """,
            """
            CREATE TRIGGER IF NOT EXISTS conversations_fts_update
            AFTER UPDATE OF search_corpus ON conversations BEGIN
                INSERT INTO conversation_fts(conversation_fts, rowid, search_corpus)
                VALUES ('delete', old.row_id, old.search_corpus);
                INSERT INTO conversation_fts(rowid, search_corpus)
                VALUES (new.row_id, new.search_corpus);
            END
            """
        ]
        return statements.allSatisfy { execute(database, sql: $0) }
    }

    private static func hasFTS(_ database: OpaquePointer) -> Bool {
        scalarInt(
            database,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'conversation_fts'"
        ).map { $0 > 0 } ?? false
    }

    private static func execute(_ database: OpaquePointer, sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func prepare(_ database: OpaquePointer, sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    private static func scalarInt(_ database: OpaquePointer, sql: String) -> Int? {
        guard let statement = prepare(database, sql: sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func scalarString(_ database: OpaquePointer, sql: String) -> String? {
        guard let statement = prepare(database, sql: sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return string(at: 0, in: statement)
    }

    private static func bind(_ value: String, at index: Int32, to statement: OpaquePointer) -> Bool {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK
    }

    private static func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) -> Bool {
        value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient) == SQLITE_OK
        }
    }

    private static func string(at index: Int32, in statement: OpaquePointer) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private static func data(at index: Int32, in statement: OpaquePointer) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private static func uuid(at index: Int32, in statement: OpaquePointer) -> UUID? {
        string(at: index, in: statement).flatMap(UUID.init(uuidString:))
    }

    private static func applyCompleteFileProtection(to databaseURL: URL, fileManager: FileManager) {
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
    }
}
