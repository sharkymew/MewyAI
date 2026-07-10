import Foundation

enum ConversationPersistenceCoordinator {
    static let didReceiveExternalConversationWriteNotification = Notification.Name(
        "MewyAIConversationStoreDidReceiveExternalWrite"
    )

    enum AssistantMessageUpdateResult: Equatable {
        case selected
        case stored(conversationIndex: Int)
    }

    enum ImageContextDescriptionSaveResult: Equatable {
        case selected
        case stored
        case revisionsOnly
        case unchanged
    }

    struct UserMessageEdit: Equatable {
        let text: String
        let imageAttachments: [ChatImageAttachment]
        let fileAttachments: [ChatFileAttachment]

        init(
            text: String,
            imageAttachments: [ChatImageAttachment],
            fileAttachments: [ChatFileAttachment]
        ) {
            self.text = text
            self.imageAttachments = imageAttachments
            self.fileAttachments = fileAttachments
        }
    }

    struct ExistingUserMessageGenerationRequest: Equatable {
        let userMessageID: UUID
        let userText: String
        let imageAttachments: [ChatImageAttachment]
        let imageContextDescription: String
        let fileAttachments: [ChatFileAttachment]
        let contextMessages: [ChatMessage]
    }

    struct BranchConversationResult: Equatable {
        let conversation: AIConversation
    }

    struct ConversationDeletionResult: Equatable {
        let selectedConversation: AIConversation?
        let didReplaceWithNewConversation: Bool
    }

    struct EnsureConversationResult: Equatable {
        let conversation: AIConversation?
        let didCreate: Bool
    }

    static let saveFailureMessage = "无法保存对话。请确认设备仍有可用空间，并稍后再试。"

    static func storedConversations(
        from conversations: [AIConversation],
        privateConversationID: UUID?
    ) -> [AIConversation] {
        guard let privateConversationID else { return conversations }
        return conversations.filter { $0.id != privateConversationID }
    }

    static func deleteConversation(
        _ id: UUID,
        selectedConversationID: UUID?,
        conversations: inout [AIConversation],
        replacementConversation: @autoclosure () -> AIConversation = AIConversation()
    ) -> ConversationDeletionResult {
        if conversations.count <= 1 {
            let replacement = replacementConversation()
            conversations = [replacement]
            return ConversationDeletionResult(
                selectedConversation: replacement,
                didReplaceWithNewConversation: true
            )
        }

        conversations.removeAll { $0.id == id }

        guard selectedConversationID == id || selectedConversationID == nil else {
            return ConversationDeletionResult(
                selectedConversation: nil,
                didReplaceWithNewConversation: false
            )
        }

        return ConversationDeletionResult(
            selectedConversation: conversations.first,
            didReplaceWithNewConversation: false
        )
    }

    static func ensureCurrentConversation(
        conversations: inout [AIConversation],
        selectedConversationID: inout UUID?,
        replacementConversation: @autoclosure () -> AIConversation = AIConversation()
    ) -> EnsureConversationResult {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return EnsureConversationResult(conversation: nil, didCreate: false)
        }

        let conversation = replacementConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        return EnsureConversationResult(conversation: conversation, didCreate: true)
    }

    @discardableResult
    static func renameConversation(
        id: UUID,
        title: String,
        conversations: inout [AIConversation]
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return false }

        conversations[index].title = ConversationRenameDraft.normalizedTitle(title)
        conversations[index].hasGeneratedTitle = true
        return true
    }

    @discardableResult
    static func toggleConversationPin(
        id: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return false }

        conversations[index].isPinned.toggle()
        return true
    }

    @discardableResult
    static func synchronizeSelectedConversationSnapshot(
        conversations: inout [AIConversation],
        selectedConversationID: UUID?,
        messages: [ChatMessage],
        activeSkillIDs: Set<UUID>,
        activeMCPServerIDs: Set<UUID>,
        activeKnowledgeBaseIDs: Set<UUID> = [],
        refreshesUpdatedAt: Bool,
        date: Date = Date()
    ) -> Bool {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return false
        }

        conversations[index].messages = messages
        conversations[index].activeSkillIDs = Array(activeSkillIDs)
        conversations[index].activeMCPServerIDs = Array(activeMCPServerIDs)
        conversations[index].activeKnowledgeBaseIDs = Array(activeKnowledgeBaseIDs)
        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: index,
            snapshotMessages: messages
        )
        if refreshesUpdatedAt {
            conversations[index].updatedAt = date
        }
        return true
    }

    @discardableResult
    static func prepareStoredConversationForPersistence(
        _ conversationID: UUID,
        conversations: inout [AIConversation],
        refreshesUpdatedAt: Bool,
        date: Date = Date()
    ) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              !conversations[conversationIndex].isIndexOnly else {
            return false
        }

        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: conversations[conversationIndex].messages
        )
        if refreshesUpdatedAt {
            conversations[conversationIndex].updatedAt = date
        }
        return true
    }

    static func updateActiveMessageRevisionSnapshots(
        conversations: inout [AIConversation],
        conversationIndex: Int,
        snapshotMessages: [ChatMessage]
    ) {
        guard conversations.indices.contains(conversationIndex) else { return }

        for groupIndex in conversations[conversationIndex].messageRevisionGroups.indices {
            let group = conversations[conversationIndex].messageRevisionGroups[groupIndex]
            guard snapshotMessages.contains(where: { $0.id == group.id && $0.role == "user" }),
                  let revisionIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
                continue
            }

            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .revisions[revisionIndex]
                .messages = snapshotMessages
        }
    }

    static func messageRevisionNavigationState(
        for messageID: UUID,
        selectedConversationID: UUID?,
        conversations: [AIConversation]
    ) -> MessageRevisionNavigationState? {
        guard let selectedConversationID,
              let conversation = conversations.first(where: { $0.id == selectedConversationID }),
              let group = conversation.messageRevisionGroups.first(where: { $0.id == messageID }),
              group.revisions.count > 1,
              let currentIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
            return nil
        }

        return MessageRevisionNavigationState(
            currentIndex: currentIndex,
            count: group.revisions.count
        )
    }

    @discardableResult
    static func createMessageRevision(
        for messageID: UUID,
        selectedConversationID: UUID?,
        conversations: inout [AIConversation],
        previousMessages: [ChatMessage],
        newMessages: [ChatMessage]
    ) -> Bool {
        guard previousMessages != newMessages,
              previousMessages.contains(where: { $0.id == messageID && $0.role == "user" }),
              newMessages.contains(where: { $0.id == messageID && $0.role == "user" }),
              let selectedConversationID,
              let conversationIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return false
        }

        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: previousMessages
        )

        let newRevision = ChatMessageRevision(messages: newMessages)
        if let groupIndex = conversations[conversationIndex]
            .messageRevisionGroups
            .firstIndex(where: { $0.id == messageID }) {
            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .revisions
                .append(newRevision)
            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .selectedRevisionID = newRevision.id
        } else {
            let previousRevision = ChatMessageRevision(messages: previousMessages)
            let group = ChatMessageRevisionGroup(
                id: messageID,
                selectedRevisionID: newRevision.id,
                revisions: [previousRevision, newRevision]
            )
            conversations[conversationIndex].messageRevisionGroups.append(group)
        }

        return true
    }

    static func selectMessageRevision(
        _ messageID: UUID,
        offset: Int,
        selectedConversationID: UUID?,
        currentMessages: [ChatMessage],
        conversations: inout [AIConversation]
    ) -> [ChatMessage]? {
        guard offset != 0,
              let selectedConversationID,
              let conversationIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }),
              let groupIndex = conversations[conversationIndex]
                .messageRevisionGroups
                .firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: currentMessages
        )

        let group = conversations[conversationIndex].messageRevisionGroups[groupIndex]
        guard let currentIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
            return nil
        }

        let nextIndex = currentIndex + offset
        guard group.revisions.indices.contains(nextIndex) else { return nil }

        let revision = group.revisions[nextIndex]
        conversations[conversationIndex].messageRevisionGroups[groupIndex].selectedRevisionID = revision.id
        return revision.messages
    }

    @discardableResult
    static func saveUserMessageEdit(
        _ edit: UserMessageEdit,
        for messageID: UUID,
        selectedConversationID: UUID?,
        messages: inout [ChatMessage],
        conversations: inout [AIConversation]
    ) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID && $0.role == "user" }) else {
            return false
        }

        let previousMessages = messages
        apply(edit, to: &messages[messageIndex])
        createMessageRevision(
            for: messageID,
            selectedConversationID: selectedConversationID,
            conversations: &conversations,
            previousMessages: previousMessages,
            newMessages: messages
        )
        return true
    }

    static func saveUserMessageEditAndPrepareRegeneration(
        _ edit: UserMessageEdit,
        for messageID: UUID,
        selectedConversationID: UUID?,
        messages: inout [ChatMessage],
        conversations: inout [AIConversation]
    ) -> ExistingUserMessageGenerationRequest? {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID && $0.role == "user" }) else {
            return nil
        }

        let previousMessages = messages
        let imageContextDescription = imageContextDescriptionAfterApplying(
            edit,
            to: messages[messageIndex]
        )
        apply(edit, imageContextDescription: imageContextDescription, to: &messages[messageIndex])
        messages.removeSubrange((messageIndex + 1)..<messages.count)
        createMessageRevision(
            for: messageID,
            selectedConversationID: selectedConversationID,
            conversations: &conversations,
            previousMessages: previousMessages,
            newMessages: messages
        )

        return ExistingUserMessageGenerationRequest(
            userMessageID: messageID,
            userText: edit.text,
            imageAttachments: edit.imageAttachments,
            imageContextDescription: imageContextDescription,
            fileAttachments: edit.fileAttachments,
            contextMessages: Array(messages.prefix(messageIndex))
        )
    }

    static func prepareAssistantResponseRegeneration(
        for assistantMessageID: UUID,
        messages: inout [ChatMessage]
    ) -> ExistingUserMessageGenerationRequest? {
        guard let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessageID && $0.role == "assistant" }),
              let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == "user" }) else {
            return nil
        }

        let userMessage = messages[userIndex]
        messages.removeSubrange((userIndex + 1)..<messages.count)
        return ExistingUserMessageGenerationRequest(
            userMessageID: userMessage.id,
            userText: userMessage.content,
            imageAttachments: userMessage.imageAttachments,
            imageContextDescription: userMessage.imageContextDescription,
            fileAttachments: userMessage.fileAttachments,
            contextMessages: Array(messages.prefix(userIndex))
        )
    }

    static func prepareBranchFromMessage(
        _ messageID: UUID,
        in sourceConversation: AIConversation,
        messages: [ChatMessage],
        activeSkillIDs: Set<UUID>,
        activeMCPServerIDs: Set<UUID>,
        activeKnowledgeBaseIDs: Set<UUID> = [],
        date: Date = Date()
    ) -> BranchConversationResult? {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        let branchMessage = messages[messageIndex]
        let branchMessages = Array(messages.prefix(through: messageIndex))
        let branchMessageIDs = Set(branchMessages.map(\.id))
        var branchDividers = sourceConversation.branchDividers.filter { divider in
            branchMessageIDs.contains(divider.afterMessageID)
        }
        branchDividers.append(ConversationBranchDivider(
            afterMessageID: messageID,
            sourceMessageName: branchSourceMessageName(for: branchMessage)
        ))

        let branchedConversation = AIConversation(
            title: AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat"),
            messages: branchMessages,
            messageRevisionGroups: [],
            createdAt: date,
            updatedAt: date,
            hasGeneratedTitle: false,
            isPinned: false,
            activeSkillIDs: Array(activeSkillIDs),
            activeMCPServerIDs: Array(activeMCPServerIDs),
            activeKnowledgeBaseIDs: Array(activeKnowledgeBaseIDs),
            branchedFromConversationID: sourceConversation.id,
            branchedFromMessageID: messageID,
            branchDividers: branchDividers
        )

        return BranchConversationResult(
            conversation: branchedConversation
        )
    }

    private static func branchSourceMessageName(for message: ChatMessage) -> String {
        let sourceText = message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !sourceText.isEmpty {
            let limit = 24
            return sourceText.count > limit ? "\(sourceText.prefix(limit))..." : sourceText
        }

        if !message.fileAttachments.isEmpty {
            return AppLocalizations.string("conversation.branchSource.files", defaultValue: "附件消息")
        }

        if !message.imageAttachments.isEmpty {
            return AppLocalizations.string("conversation.branchSource.images", defaultValue: "图片消息")
        }

        return message.role == "assistant"
            ? AppLocalizations.string("conversation.branchSource.assistant", defaultValue: "AI 回复")
            : AppLocalizations.string("conversation.branchSource.user", defaultValue: "用户消息")
    }

    private static func apply(_ edit: UserMessageEdit, to message: inout ChatMessage) {
        let imageContextDescription = imageContextDescriptionAfterApplying(edit, to: message)
        apply(edit, imageContextDescription: imageContextDescription, to: &message)
    }

    private static func apply(
        _ edit: UserMessageEdit,
        imageContextDescription: String,
        to message: inout ChatMessage
    ) {
        message.content = edit.text
        message.imageAttachments = edit.imageAttachments
        message.imageContextDescription = imageContextDescription
        message.fileAttachments = edit.fileAttachments
    }

    private static func imageContextDescriptionAfterApplying(
        _ edit: UserMessageEdit,
        to message: ChatMessage
    ) -> String {
        message.imageAttachments == edit.imageAttachments
            ? message.imageContextDescription
            : ""
    }

    @discardableResult
    static func updateAssistantMessage(
        _ messageID: UUID,
        in conversationID: UUID,
        selectedConversationID: UUID?,
        messages: inout [ChatMessage],
        conversations: inout [AIConversation],
        refreshesUpdatedAt: Bool,
        date: Date = Date(),
        update: (inout ChatMessage) -> Void
    ) -> AssistantMessageUpdateResult? {
        if selectedConversationID == conversationID {
            guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
                return nil
            }

            update(&messages[messageIndex])
            return .selected
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex]
                .messages
                .firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        update(&conversations[conversationIndex].messages[messageIndex])
        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: conversations[conversationIndex].messages
        )
        if refreshesUpdatedAt {
            conversations[conversationIndex].updatedAt = date
        }
        return .stored(conversationIndex: conversationIndex)
    }

    @discardableResult
    static func flushBackgroundPendingTokens(
        from generation: ActiveConversationGeneration,
        conversations: inout [AIConversation],
        flushesReasoning: Bool
    ) -> ChatSessionViewModel.TokenFlushResult? {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == generation.conversationID }) else {
            generation.tokenBuffer.clearPendingTokens()
            generation.cancelScheduledFlush()
            return nil
        }

        let flushResult = ChatSessionViewModel.flushBackgroundPendingTokens(
            from: generation,
            into: &conversations[conversationIndex].messages,
            flushesReasoning: flushesReasoning
        )
        guard flushResult.messageWasFound else { return flushResult }

        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: conversations[conversationIndex].messages
        )
        return flushResult
    }

    @discardableResult
    static func synchronizeStoredAssistantContent(
        _ contentText: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              ChatSessionViewModel.synchronizeCompletedAssistantContent(
                contentText,
                for: assistantMessageID,
                in: &conversations[conversationIndex].messages
              ) else {
            return false
        }

        updateActiveMessageRevisionSnapshots(
            conversations: &conversations,
            conversationIndex: conversationIndex,
            snapshotMessages: conversations[conversationIndex].messages
        )
        return true
    }

    @discardableResult
    static func setStoredAssistantUsage(
        _ usage: ChatUsage,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        var visibleMessages = [ChatMessage]()
        return updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: nil,
            messages: &visibleMessages,
            conversations: &conversations,
            refreshesUpdatedAt: false,
            update: { message in
                message.usage = usage
            }
        ) != nil
    }

    @discardableResult
    static func setStoredAssistantContent(
        _ content: String,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        var visibleMessages = [ChatMessage]()
        return updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: nil,
            messages: &visibleMessages,
            conversations: &conversations,
            refreshesUpdatedAt: false,
            update: { message in
                message.content = content
            }
        ) != nil
    }

    @discardableResult
    static func setStoredToolExchanges(
        _ exchanges: [ChatToolExchange],
        for assistantMessageID: UUID,
        in conversationID: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        var visibleMessages = [ChatMessage]()
        return updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: nil,
            messages: &visibleMessages,
            conversations: &conversations,
            refreshesUpdatedAt: false,
            update: { message in
                message.toolExchanges = exchanges
            }
        ) != nil
    }

    @discardableResult
    static func resetStoredStreamingRoundMessageDisplay(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        conversations: inout [AIConversation]
    ) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        return ChatSessionViewModel.resetStreamingRoundMessageDisplay(
            for: assistantMessageID,
            in: &conversations[conversationIndex].messages
        )
    }

    @discardableResult
    static func setAssistantStopped(
        _ isStopped: Bool = true,
        for assistantMessageID: UUID,
        in conversationID: UUID,
        selectedConversationID: UUID?,
        messages: inout [ChatMessage],
        conversations: inout [AIConversation]
    ) -> AssistantMessageUpdateResult? {
        updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            selectedConversationID: selectedConversationID,
            messages: &messages,
            conversations: &conversations,
            refreshesUpdatedAt: false,
            update: { message in
                message.isStopped = isStopped
            }
        )
    }

    @discardableResult
    static func saveImageContextDescription(
        _ description: String,
        for messageID: UUID,
        in conversationID: UUID,
        matching imageAttachments: [ChatImageAttachment],
        selectedConversationID: UUID?,
        messages: inout [ChatMessage],
        conversations: inout [AIConversation]
    ) -> ImageContextDescriptionSaveResult {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else { return .unchanged }

        if selectedConversationID == conversationID,
           let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
           messages[messageIndex].imageAttachments == imageAttachments {
            messages[messageIndex].imageContextDescription = trimmedDescription
            return .selected
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return .unchanged
        }

        if let messageIndex = conversations[conversationIndex]
            .messages
            .firstIndex(where: { $0.id == messageID }),
           conversations[conversationIndex].messages[messageIndex].imageAttachments == imageAttachments {
            conversations[conversationIndex]
                .messages[messageIndex]
                .imageContextDescription = trimmedDescription
            _ = updateImageContextDescriptionInMessageRevisions(
                trimmedDescription,
                for: messageID,
                in: conversationIndex,
                matching: imageAttachments,
                conversations: &conversations
            )
            return .stored
        }

        if updateImageContextDescriptionInMessageRevisions(
            trimmedDescription,
            for: messageID,
            in: conversationIndex,
            matching: imageAttachments,
            conversations: &conversations
        ) {
            return .revisionsOnly
        }

        return .unchanged
    }

    private static func updateImageContextDescriptionInMessageRevisions(
        _ description: String,
        for messageID: UUID,
        in conversationIndex: Int,
        matching imageAttachments: [ChatImageAttachment],
        conversations: inout [AIConversation]
    ) -> Bool {
        guard conversations.indices.contains(conversationIndex) else {
            return false
        }

        var didUpdate = false
        for groupIndex in conversations[conversationIndex].messageRevisionGroups.indices {
            for revisionIndex in conversations[conversationIndex].messageRevisionGroups[groupIndex].revisions.indices {
                guard let messageIndex = conversations[conversationIndex]
                    .messageRevisionGroups[groupIndex]
                    .revisions[revisionIndex]
                    .messages
                    .firstIndex(where: { $0.id == messageID && $0.imageAttachments == imageAttachments }) else {
                    continue
                }

                conversations[conversationIndex]
                    .messageRevisionGroups[groupIndex]
                    .revisions[revisionIndex]
                    .messages[messageIndex]
                    .imageContextDescription = description
                didUpdate = true
            }
        }

        return didUpdate
    }

    @discardableResult
    static func saveConversations(
        _ conversations: [AIConversation],
        synchronize: Bool = false
    ) -> Bool {
        guard !conversations.isEmpty else { return false }
        return ConversationStore.saveConversations(conversations, synchronize: synchronize)
    }

    @discardableResult
    static func saveConversation(
        _ conversation: AIConversation,
        in conversations: [AIConversation],
        synchronize: Bool = false
    ) -> Bool {
        ConversationStore.saveConversation(
            conversation,
            in: conversations,
            synchronize: synchronize
        )
    }

    static func saveSelectedConversationIDIfStored(
        _ id: UUID,
        privateConversationID: UUID?,
        storedConversations: [AIConversation]
    ) {
        guard privateConversationID != id,
              storedConversations.contains(where: { $0.id == id }) else {
            ConversationStore.clearSelectedConversationID()
            return
        }

        ConversationStore.saveSelectedConversationID(id)
    }

    // Persists a conversation that was written from outside the main UI scene
    // (e.g. App Intents). Loads the freshest on-disk list, merges the
    // conversation in, saves, then posts a notification so the running app
    // can fold the change into its in-memory state. Returning the merged
    // conversation allows callers to surface the persisted snapshot back to
    // intents. Returns the persisted conversation, or nil on failure.
    @discardableResult
    static func saveConversationFromExternalSource(
        _ conversation: AIConversation,
        synchronize: Bool = false,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> AIConversation? {
        let onDiskConversations = ConversationStore.loadConversationList(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        var conversations = onDiskConversations
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else if let emptyIndex = conversations.firstIndex(where: { !$0.hasInformation }) {
            conversations[emptyIndex] = conversation
        } else {
            conversations.append(conversation)
        }

        guard ConversationStore.saveConversations(
            conversations,
            synchronize: synchronize,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ) else {
            return nil
        }

        NotificationCenter.default.post(
            name: didReceiveExternalConversationWriteNotification,
            object: conversation
        )
        return conversation
    }
}
