import XCTest
@testable import MewyAI

@MainActor
final class ConversationStoreTests: XCTestCase {
    func testChatMessageDecodeDefaultsAndNormalize() throws {
        let data = """
        {
          "role": "assistant",
          "contentChunks": ["Hello", " world"],
          "reasoningContent": "kept reasoning",
          "reasoningChunks": ["old reasoning"],
          "toolExchanges": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "assistantContent": "",
              "reasoningContent": "",
              "toolCalls": [],
              "toolResults": []
            }
          ]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: data).normalized

        XCTAssertEqual(message.role, "assistant")
        XCTAssertEqual(message.content, "Hello world")
        XCTAssertTrue(message.contentChunks.isEmpty)
        XCTAssertEqual(message.reasoningContent, "kept reasoning")
        XCTAssertTrue(message.reasoningChunks.isEmpty)
        XCTAssertTrue(message.toolExchanges.isEmpty)
        XCTAssertTrue(message.knowledgeCitations.isEmpty)
        XCTAssertFalse(message.isContentCleared)
    }

    func testConversationDecodeDefaultsBranchDividers() throws {
        let data = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Legacy",
          "messages": []
        }
        """.data(using: .utf8)!

        let conversation = try JSONDecoder().decode(AIConversation.self, from: data)

        XCTAssertTrue(conversation.branchDividers.isEmpty)
        XCTAssertTrue(conversation.activeKnowledgeBaseIDs.isEmpty)
    }

    func testKnowledgeBaseSelectionAndCitationsRoundTrip() throws {
        let knowledgeBaseID = UUID()
        let citation = KnowledgeCitation(
            knowledgeBaseID: knowledgeBaseID,
            knowledgeBaseName: "Docs",
            documentID: UUID(),
            documentName: "Guide",
            chunkID: UUID(),
            chunkIndex: 3,
            location: "Page 4",
            excerpt: "excerpt",
            similarity: 0.82
        )
        let conversation = AIConversation(
            messages: [
                ChatMessage(role: "assistant", content: "answer", knowledgeCitations: [citation])
            ],
            activeKnowledgeBaseIDs: [knowledgeBaseID]
        )

        let decoded = try JSONDecoder().decode(
            AIConversation.self,
            from: JSONEncoder().encode(conversation)
        )

        XCTAssertEqual(decoded.activeKnowledgeBaseIDs, [knowledgeBaseID])
        XCTAssertEqual(decoded.messages.first?.knowledgeCitations, [citation])
    }

    func testConversationBranchDividersRoundTrip() throws {
        let messageID = UUID()
        let conversation = AIConversation(
            messages: [
                ChatMessage(id: messageID, role: "user", content: "branch point")
            ],
            branchDividers: [
                ConversationBranchDivider(afterMessageID: messageID, sourceMessageName: "branch point")
            ]
        )

        let decoded = try JSONDecoder().decode(
            AIConversation.self,
            from: JSONEncoder().encode(conversation)
        )

        XCTAssertEqual(decoded.branchDividers.count, 1)
        XCTAssertEqual(decoded.branchDividers.first?.afterMessageID, messageID)
        XCTAssertEqual(decoded.branchDividers.first?.sourceMessageName, "branch point")
    }

    func testClearedGeneratedContentRoundTripsWithoutStoredContent() throws {
        let usage = ChatUsage(
            inputTokens: 12,
            outputTokens: 8,
            totalTokens: 20,
            cacheReadInputTokens: 0,
            modelName: "test-model",
            configurationID: UUID()
        )
        var message = ChatMessage(
            role: "assistant",
            content: "answer",
            contentChunks: ["chunk"],
            reasoningContent: "reasoning",
            reasoningChunks: ["reason"],
            toolExchanges: [
                ChatToolExchange(
                    toolCalls: [
                        ChatToolCall(
                            id: "call-1",
                            name: "search",
                            displayName: "Search",
                            argumentsJSON: "{}"
                        )
                    ]
                )
            ],
            usage: usage,
            isReasoningExpanded: true
        )

        message.clearGeneratedContent()
        let decoded = try JSONDecoder().decode(
            ChatMessage.self,
            from: JSONEncoder().encode(message)
        )

        XCTAssertTrue(decoded.isContentCleared)
        XCTAssertEqual(decoded.content, "")
        XCTAssertEqual(decoded.contentChunks, [])
        XCTAssertEqual(decoded.reasoningContent, "")
        XCTAssertEqual(decoded.reasoningChunks, [])
        XCTAssertEqual(decoded.toolExchanges, [])
        XCTAssertEqual(decoded.knowledgeCitations, [])
        XCTAssertNil(decoded.usage)
        XCTAssertFalse(decoded.isReasoningExpanded)
    }

    func testConversationNormalizeFiltersInvalidRevisionGroups() {
        let userID = UUID()
        let validRevision = ChatMessageRevision(messages: [
            ChatMessage(id: userID, role: "user", content: "", contentChunks: ["edited"])
        ])
        let invalidRevision = ChatMessageRevision(messages: [
            ChatMessage(role: "assistant", content: "orphan")
        ])
        let conversation = AIConversation(
            messages: [
                ChatMessage(id: userID, role: "user", content: "current")
            ],
            messageRevisionGroups: [
                ChatMessageRevisionGroup(
                    id: userID,
                    selectedRevisionID: invalidRevision.id,
                    revisions: [invalidRevision, validRevision]
                )
            ]
        ).normalized

        XCTAssertEqual(conversation.messageRevisionGroups.count, 1)
        XCTAssertEqual(conversation.messageRevisionGroups[0].revisions, [validRevision.normalized])
        XCTAssertEqual(conversation.messageRevisionGroups[0].selectedRevisionID, validRevision.id)
    }

    func testLegacyImageAttachmentDataURLDecodesMimeType() throws {
        let data = """
        {
          "role": "user",
          "content": "image",
          "imageAttachments": [
            { "dataURL": "data:image/png;base64,AAAA" }
          ]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.imageAttachments.count, 1)
        XCTAssertEqual(message.imageAttachments[0].mimeType, "image/png")
        XCTAssertEqual(message.imageAttachments[0].byteCount, 0)
    }

    func testChatMessageWithoutUsageDecodesToNil() throws {
        let data = """
        {
          "role": "assistant",
          "content": "legacy message"
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertNil(message.usage)
    }

    func testChatMessageUsageRoundTrips() throws {
        let usage = ChatUsage(
            inputTokens: 120,
            outputTokens: 45,
            totalTokens: 165,
            cacheReadInputTokens: 30,
            modelName: "deepseek-v4-pro",
            configurationID: UUID()
        )
        let message = ChatMessage(role: "assistant", content: "hi", usage: usage)

        let decoded = try JSONDecoder().decode(
            ChatMessage.self,
            from: JSONEncoder().encode(message)
        )

        XCTAssertEqual(decoded.usage, usage)
        XCTAssertEqual(decoded.normalized.usage, usage)
    }

    func testStorageDataCompressionRoundTrip() throws {
        let conversations = [
            AIConversation(messages: (0..<50).map { index in
                ChatMessage(role: index.isMultiple(of: 2) ? "user" : "assistant",
                            content: "Message body number \(index) with enough repeated text to compress.")
            })
        ]
        let json = try JSONEncoder().encode(conversations)

        let stored = ConversationStore.compressedStorageData(from: json)

        XCTAssertLessThan(stored.count, json.count / 2)
        XCTAssertEqual(ConversationStore.decompressedStorageData(from: stored), json)
    }

    func testDecompressedStorageDataPassesThroughLegacyPlainJSON() {
        let json = Data("[{\"title\":\"legacy plain conversations\"}]".utf8)

        XCTAssertEqual(ConversationStore.decompressedStorageData(from: json), json)
    }

    func testCompressedStorageDataKeepsIncompressibleDataIntact() {
        let tiny = Data("[]".utf8)

        let stored = ConversationStore.compressedStorageData(from: tiny)

        XCTAssertEqual(stored, tiny)
        XCTAssertEqual(ConversationStore.decompressedStorageData(from: stored), tiny)
    }

    func testSaveConversationsWritesSplitIndexAndConversationFiles() throws {
        let storageURL = try makeTemporaryStorageURL()
        let older = AIConversation(
            id: UUID(),
            title: "Older",
            messages: [ChatMessage(role: "user", content: "old")],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = AIConversation(
            id: UUID(),
            title: "Newer",
            messages: [ChatMessage(role: "assistant", content: "new")],
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertTrue(ConversationStore.saveConversations(
            [older, newer],
            applicationSupportURL: storageURL
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL(in: storageURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationURL(newer.id, in: storageURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationURL(older.id, in: storageURL).path))

        let loaded = ConversationStore.loadConversations(applicationSupportURL: storageURL)

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.first?.messages.first?.content, "new")
    }

    func testLoadConversationListReadsIndexOnlyMetadata() throws {
        let storageURL = try makeTemporaryStorageURL()
        let older = AIConversation(
            id: UUID(),
            title: "Older",
            messages: [ChatMessage(role: "user", content: "old")],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = AIConversation(
            id: UUID(),
            title: "Newer",
            messages: [
                ChatMessage(role: "user", content: "new prompt"),
                ChatMessage(role: "assistant", content: "new answer")
            ],
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            hasGeneratedTitle: true,
            isPinned: true
        )

        XCTAssertTrue(ConversationStore.saveConversations(
            [older, newer],
            applicationSupportURL: storageURL
        ))

        let loaded = ConversationStore.loadConversationList(applicationSupportURL: storageURL)

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertTrue(loaded.allSatisfy(\.isIndexOnly))
        XCTAssertEqual(loaded[0].title, "Newer")
        XCTAssertEqual(loaded[0].storedMessageCount, 2)
        XCTAssertTrue(loaded[0].hasInformation)
        XCTAssertTrue(loaded[0].messages.isEmpty)
        XCTAssertTrue(loaded[0].hasGeneratedTitle)
        XCTAssertTrue(loaded[0].isPinned)
        XCTAssertEqual(loaded[1].storedMessageCount, 1)
    }

    func testLoadConversationsForStartupLoadsOnlySelectedConversationBody() throws {
        let storageURL = try makeTemporaryStorageURL()
        let older = AIConversation(
            id: UUID(),
            title: "Older",
            messages: [ChatMessage(role: "user", content: "selected body")],
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = AIConversation(
            id: UUID(),
            title: "Newer",
            messages: [ChatMessage(role: "assistant", content: "index only body")],
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [older, newer],
            applicationSupportURL: storageURL
        ))

        let loaded = ConversationStore.loadConversationsForStartup(
            selectedConversationID: older.id,
            applicationSupportURL: storageURL
        )

        let selectedConversation = try XCTUnwrap(loaded.first { $0.id == older.id })
        let indexedConversation = try XCTUnwrap(loaded.first { $0.id == newer.id })

        XCTAssertFalse(selectedConversation.isIndexOnly)
        XCTAssertEqual(selectedConversation.messages.first?.content, "selected body")
        XCTAssertTrue(indexedConversation.isIndexOnly)
        XCTAssertTrue(indexedConversation.messages.isEmpty)
        XCTAssertEqual(indexedConversation.storedMessageCount, 1)
    }

    func testLoadConversationReadsSingleSplitConversationBody() throws {
        let storageURL = try makeTemporaryStorageURL()
        let conversation = AIConversation(
            id: UUID(),
            title: "Single",
            messages: [ChatMessage(role: "user", content: "single body")]
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [conversation],
            applicationSupportURL: storageURL
        ))

        let loaded = try XCTUnwrap(ConversationStore.loadConversation(
            id: conversation.id,
            applicationSupportURL: storageURL
        ))

        XCTAssertFalse(loaded.isIndexOnly)
        XCTAssertEqual(loaded.messages.first?.content, "single body")
    }

    func testLoadConversationPreservesBranchDividers() throws {
        let storageURL = try makeTemporaryStorageURL()
        let messageID = UUID()
        let conversation = AIConversation(
            id: UUID(),
            title: "Branched",
            messages: [
                ChatMessage(id: messageID, role: "assistant", content: "source answer")
            ],
            branchedFromConversationID: UUID(),
            branchedFromMessageID: messageID,
            branchDividers: [
                ConversationBranchDivider(afterMessageID: messageID, sourceMessageName: "source answer")
            ]
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [conversation],
            applicationSupportURL: storageURL
        ))

        let loaded = try XCTUnwrap(ConversationStore.loadConversation(
            id: conversation.id,
            applicationSupportURL: storageURL
        ))

        XCTAssertEqual(loaded.branchedFromConversationID, conversation.branchedFromConversationID)
        XCTAssertEqual(loaded.branchedFromMessageID, messageID)
        XCTAssertEqual(loaded.branchDividers.count, 1)
        XCTAssertEqual(loaded.branchDividers.first?.afterMessageID, messageID)
        XCTAssertEqual(loaded.branchDividers.first?.sourceMessageName, "source answer")
    }

    func testLoadConversationsMigratesLegacySingleFileToSplitStorage() throws {
        let storageURL = try makeTemporaryStorageURL()
        let conversation = AIConversation(
            id: UUID(),
            title: "Legacy",
            messages: [ChatMessage(role: "user", content: "legacy body")]
        )
        let legacyData = try JSONEncoder().encode([conversation])
        try legacyData.write(to: storageURL.appendingPathComponent("Conversations.json"))

        let loaded = ConversationStore.loadConversations(applicationSupportURL: storageURL)

        XCTAssertEqual(loaded.map(\.id), [conversation.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL(in: storageURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationURL(conversation.id, in: storageURL).path))
    }

    func testSaveConversationUpdatesOnlyTargetConversationFile() throws {
        let storageURL = try makeTemporaryStorageURL()
        let first = AIConversation(
            id: UUID(),
            title: "First",
            messages: [ChatMessage(role: "user", content: "first")],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let second = AIConversation(
            id: UUID(),
            title: "Second",
            messages: [ChatMessage(role: "user", content: "second")],
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [first, second],
            applicationSupportURL: storageURL
        ))
        let secondDataBefore = try Data(contentsOf: conversationURL(second.id, in: storageURL))

        var updatedFirst = first
        updatedFirst.messages.append(ChatMessage(role: "assistant", content: "updated"))
        updatedFirst.updatedAt = Date(timeIntervalSince1970: 3)

        XCTAssertTrue(ConversationStore.saveConversation(
            updatedFirst,
            in: [updatedFirst, second],
            applicationSupportURL: storageURL
        ))

        let secondDataAfter = try Data(contentsOf: conversationURL(second.id, in: storageURL))
        let loaded = ConversationStore.loadConversations(applicationSupportURL: storageURL)

        XCTAssertEqual(secondDataAfter, secondDataBefore)
        XCTAssertEqual(loaded.first?.id, updatedFirst.id)
        XCTAssertEqual(loaded.first?.messages.last?.content, "updated")
    }

    func testSavingIndexOnlyConversationsPreservesExistingConversationFiles() throws {
        let storageURL = try makeTemporaryStorageURL()
        let first = AIConversation(
            id: UUID(),
            title: "First",
            messages: [ChatMessage(role: "user", content: "first body")],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let second = AIConversation(
            id: UUID(),
            title: "Second",
            messages: [ChatMessage(role: "assistant", content: "second body")],
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [first, second],
            applicationSupportURL: storageURL
        ))
        let firstDataBefore = try Data(contentsOf: conversationURL(first.id, in: storageURL))
        let secondDataBefore = try Data(contentsOf: conversationURL(second.id, in: storageURL))

        var indexOnlyConversations = ConversationStore.loadConversationList(applicationSupportURL: storageURL)
        let secondIndex = try XCTUnwrap(indexOnlyConversations.firstIndex { $0.id == second.id })
        indexOnlyConversations[secondIndex].isPinned = true

        XCTAssertTrue(ConversationStore.saveConversations(
            indexOnlyConversations,
            applicationSupportURL: storageURL
        ))

        XCTAssertEqual(try Data(contentsOf: conversationURL(first.id, in: storageURL)), firstDataBefore)
        XCTAssertEqual(try Data(contentsOf: conversationURL(second.id, in: storageURL)), secondDataBefore)

        let loadedSecond = try XCTUnwrap(ConversationStore.loadConversation(
            id: second.id,
            applicationSupportURL: storageURL
        ))
        XCTAssertEqual(loadedSecond.messages.first?.content, "second body")

        let updatedIndex = ConversationStore.loadConversationList(applicationSupportURL: storageURL)
        XCTAssertTrue(updatedIndex.first { $0.id == second.id }?.isPinned == true)
    }

    func testSavingIndexOnlySingleConversationPreservesExistingConversationFile() throws {
        let storageURL = try makeTemporaryStorageURL()
        let conversation = AIConversation(
            id: UUID(),
            title: "Original",
            messages: [ChatMessage(role: "user", content: "original body")]
        )
        XCTAssertTrue(ConversationStore.saveConversations(
            [conversation],
            applicationSupportURL: storageURL
        ))
        let dataBefore = try Data(contentsOf: conversationURL(conversation.id, in: storageURL))

        var indexOnlyConversation = try XCTUnwrap(
            ConversationStore.loadConversationList(applicationSupportURL: storageURL).first
        )
        indexOnlyConversation.title = "Renamed"

        XCTAssertTrue(ConversationStore.saveConversation(
            indexOnlyConversation,
            in: [indexOnlyConversation],
            applicationSupportURL: storageURL
        ))

        XCTAssertEqual(try Data(contentsOf: conversationURL(conversation.id, in: storageURL)), dataBefore)

        let loadedConversation = try XCTUnwrap(ConversationStore.loadConversation(
            id: conversation.id,
            applicationSupportURL: storageURL
        ))
        XCTAssertEqual(loadedConversation.messages.first?.content, "original body")

        let loadedIndex = try XCTUnwrap(
            ConversationStore.loadConversationList(applicationSupportURL: storageURL).first
        )
        XCTAssertEqual(loadedIndex.title, "Renamed")
    }

    func testSaveConversationsRemovesStaleSplitConversationFiles() throws {
        let storageURL = try makeTemporaryStorageURL()
        let retained = AIConversation(id: UUID(), title: "Retained")
        let removed = AIConversation(id: UUID(), title: "Removed")
        XCTAssertTrue(ConversationStore.saveConversations(
            [retained, removed],
            applicationSupportURL: storageURL
        ))

        XCTAssertTrue(ConversationStore.saveConversations(
            [retained],
            applicationSupportURL: storageURL
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationURL(retained.id, in: storageURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversationURL(removed.id, in: storageURL).path))
    }

    private func makeTemporaryStorageURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func conversationsDirectoryURL(in storageURL: URL) -> URL {
        storageURL.appendingPathComponent("Conversations", isDirectory: true)
    }

    private func indexURL(in storageURL: URL) -> URL {
        conversationsDirectoryURL(in: storageURL)
            .appendingPathComponent("Index.json", isDirectory: false)
    }

    private func conversationURL(_ id: UUID, in storageURL: URL) -> URL {
        conversationsDirectoryURL(in: storageURL)
            .appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }
}
