import XCTest
@testable import MewyAI

@MainActor
final class ConversationPersistenceCoordinatorTests: XCTestCase {
    func testStoredConversationsFiltersPrivateConversation() {
        let privateID = UUID()
        let conversations = [
            AIConversation(id: UUID(), title: "Stored"),
            AIConversation(id: privateID, title: "Private")
        ]

        let stored = ConversationPersistenceCoordinator.storedConversations(
            from: conversations,
            privateConversationID: privateID
        )

        XCTAssertEqual(stored.map(\.title), ["Stored"])
    }

    func testDeleteConversationReplacesOnlyConversation() {
        let deletedID = UUID()
        let replacement = AIConversation(id: UUID(), title: "Replacement")
        var conversations = [
            AIConversation(id: deletedID, title: "Deleted")
        ]

        let result = ConversationPersistenceCoordinator.deleteConversation(
            deletedID,
            selectedConversationID: deletedID,
            conversations: &conversations,
            replacementConversation: replacement
        )

        XCTAssertEqual(conversations, [replacement])
        XCTAssertEqual(result.selectedConversation, replacement)
        XCTAssertTrue(result.didReplaceWithNewConversation)
    }

    func testDeleteSelectedConversationSelectsFirstRemainingConversation() {
        let deletedID = UUID()
        let next = AIConversation(id: UUID(), title: "Next")
        let other = AIConversation(id: UUID(), title: "Other")
        var conversations = [
            AIConversation(id: deletedID, title: "Deleted"),
            next,
            other
        ]

        let result = ConversationPersistenceCoordinator.deleteConversation(
            deletedID,
            selectedConversationID: deletedID,
            conversations: &conversations
        )

        XCTAssertEqual(conversations.map(\.id), [next.id, other.id])
        XCTAssertEqual(result.selectedConversation, next)
        XCTAssertFalse(result.didReplaceWithNewConversation)
    }

    func testDeleteUnselectedConversationKeepsCurrentSelection() {
        let selectedID = UUID()
        let deletedID = UUID()
        let selected = AIConversation(id: selectedID, title: "Selected")
        var conversations = [
            selected,
            AIConversation(id: deletedID, title: "Deleted")
        ]

        let result = ConversationPersistenceCoordinator.deleteConversation(
            deletedID,
            selectedConversationID: selectedID,
            conversations: &conversations
        )

        XCTAssertEqual(conversations, [selected])
        XCTAssertNil(result.selectedConversation)
        XCTAssertFalse(result.didReplaceWithNewConversation)
    }

    func testEnsureCurrentConversationCreatesWhenSelectionIsMissing() {
        let existing = AIConversation(id: UUID(), title: "Existing")
        let replacement = AIConversation(id: UUID(), title: "Replacement")
        var conversations = [existing]
        var selectedConversationID: UUID?

        let result = ConversationPersistenceCoordinator.ensureCurrentConversation(
            conversations: &conversations,
            selectedConversationID: &selectedConversationID,
            replacementConversation: replacement
        )

        XCTAssertEqual(result, .init(conversation: replacement, didCreate: true))
        XCTAssertEqual(conversations.map(\.id), [replacement.id, existing.id])
        XCTAssertEqual(selectedConversationID, replacement.id)
    }

    func testEnsureCurrentConversationDoesNotMutateValidSelection() {
        let selected = AIConversation(id: UUID(), title: "Selected")
        var conversations = [selected]
        var selectedConversationID: UUID? = selected.id

        let result = ConversationPersistenceCoordinator.ensureCurrentConversation(
            conversations: &conversations,
            selectedConversationID: &selectedConversationID
        )

        XCTAssertEqual(result, .init(conversation: nil, didCreate: false))
        XCTAssertEqual(conversations, [selected])
        XCTAssertEqual(selectedConversationID, selected.id)
    }

    func testRenameConversationNormalizesTitleAndMarksGenerated() {
        let id = UUID()
        var conversations = [
            AIConversation(id: id, title: "Old", hasGeneratedTitle: false)
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.renameConversation(
            id: id,
            title: "  New Title  ",
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].title, "New Title")
        XCTAssertTrue(conversations[0].hasGeneratedTitle)
    }

    func testToggleConversationPinFlipsPinState() {
        let id = UUID()
        var conversations = [
            AIConversation(id: id, title: "Pinned", isPinned: false)
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.toggleConversationPin(
            id: id,
            conversations: &conversations
        ))

        XCTAssertTrue(conversations[0].isPinned)
    }

    func testSynchronizeSelectedConversationSnapshotUpdatesMessagesCapsulesAndRevisionSnapshot() {
        let userMessageID = UUID()
        let selectedRevisionID = UUID()
        let conversationID = UUID()
        let skillID = UUID()
        let mcpServerID = UUID()
        let oldMessages = [
            ChatMessage(id: userMessageID, role: "user", content: "old"),
            ChatMessage(role: "assistant", content: "old answer")
        ]
        let newMessages = [
            ChatMessage(id: userMessageID, role: "user", content: "new"),
            ChatMessage(role: "assistant", content: "new answer")
        ]
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: selectedRevisionID,
            revisions: [
                ChatMessageRevision(id: selectedRevisionID, messages: oldMessages)
            ]
        )
        let originalUpdatedAt = Date(timeIntervalSince1970: 1)
        let refreshedAt = Date(timeIntervalSince1970: 2)
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: oldMessages,
                messageRevisionGroups: [revisionGroup],
                updatedAt: originalUpdatedAt
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.synchronizeSelectedConversationSnapshot(
            conversations: &conversations,
            selectedConversationID: conversationID,
            messages: newMessages,
            activeSkillIDs: [skillID],
            activeMCPServerIDs: [mcpServerID],
            refreshesUpdatedAt: true,
            date: refreshedAt
        ))

        XCTAssertEqual(conversations[0].messages, newMessages)
        XCTAssertEqual(conversations[0].activeSkillIDs, [skillID])
        XCTAssertEqual(conversations[0].activeMCPServerIDs, [mcpServerID])
        XCTAssertEqual(conversations[0].updatedAt, refreshedAt)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            newMessages
        )
    }

    func testSynchronizeSelectedConversationSnapshotReturnsFalseForMissingSelection() {
        var conversations = [
            AIConversation(messages: [ChatMessage(role: "user", content: "old")])
        ]

        XCTAssertFalse(ConversationPersistenceCoordinator.synchronizeSelectedConversationSnapshot(
            conversations: &conversations,
            selectedConversationID: UUID(),
            messages: [ChatMessage(role: "user", content: "new")],
            activeSkillIDs: [],
            activeMCPServerIDs: [],
            refreshesUpdatedAt: true
        ))

        XCTAssertEqual(conversations[0].messages[0].content, "old")
    }

    func testPrepareStoredConversationForPersistenceUpdatesRevisionSnapshotAndDate() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let originalMessages = [
            ChatMessage(id: userMessageID, role: "user", content: "old")
        ]
        let currentMessages = [
            ChatMessage(id: userMessageID, role: "user", content: "new"),
            ChatMessage(role: "assistant", content: "answer")
        ]
        let revision = ChatMessageRevision(messages: originalMessages)
        let originalUpdatedAt = Date(timeIntervalSince1970: 1)
        let refreshedAt = Date(timeIntervalSince1970: 2)
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: currentMessages,
                messageRevisionGroups: [
                    ChatMessageRevisionGroup(
                        id: userMessageID,
                        selectedRevisionID: revision.id,
                        revisions: [revision]
                    )
                ],
                updatedAt: originalUpdatedAt
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.prepareStoredConversationForPersistence(
            conversationID,
            conversations: &conversations,
            refreshesUpdatedAt: true,
            date: refreshedAt
        ))

        XCTAssertEqual(conversations[0].updatedAt, refreshedAt)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            currentMessages
        )
    }

    func testPrepareStoredConversationForPersistenceRejectsMissingAndIndexOnlyConversations() {
        let indexOnlyID = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 1)
        var conversations = [
            AIConversation(
                id: indexOnlyID,
                messages: [],
                updatedAt: originalUpdatedAt,
                indexedMessageCount: 3
            )
        ]

        XCTAssertFalse(ConversationPersistenceCoordinator.prepareStoredConversationForPersistence(
            UUID(),
            conversations: &conversations,
            refreshesUpdatedAt: true,
            date: Date(timeIntervalSince1970: 2)
        ))
        XCTAssertFalse(ConversationPersistenceCoordinator.prepareStoredConversationForPersistence(
            indexOnlyID,
            conversations: &conversations,
            refreshesUpdatedAt: true,
            date: Date(timeIntervalSince1970: 2)
        ))
        XCTAssertEqual(conversations[0].updatedAt, originalUpdatedAt)
    }

    func testMessageRevisionNavigationStateReturnsCurrentIndexAndCount() {
        let conversationID = UUID()
        let messageID = UUID()
        let firstRevisionID = UUID()
        let secondRevisionID = UUID()
        let conversations = [
            AIConversation(
                id: conversationID,
                messageRevisionGroups: [
                    ChatMessageRevisionGroup(
                        id: messageID,
                        selectedRevisionID: secondRevisionID,
                        revisions: [
                            ChatMessageRevision(id: firstRevisionID, messages: []),
                            ChatMessageRevision(id: secondRevisionID, messages: [])
                        ]
                    )
                ]
            )
        ]

        let state = ConversationPersistenceCoordinator.messageRevisionNavigationState(
            for: messageID,
            selectedConversationID: conversationID,
            conversations: conversations
        )

        XCTAssertEqual(state, MessageRevisionNavigationState(currentIndex: 1, count: 2))
    }

    func testCreateMessageRevisionCreatesNewGroup() {
        let conversationID = UUID()
        let messageID = UUID()
        let previousMessages = [
            ChatMessage(id: messageID, role: "user", content: "old")
        ]
        let newMessages = [
            ChatMessage(id: messageID, role: "user", content: "new")
        ]
        var conversations = [
            AIConversation(id: conversationID, messages: newMessages)
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.createMessageRevision(
            for: messageID,
            selectedConversationID: conversationID,
            conversations: &conversations,
            previousMessages: previousMessages,
            newMessages: newMessages
        ))

        XCTAssertEqual(conversations[0].messageRevisionGroups.count, 1)
        let group = conversations[0].messageRevisionGroups[0]
        XCTAssertEqual(group.id, messageID)
        XCTAssertEqual(group.revisions.map(\.messages), [previousMessages, newMessages])
        XCTAssertEqual(group.selectedRevisionID, group.revisions[1].id)
    }

    func testCreateMessageRevisionAppendsToExistingGroupAfterSnapshotUpdate() {
        let conversationID = UUID()
        let messageID = UUID()
        let selectedRevisionID = UUID()
        let originalSelectedMessages = [
            ChatMessage(id: messageID, role: "user", content: "selected before snapshot")
        ]
        let previousMessages = [
            ChatMessage(id: messageID, role: "user", content: "previous")
        ]
        let newMessages = [
            ChatMessage(id: messageID, role: "user", content: "new")
        ]
        let revisionGroup = ChatMessageRevisionGroup(
            id: messageID,
            selectedRevisionID: selectedRevisionID,
            revisions: [
                ChatMessageRevision(id: selectedRevisionID, messages: originalSelectedMessages)
            ]
        )
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: previousMessages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.createMessageRevision(
            for: messageID,
            selectedConversationID: conversationID,
            conversations: &conversations,
            previousMessages: previousMessages,
            newMessages: newMessages
        ))

        let group = conversations[0].messageRevisionGroups[0]
        XCTAssertEqual(group.revisions.count, 2)
        XCTAssertEqual(group.revisions[0].messages, previousMessages)
        XCTAssertEqual(group.revisions[1].messages, newMessages)
        XCTAssertEqual(group.selectedRevisionID, group.revisions[1].id)
    }

    func testSelectMessageRevisionSnapshotsCurrentMessagesAndReturnsTargetMessages() {
        let conversationID = UUID()
        let messageID = UUID()
        let firstRevisionID = UUID()
        let secondRevisionID = UUID()
        let originalSelectedMessages = [
            ChatMessage(id: messageID, role: "user", content: "selected before snapshot")
        ]
        let currentMessages = [
            ChatMessage(id: messageID, role: "user", content: "current")
        ]
        let targetMessages = [
            ChatMessage(id: messageID, role: "user", content: "target")
        ]
        let revisionGroup = ChatMessageRevisionGroup(
            id: messageID,
            selectedRevisionID: firstRevisionID,
            revisions: [
                ChatMessageRevision(id: firstRevisionID, messages: originalSelectedMessages),
                ChatMessageRevision(id: secondRevisionID, messages: targetMessages)
            ]
        )
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: currentMessages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        let selectedMessages = ConversationPersistenceCoordinator.selectMessageRevision(
            messageID,
            offset: 1,
            selectedConversationID: conversationID,
            currentMessages: currentMessages,
            conversations: &conversations
        )

        XCTAssertEqual(selectedMessages, targetMessages)
        XCTAssertEqual(conversations[0].messageRevisionGroups[0].selectedRevisionID, secondRevisionID)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            currentMessages
        )
    }

    func testSaveUserMessageEditUpdatesMessageAndPreservesImageContextDescription() {
        let conversationID = UUID()
        let messageID = UUID()
        let attachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        let file = ChatFileAttachment(
            name: "note.txt",
            typeIdentifier: "public.text",
            byteCount: 4,
            characterCount: 4,
            extractedText: "note",
            isTruncated: false
        )
        let previousMessages = [
            ChatMessage(
                id: messageID,
                role: "user",
                content: "old",
                imageAttachments: [attachment],
                imageContextDescription: "image context"
            )
        ]
        var messages = previousMessages
        var conversations = [
            AIConversation(id: conversationID, messages: previousMessages)
        ]
        let edit = ConversationPersistenceCoordinator.UserMessageEdit(
            text: "new",
            imageAttachments: [attachment],
            fileAttachments: [file]
        )

        XCTAssertTrue(ConversationPersistenceCoordinator.saveUserMessageEdit(
            edit,
            for: messageID,
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations
        ))

        XCTAssertEqual(messages[0].content, "new")
        XCTAssertEqual(messages[0].imageContextDescription, "image context")
        XCTAssertEqual(messages[0].fileAttachments, [file])
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions.map(\.messages),
            [previousMessages, messages]
        )
    }

    func testSaveUserMessageEditClearsImageContextDescriptionWhenImagesChange() {
        let conversationID = UUID()
        let messageID = UUID()
        let originalAttachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        let replacementAttachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,BB==")
        var messages = [
            ChatMessage(
                id: messageID,
                role: "user",
                content: "old",
                imageAttachments: [originalAttachment],
                imageContextDescription: "image context"
            )
        ]
        var conversations = [
            AIConversation(id: conversationID, messages: messages)
        ]
        let edit = ConversationPersistenceCoordinator.UserMessageEdit(
            text: "new",
            imageAttachments: [replacementAttachment],
            fileAttachments: []
        )

        XCTAssertTrue(ConversationPersistenceCoordinator.saveUserMessageEdit(
            edit,
            for: messageID,
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations
        ))

        XCTAssertEqual(messages[0].imageContextDescription, "")
        XCTAssertEqual(messages[0].imageAttachments, [replacementAttachment])
    }

    func testSaveUserMessageEditAndPrepareRegenerationTruncatesAndReturnsContext() {
        let conversationID = UUID()
        let contextUserID = UUID()
        let messageID = UUID()
        let assistantID = UUID()
        let attachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        let previousMessages = [
            ChatMessage(id: contextUserID, role: "user", content: "context"),
            ChatMessage(
                id: messageID,
                role: "user",
                content: "old",
                imageAttachments: [attachment],
                imageContextDescription: "image context"
            ),
            ChatMessage(id: assistantID, role: "assistant", content: "old answer")
        ]
        var messages = previousMessages
        var conversations = [
            AIConversation(id: conversationID, messages: previousMessages)
        ]
        let edit = ConversationPersistenceCoordinator.UserMessageEdit(
            text: "new",
            imageAttachments: [attachment],
            fileAttachments: []
        )

        let request = ConversationPersistenceCoordinator.saveUserMessageEditAndPrepareRegeneration(
            edit,
            for: messageID,
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations
        )

        let expectedMessages = [
            ChatMessage(id: contextUserID, role: "user", content: "context"),
            ChatMessage(
                id: messageID,
                role: "user",
                content: "new",
                imageAttachments: [attachment],
                imageContextDescription: "image context"
            )
        ]
        XCTAssertEqual(messages, expectedMessages)
        XCTAssertEqual(request?.userMessageID, messageID)
        XCTAssertEqual(request?.userText, "new")
        XCTAssertEqual(request?.imageContextDescription, "image context")
        XCTAssertEqual(request?.contextMessages, [expectedMessages[0]])
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions.map(\.messages),
            [previousMessages, expectedMessages]
        )
    }

    func testPrepareAssistantResponseRegenerationTruncatesAfterPreviousUser() {
        let firstUserID = UUID()
        let firstAssistantID = UUID()
        let secondUserID = UUID()
        let secondAssistantID = UUID()
        let trailingAssistantID = UUID()
        var messages = [
            ChatMessage(id: firstUserID, role: "user", content: "first question"),
            ChatMessage(id: firstAssistantID, role: "assistant", content: "first answer"),
            ChatMessage(
                id: secondUserID,
                role: "user",
                content: "second question",
                imageContextDescription: "image context"
            ),
            ChatMessage(id: secondAssistantID, role: "assistant", content: "second answer"),
            ChatMessage(id: trailingAssistantID, role: "assistant", content: "trailing answer")
        ]

        let request = ConversationPersistenceCoordinator.prepareAssistantResponseRegeneration(
            for: secondAssistantID,
            messages: &messages
        )

        XCTAssertEqual(messages.map(\.id), [firstUserID, firstAssistantID, secondUserID])
        XCTAssertEqual(request?.userMessageID, secondUserID)
        XCTAssertEqual(request?.userText, "second question")
        XCTAssertEqual(request?.imageContextDescription, "image context")
        XCTAssertEqual(request?.contextMessages.map(\.id), [firstUserID, firstAssistantID])
    }

    func testUpdateAssistantMessageMutatesSelectedMessagesOnly() {
        let conversationID = UUID()
        let assistantMessageID = UUID()
        var messages = [
            ChatMessage(id: assistantMessageID, role: "assistant", content: "visible")
        ]
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [
                    ChatMessage(id: assistantMessageID, role: "assistant", content: "stored")
                ]
            )
        ]

        let result = ConversationPersistenceCoordinator.updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations,
            refreshesUpdatedAt: false
        ) { message in
            message.content = "updated"
        }

        XCTAssertEqual(result, .selected)
        XCTAssertEqual(messages[0].content, "updated")
        XCTAssertEqual(conversations[0].messages[0].content, "stored")
    }

    func testUpdateAssistantMessageMutatesStoredConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let selectedRevisionID = UUID()
        let originalUpdatedAt = Date(timeIntervalSince1970: 1)
        let refreshedAt = Date(timeIntervalSince1970: 2)
        let oldMessages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "old answer")
        ]
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: selectedRevisionID,
            revisions: [
                ChatMessageRevision(id: selectedRevisionID, messages: oldMessages)
            ]
        )
        var messages = [
            ChatMessage(role: "assistant", content: "visible")
        ]
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: oldMessages,
                messageRevisionGroups: [revisionGroup],
                updatedAt: originalUpdatedAt
            )
        ]

        let result = ConversationPersistenceCoordinator.updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: nil,
            messages: &messages,
            conversations: &conversations,
            refreshesUpdatedAt: true,
            date: refreshedAt
        ) { message in
            message.content = "new answer"
        }

        XCTAssertEqual(result, .stored(conversationIndex: 0))
        XCTAssertEqual(conversations[0].messages[1].content, "new answer")
        XCTAssertEqual(conversations[0].updatedAt, refreshedAt)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages[1].content,
            "new answer"
        )
        XCTAssertEqual(messages[0].content, "visible")
    }

    func testFlushBackgroundPendingTokensUpdatesConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        let generation = ActiveConversationGeneration(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            service: AIService()
        )
        generation.tokenBuffer.appendReasoning("thinking")
        generation.tokenBuffer.appendContent(" answer")
        generation.isFlushScheduled = true
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        let result = ConversationPersistenceCoordinator.flushBackgroundPendingTokens(
            from: generation,
            conversations: &conversations,
            flushesReasoning: true
        )

        XCTAssertEqual(result, ChatSessionViewModel.TokenFlushResult(
            messageWasFound: true,
            didConsumeReasoning: true,
            didConsumeContent: true,
            shouldInvalidateMarkdownCache: false,
            shouldRequestAutoScroll: false
        ))
        XCTAssertEqual(conversations[0].messages[1].content, "partial answer")
        XCTAssertEqual(conversations[0].messages[1].reasoningChunks, ["thinking"])
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
        XCTAssertFalse(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(generation.tokenBuffer.hasPendingReasoningText)
        XCTAssertFalse(generation.isFlushScheduled)
    }

    func testSynchronizeStoredAssistantContentUpdatesConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "partial")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.synchronizeStoredAssistantContent(
            "final",
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].messages[1].content, "final")
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
    }

    func testSynchronizeStoredAssistantContentReturnsFalseWhenUnchangedOrMissing() {
        let conversationID = UUID()
        let assistantMessageID = UUID()
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [ChatMessage(id: assistantMessageID, role: "assistant", content: "final")]
            )
        ]

        XCTAssertFalse(ConversationPersistenceCoordinator.synchronizeStoredAssistantContent(
            "final",
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))
        XCTAssertFalse(ConversationPersistenceCoordinator.synchronizeStoredAssistantContent(
            "updated",
            for: UUID(),
            in: conversationID,
            conversations: &conversations
        ))
        XCTAssertEqual(conversations[0].messages[0].content, "final")
    }

    func testSetStoredAssistantUsageUpdatesConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "answer")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        let usage = ChatUsage(inputTokens: 3, outputTokens: 5, totalTokens: 8)
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.setStoredAssistantUsage(
            usage,
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].messages[1].usage, usage)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
    }

    func testSetStoredAssistantUsageReturnsFalseForMissingMessage() {
        let conversationID = UUID()
        var conversations = [
            AIConversation(id: conversationID, messages: [ChatMessage(role: "assistant", content: "answer")])
        ]

        XCTAssertFalse(ConversationPersistenceCoordinator.setStoredAssistantUsage(
            ChatUsage(inputTokens: 1, outputTokens: 1),
            for: UUID(),
            in: conversationID,
            conversations: &conversations
        ))
    }

    func testSetStoredAssistantContentUpdatesConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "old")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.setStoredAssistantContent(
            "Request failed",
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].messages[1].content, "Request failed")
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
    }

    func testSetStoredToolExchangesUpdatesConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "answer")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        let exchanges = [
            ChatToolExchange(
                assistantContent: "checking",
                toolCalls: [
                    ChatToolCall(
                        id: "call-1",
                        name: "lookup",
                        displayName: "Lookup",
                        argumentsJSON: "{}"
                    )
                ],
                toolResults: [
                    ChatToolResult(
                        toolCallID: "call-1",
                        name: "lookup",
                        content: "result",
                        isError: false
                    )
                ]
            )
        ]
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.setStoredToolExchanges(
            exchanges,
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].messages[1].toolExchanges, exchanges)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
    }

    func testResetStoredStreamingRoundMessageDisplayClearsAssistantMessageFields() {
        let conversationID = UUID()
        let assistantMessageID = UUID()
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [
                    ChatMessage(
                        id: assistantMessageID,
                        role: "assistant",
                        content: "old",
                        contentChunks: ["old"],
                        reasoningContent: "reason",
                        reasoningChunks: ["reason"]
                    )
                ]
            )
        ]

        XCTAssertTrue(ConversationPersistenceCoordinator.resetStoredStreamingRoundMessageDisplay(
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        ))

        XCTAssertEqual(conversations[0].messages[0].content, "")
        XCTAssertEqual(conversations[0].messages[0].contentChunks, [])
        XCTAssertEqual(conversations[0].messages[0].reasoningContent, "")
        XCTAssertEqual(conversations[0].messages[0].reasoningChunks, [])
    }

    func testResetStoredStreamingRoundMessageDisplayReturnsFalseForMissingConversationOrMessage() {
        let conversationID = UUID()
        var conversations = [
            AIConversation(id: conversationID, messages: [ChatMessage(role: "assistant", content: "old")])
        ]

        XCTAssertFalse(ConversationPersistenceCoordinator.resetStoredStreamingRoundMessageDisplay(
            for: UUID(),
            in: conversationID,
            conversations: &conversations
        ))
        XCTAssertFalse(ConversationPersistenceCoordinator.resetStoredStreamingRoundMessageDisplay(
            for: UUID(),
            in: UUID(),
            conversations: &conversations
        ))
        XCTAssertEqual(conversations[0].messages[0].content, "old")
    }

    func testSetAssistantStoppedMutatesSelectedMessages() {
        let conversationID = UUID()
        let assistantMessageID = UUID()
        var messages = [
            ChatMessage(id: assistantMessageID, role: "assistant", content: "answer")
        ]
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [ChatMessage(id: assistantMessageID, role: "assistant", content: "stored")]
            )
        ]

        let result = ConversationPersistenceCoordinator.setAssistantStopped(
            true,
            for: assistantMessageID,
            in: conversationID,
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations
        )

        XCTAssertEqual(result, .selected)
        XCTAssertTrue(messages[0].isStopped)
        XCTAssertFalse(conversations[0].messages[0].isStopped)
    }

    func testSetAssistantStoppedMutatesStoredConversationAndRevisionSnapshot() {
        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let messages = [
            ChatMessage(id: userMessageID, role: "user", content: "question"),
            ChatMessage(id: assistantMessageID, role: "assistant", content: "answer")
        ]
        let revision = ChatMessageRevision(messages: messages)
        let revisionGroup = ChatMessageRevisionGroup(
            id: userMessageID,
            selectedRevisionID: revision.id,
            revisions: [revision]
        )
        var visibleMessages = [ChatMessage(role: "assistant", content: "visible")]
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: messages,
                messageRevisionGroups: [revisionGroup]
            )
        ]

        let result = ConversationPersistenceCoordinator.setAssistantStopped(
            true,
            for: assistantMessageID,
            in: conversationID,
            selectedConversationID: nil,
            messages: &visibleMessages,
            conversations: &conversations
        )

        XCTAssertEqual(result, .stored(conversationIndex: 0))
        XCTAssertTrue(conversations[0].messages[1].isStopped)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages,
            conversations[0].messages
        )
        XCTAssertFalse(visibleMessages[0].isStopped)
    }

    func testFlushBackgroundPendingTokensClearsGenerationWhenConversationIsMissing() {
        let generation = ActiveConversationGeneration(
            conversationID: UUID(),
            assistantMessageID: UUID(),
            service: AIService()
        )
        generation.tokenBuffer.appendReasoning("thinking")
        generation.tokenBuffer.appendContent("answer")
        generation.isFlushScheduled = true
        var conversations = [AIConversation]()

        let result = ConversationPersistenceCoordinator.flushBackgroundPendingTokens(
            from: generation,
            conversations: &conversations,
            flushesReasoning: true
        )

        XCTAssertNil(result)
        XCTAssertTrue(conversations.isEmpty)
        XCTAssertFalse(generation.tokenBuffer.hasPendingContentText)
        XCTAssertFalse(generation.tokenBuffer.hasPendingReasoningText)
        XCTAssertFalse(generation.isFlushScheduled)
    }

    func testSaveImageContextDescriptionMutatesSelectedMessage() {
        let conversationID = UUID()
        let messageID = UUID()
        let attachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        var messages = [
            ChatMessage(
                id: messageID,
                role: "user",
                content: "image",
                imageAttachments: [attachment]
            )
        ]
        var conversations = [
            AIConversation(id: conversationID, messages: [])
        ]

        let result = ConversationPersistenceCoordinator.saveImageContextDescription(
            "  image description  ",
            for: messageID,
            in: conversationID,
            matching: [attachment],
            selectedConversationID: conversationID,
            messages: &messages,
            conversations: &conversations
        )

        XCTAssertEqual(result, .selected)
        XCTAssertEqual(messages[0].imageContextDescription, "image description")
        XCTAssertTrue(conversations[0].messages.isEmpty)
    }

    func testSaveImageContextDescriptionMutatesStoredMessageAndRevisions() {
        let conversationID = UUID()
        let messageID = UUID()
        let revisionID = UUID()
        let attachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        let message = ChatMessage(
            id: messageID,
            role: "user",
            content: "image",
            imageAttachments: [attachment]
        )
        let revisionGroup = ChatMessageRevisionGroup(
            id: messageID,
            selectedRevisionID: revisionID,
            revisions: [
                ChatMessageRevision(id: revisionID, messages: [message])
            ]
        )
        var messages: [ChatMessage] = []
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [message],
                messageRevisionGroups: [revisionGroup]
            )
        ]

        let result = ConversationPersistenceCoordinator.saveImageContextDescription(
            "description",
            for: messageID,
            in: conversationID,
            matching: [attachment],
            selectedConversationID: nil,
            messages: &messages,
            conversations: &conversations
        )

        XCTAssertEqual(result, .stored)
        XCTAssertEqual(conversations[0].messages[0].imageContextDescription, "description")
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages[0].imageContextDescription,
            "description"
        )
    }

    func testSaveImageContextDescriptionMutatesRevisionsOnlyWhenMessageIsNotLoaded() {
        let conversationID = UUID()
        let messageID = UUID()
        let revisionID = UUID()
        let attachment = ChatImageAttachment(id: UUID(), dataURL: "data:image/jpeg;base64,AA==")
        let revisionMessage = ChatMessage(
            id: messageID,
            role: "user",
            content: "image",
            imageAttachments: [attachment]
        )
        let revisionGroup = ChatMessageRevisionGroup(
            id: messageID,
            selectedRevisionID: revisionID,
            revisions: [
                ChatMessageRevision(id: revisionID, messages: [revisionMessage])
            ]
        )
        var messages: [ChatMessage] = []
        var conversations = [
            AIConversation(
                id: conversationID,
                messages: [],
                messageRevisionGroups: [revisionGroup]
            )
        ]

        let result = ConversationPersistenceCoordinator.saveImageContextDescription(
            "description",
            for: messageID,
            in: conversationID,
            matching: [attachment],
            selectedConversationID: nil,
            messages: &messages,
            conversations: &conversations
        )

        XCTAssertEqual(result, .revisionsOnly)
        XCTAssertTrue(conversations[0].messages.isEmpty)
        XCTAssertEqual(
            conversations[0].messageRevisionGroups[0].revisions[0].messages[0].imageContextDescription,
            "description"
        )
    }
}
