import SwiftUI
import Combine
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var agentSkills = AgentCapabilityStore.loadSkills()
    @State private var mcpServers = AgentCapabilityStore.loadMCPServers()
    @State private var agentCapabilitySelection = AgentCapabilitySelection()
    @State private var chatSession = ChatSessionViewModel()
    @StateObject private var speechInputController = SpeechInputController()
    @StateObject private var streamingOutputHaptics = StreamingOutputHaptics()
    @StateObject private var conversationActionHaptics = ConversationActionHaptics()
    @AppStorage(AIConfigurationStore.hapticFeedbackEnabledKey)
    private var isHapticFeedbackEnabled = AIConfigurationStore.defaultHapticFeedbackEnabled
    @AppStorage(ChatMemoryStore.memoryEnabledKey)
    private var isGlobalMemoryEnabled = ChatMemoryStore.defaultMemoryEnabled
    @AppStorage(ChatMemoryStore.historyRecallEnabledKey)
    private var isHistoryRecallEnabled = ChatMemoryStore.defaultHistoryRecallEnabled
    @AppStorage(AIConfigurationStore.saveCapturedPhotosToLibraryKey)
    private var isSaveCapturedPhotosToLibraryEnabled = AIConfigurationStore.defaultSaveCapturedPhotosToLibrary
    @State private var chatSessionPostProcessor = ChatSessionPostProcessor()
    @StateObject private var inputDraft = ChatInputDraft()
    @State private var conversations = ConversationStore.loadConversationsForStartup()
    @State private var selectedConversationID: UUID? = ConversationStore.loadSelectedConversationID()
    @State private var privateConversationID: UUID?
    @State private var conversationRenameDraft = ConversationRenameDraft()
    @State private var conversationExportDraft = ConversationExportDraft()
    @State private var conversationSaveErrorMessage: String?
    @State private var pendingClearGeneratedContentMessageID: UUID?
    @State private var showConfiguration = false
    @State private var showPromptSettings = false
    @State private var showAgentCapabilities = false
    @State private var showConversationSidebar = false
    @State private var chatScrollController = ChatScrollController()
    @State private var backgroundRequestKeeper = BackgroundRequestKeeper()
    @State private var backgroundCompletionNotificationCoordinator = BackgroundCompletionNotificationCoordinator()
    @State private var markdownRenderCache = MarkdownRenderCacheController()
    @State private var attachmentDraft = ChatAttachmentDraft()
    @State private var messageInteraction = MessageInteractionState()
    @State private var speechInputMergeState = SpeechInputMergeState()
    @State private var inputBarLayout = InputBarLayoutState()
    @State private var isExpandedInputPresented = false
    @State private var hasLoadedInitialConversation = false

    private let maxActiveConversationGenerations = 4
    private let inputBarBottomPadding: CGFloat = 8
    private let inputBarTopPadding: CGFloat = 8
    private let inputBarHorizontalPadding: CGFloat = 12
    private let inputBarCornerRadius: CGFloat = 34
    private let bottomScrollContentGap: CGFloat = 10
    private let inputBottomFadeHeight: CGFloat = 178
    private let inputBottomFadeOverlap: CGFloat = 118
    private let topGlassFadeExclusionInset: CGFloat = 8
    private let scrollToBottomFadeExclusionSize: CGFloat = 34
    private let topControlSize: CGFloat = 44
    private let topControlsTopPadding: CGFloat = 8
    private let topControlsHorizontalPadding: CGFloat = 16
    private let topModelButtonWidth: CGFloat = 148
    private let topFadeBottomPadding: CGFloat = 155
    private let topScrollContentGap: CGFloat = 70
    private let sidebarTransitionDuration: Double = 0.22

    private var pendingToolApproval: PendingToolApproval? {
        chatSession.pendingToolApproval
    }

    private var messages: [ChatMessage] {
        get { chatSession.messages }
        nonmutating set { chatSession.messages = newValue }
    }

    private var messageBindings: Binding<[ChatMessage]> {
        Binding {
            messages
        } set: { updatedMessages in
            messages = updatedMessages
        }
    }

    private var isGenerating: Bool {
        chatSession.isGenerating
    }

    private var pendingImageAttachments: [ChatImageAttachment] {
        get { attachmentDraft.pendingImageAttachments }
        nonmutating set { attachmentDraft.pendingImageAttachments = newValue }
    }

    private var pendingFileAttachments: [ChatFileAttachment] {
        get { attachmentDraft.pendingFileAttachments }
        nonmutating set { attachmentDraft.pendingFileAttachments = newValue }
    }

    private var imageSelectionError: String? {
        get { attachmentDraft.imageSelectionError }
        nonmutating set { attachmentDraft.imageSelectionError = newValue }
    }

    private var inputGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.14)
    }

    private var inputGlassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : Color.white.opacity(0.74)
    }

    private var controlGlassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.58)
    }

    private var inputBottomFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.40) : Color.white.opacity(0.62)
    }

    private var topFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.48)
    }

    private var topFadeHeight: CGFloat {
        topControlsTopPadding + topControlSize + topFadeBottomPadding
    }

    private var topScrollContentPadding: CGFloat {
        topControlsTopPadding + topControlSize + topScrollContentGap
    }

    private var bottomScrollContentPadding: CGFloat {
        inputBarLayout.bottomContentPadding(fallback: inputBarFallbackHeight, gap: bottomScrollContentGap)
    }

    private var scrollToBottomButtonBottomPadding: CGFloat {
        inputBarLayout.scrollButtonBottomPadding(fallback: inputBarFallbackHeight)
    }

    private var inputBarFallbackHeight: CGFloat {
        inputBottomFadeOverlap + activeAgentCapsuleFallbackHeight
    }

    private var activeAgentCapsuleFallbackHeight: CGFloat {
        activeAgentCapsules.isEmpty ? 0 : ActiveAgentCapsuleRow.fallbackHeight + 8
    }

    private func topChrome(
        topSafeAreaInset: CGFloat,
        sidebarToggleLeadingOffset: CGFloat,
        showsSidebarToggleExclusion: Bool
    ) -> some View {
        ChatTopChrome(
            colorScheme: colorScheme,
            tint: topFadeTint,
            topSafeAreaInset: topSafeAreaInset,
            fadeHeight: topFadeHeight,
            controlSize: topControlSize,
            controlsTopPadding: topControlsTopPadding,
            controlsHorizontalPadding: topControlsHorizontalPadding,
            sidebarToggleExclusionLeadingOffset: sidebarToggleLeadingOffset,
            glassFadeExclusionInset: topGlassFadeExclusionInset,
            showsSidebarToggleExclusion: showsSidebarToggleExclusion
        ) {
            topFloatingControls
        }
    }

    @ViewBuilder
    private func topGlassControl<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ChatTopGlassControl(
            tint: inputGlassTint,
            highlight: inputGlassHighlight,
            fadeExclusionInset: topGlassFadeExclusionInset,
            content: content
        )
    }

    private var storedConversations: [AIConversation] {
        ConversationPersistenceCoordinator.storedConversations(
            from: conversations,
            privateConversationID: privateConversationID
        )
    }

    private func fullConversationIfNeeded(_ conversation: AIConversation) -> AIConversation {
        guard conversation.isIndexOnly,
              let loadedConversation = ConversationStore.loadConversation(id: conversation.id) else {
            return conversation
        }

        if let index = conversations.firstIndex(where: { $0.id == loadedConversation.id }) {
            conversations[index] = loadedConversation
        }
        return loadedConversation
    }

    private func fullConversationIfNeeded(id: UUID) -> AIConversation? {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return nil }
        return fullConversationIfNeeded(conversation)
    }

    private func conversationForSearch(_ conversation: AIConversation) -> AIConversation {
        guard conversation.isIndexOnly else { return conversation }
        return ConversationStore.loadConversation(id: conversation.id) ?? conversation
    }

    private func fullyLoadedStoredConversations() -> [AIConversation] {
        storedConversations.map { fullConversationIfNeeded($0) }
    }

    private var isPrivateConversationSelected: Bool {
        guard let privateConversationID else { return false }
        return selectedConversationID == privateConversationID
    }

    private var showsTemporaryChatNotice: Bool {
        isPrivateConversationSelected && messages.isEmpty
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText
            || attachmentDraft.hasPendingAttachments
    }

    private var isEditingMessage: Bool {
        messageInteraction.isEditing
    }

    private var hasPendingInputAttachments: Bool {
        attachmentDraft.hasPendingAttachments
    }

    private var expandedInputCover: some View {
        ExpandedChatInputView(
            inputDraft: inputDraft,
            isGenerating: isGenerating,
            isEditingMessage: isEditingMessage,
            isSpeechRecording: speechInputController.isRecording,
            hasPendingAttachments: hasPendingInputAttachments,
            onPasteImageProviders: pasteImageProvidersFromInputMenu,
            onDismiss: dismissExpandedInputAndRefocus,
            onToggleSpeechInput: toggleSpeechInput,
            onStopGenerating: {
                stopGenerating()
            },
            onSendMessage: handleExpandedInputSend,
            onCancelEditingMessage: handleExpandedInputCancelEditing,
            onSaveEditingMessageOnly: handleExpandedInputSaveEditingOnly,
            onSaveEditingMessageAndRegenerate: handleExpandedInputSaveEditingAndRegenerate
        )
    }

    private func presentExpandedInput() {
        inputDraft.resignFocus()
        withAnimation(.easeInOut(duration: 0.22)) {
            isExpandedInputPresented = true
        }
    }

    private func dismissExpandedInput(refocusesInput: Bool) {
        withAnimation(.easeInOut(duration: 0.22)) {
            isExpandedInputPresented = false
        }
        guard refocusesInput else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard !isExpandedInputPresented else { return }
            inputDraft.requestFocus()
        }
    }

    private func dismissExpandedInputAndRefocus() {
        dismissExpandedInput(refocusesInput: true)
    }

    private func handleExpandedInputSend() {
        stopSpeechInputIfNeeded()
        let didStartSending = sendMessage()
        if didStartSending {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private func handleExpandedInputCancelEditing() {
        cancelEditingMessage()
        dismissExpandedInput(refocusesInput: false)
    }

    private func handleExpandedInputSaveEditingOnly() {
        stopSpeechInputIfNeeded()
        let didSave = saveEditingMessageOnly()
        if didSave {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private func handleExpandedInputSaveEditingAndRegenerate() {
        stopSpeechInputIfNeeded()
        let didStartSending = saveEditingMessageAndRegenerate()
        if didStartSending {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private func toggleSpeechInput() {
        SpeechInputHandler.toggleRecording(
            controller: speechInputController,
            mergeState: &speechInputMergeState,
            currentText: inputDraft.text
        )
    }

    private func stopSpeechInputIfNeeded() {
        SpeechInputHandler.stopRecordingIfNeeded(controller: speechInputController)
    }

    private func resolveToolApproval(_ isAllowed: Bool) {
        chatSession.resolveToolApproval(isAllowed)
    }

    private func resetSpeechInputMergeState() {
        SpeechInputHandler.resetMergeState(&speechInputMergeState, baseText: inputDraft.text)
    }

    private func applySpeechTranscript(_ transcript: String) {
        SpeechInputHandler.applyTranscript(
            transcript,
            mergeState: &speechInputMergeState,
            inputDraft: inputDraft
        )
    }

    var body: some View {
        ChatConversationRootLayout(
            isSidebarVisible: $showConversationSidebar,
            conversations: storedConversations,
            conversationForSearch: conversationForSearch,
            selectedConversationID: selectedConversationID,
            transitionDuration: sidebarTransitionDuration,
            isExpandedInputPresented: isExpandedInputPresented,
            onOverlayClose: {
                setConversationSidebarVisibility(false)
            },
            onEdgeOpen: {
                hideKeyboard()
                setConversationSidebarVisibility(true)
            },
            onSelectConversation: { id, closesSidebar in
                selectConversation(id, closesSidebar: closesSidebar)
            },
            onOpenConfiguration: { closesSidebar in
                openConfigurationFromSidebar(closesSidebar: closesSidebar)
            },
            onRenameConversation: beginRenamingConversation,
            onTogglePinnedConversation: toggleConversationPin,
            onExportConversation: beginExportingConversation,
            onDeleteConversation: deleteConversation,
            mainContent: { topSafeAreaInset, showsSidebarToggleExclusion, sidebarToggleLeadingOffset in
                mainContent(
                    topSafeAreaInset: topSafeAreaInset,
                    sidebarToggleLeadingOffset: sidebarToggleLeadingOffset,
                    showsSidebarToggleExclusion: showsSidebarToggleExclusion
                )
            },
            sidebarToggle: { sidebarToggleLeadingOffset in
                sidebarToggleControl(leadingOffset: sidebarToggleLeadingOffset)
            },
            expandedInput: {
                expandedInputCover
            }
        )
        .onAppear {
            guard !hasLoadedInitialConversation else { return }
            hasLoadedInitialConversation = true
            loadSelectedConversation()
            updateMissingHistorySummariesIfNeeded(configuration: currentConfiguration)
            if isHapticFeedbackEnabled {
                conversationActionHaptics.prepare()
            }
        }
        .chatRootPresentations(
            showConfiguration: $showConfiguration,
            showPromptSettings: $showPromptSettings,
            showAgentCapabilities: $showAgentCapabilities,
            conversationRenameDraft: $conversationRenameDraft,
            conversationExportDraft: $conversationExportDraft,
            conversationSaveErrorMessage: $conversationSaveErrorMessage,
            pendingClearGeneratedContentMessageID: $pendingClearGeneratedContentMessageID,
            attachmentDraft: $attachmentDraft,
            promptConfigurationID: currentConfiguration.id,
            pendingToolApproval: pendingToolApproval,
            toolApprovalMessage: toolApprovalMessage,
            onResetRenamingConversation: resetRenamingConversationState,
            onCommitRenamingConversation: commitRenamingConversation,
            onConfirmClearGeneratedContent: confirmClearGeneratedContent,
            onResolveToolApproval: resolveToolApproval,
            onLoadSelectedFiles: loadSelectedFiles,
            onConfigurationDismissed: {
                reloadConfigurations()
                reloadAgentCapabilities()
            },
            onPromptSettingsDismissed: reloadConfigurations,
            onAgentCapabilitiesDismissed: reloadAgentCapabilities,
            onSelectedPhotoItemsChanged: loadSelectedImages,
            onCameraImageCaptured: { image in
                handleCameraImage(image)
            }
        )
        .onChange(of: dynamicTypeSize) { _, _ in
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { _, _ in
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        }
        .onChange(of: speechInputController.transcript) { _, transcript in
            applySpeechTranscript(transcript)
        }
        .onChange(of: isHapticFeedbackEnabled) { _, isEnabled in
            if isEnabled {
                conversationActionHaptics.prepare()
            }

            if isEnabled, isGenerating {
                streamingOutputHaptics.prepareForStreaming()
            } else {
                streamingOutputHaptics.reset()
            }
        }
        .onChange(of: isGlobalMemoryEnabled) { _, isEnabled in
            if isEnabled {
                updateMissingHistorySummariesIfNeeded(configuration: currentConfiguration)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else {
                updateBackgroundRequestKeeper()
                return
            }
            speechInputController.stopRecording()
            persistApplicationStateForLifecycle()
            updateBackgroundRequestKeeper()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ConversationPersistenceCoordinator.didReceiveExternalConversationWriteNotification
            )
        ) { notification in
            mergeExternalConversation(notification.object as? AIConversation)
        }
    }

    private func setConversationSidebarVisibility(_ isVisible: Bool) {
        guard showConversationSidebar != isVisible else { return }
        showConversationSidebar = isVisible
    }

    @ViewBuilder
    private func mainContent(
        topSafeAreaInset: CGFloat,
        sidebarToggleLeadingOffset: CGFloat,
        showsSidebarToggleExclusion: Bool
    ) -> some View {
        ChatMainConversationContent(
            scrollController: chatScrollController,
            topSafeAreaInset: topSafeAreaInset,
            topScrollContentPadding: topScrollContentPadding,
            bottomScrollContentPadding: bottomScrollContentPadding,
            scrollToBottomButtonBottomPadding: scrollToBottomButtonBottomPadding,
            showsTemporaryChatNotice: showsTemporaryChatNotice,
            chatScrollView: chatScrollView,
            temporaryNotice: {
                temporaryChatNotice
            },
            topChrome: { topSafeAreaInset in
                topChrome(
                    topSafeAreaInset: topSafeAreaInset,
                    sidebarToggleLeadingOffset: sidebarToggleLeadingOffset,
                    showsSidebarToggleExclusion: showsSidebarToggleExclusion
                )
            },
            inputBar: {
                inputBar(includesLegacyFade: true)
            },
            scrollButtonLabel: {
                ChatScrollToBottomGlassIconLabel(
                    tint: inputGlassTint,
                    highlight: inputGlassHighlight
                )
            }
        )
    }

    private func chatScrollView(topPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        ChatMessageScrollView(
            messages: messageBindings,
            messageInteraction: $messageInteraction,
            scrollController: chatScrollController,
            isGenerating: isGenerating,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            visibleAssistantDisplayState: { messageID in
                chatSession.visibleAssistantDisplayState(for: messageID)
            },
            markdownRenderCacheEntry: { messageID in
                markdownRenderCache[messageID]
            },
            usageFooterText: usageFooterText,
            revisionNavigationState: messageRevisionNavigationState,
            onReasoningExpansionChanged: { messageID, isExpanded in
                handleReasoningExpansionChange(for: messageID, isExpanded: isExpanded)
            },
            onRegenerate: regenerateAssistantResponse,
            onEdit: startEditingUserMessage,
            onBranch: branchFromMessage,
            onClearGeneratedContent: requestClearGeneratedContent,
            onSelectPreviousRevision: { messageID in
                selectMessageRevision(messageID, offset: -1)
            },
            onSelectNextRevision: { messageID in
                selectMessageRevision(messageID, offset: 1)
            },
            onHideKeyboard: hideKeyboard
        )
    }

    private var temporaryChatNotice: some View {
        VStack(spacing: 12) {
            Text("临时聊天")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("在临时聊天中，聊天不会出现在历史记录中，但是在此对话进行过程中，你的上下文记录会被发送到模型提供商。")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("即使开启了「保存拍摄的照片到相册」，在临时聊天中拍摄的照片也不会保存到相册。")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
    }

    private func inputBar(includesLegacyFade: Bool) -> some View {
        ChatInputBar(
            showsActiveAgentCapsules: !activeAgentCapsules.isEmpty,
            showsPendingAttachments: hasPendingInputAttachments,
            imageSelectionError: imageSelectionError,
            speechInputError: speechInputController.errorMessage,
            isEditingMessage: isEditingMessage,
            inputGlassTint: inputGlassTint,
            inputGlassHighlight: inputGlassHighlight,
            cornerRadius: inputBarCornerRadius,
            horizontalPadding: inputBarHorizontalPadding,
            topPadding: inputBarTopPadding,
            bottomPadding: inputBarBottomPadding,
            includesLegacyFade: includesLegacyFade,
            isAttachmentDropTargeted: $attachmentDraft.isAttachmentDropTargeted,
            onDropAttachments: handleDroppedAttachments,
            onMeasuredHeightChanged: { height in
                guard inputBarLayout.updateMeasuredHeight(height) else { return }

                chatScrollController.requestImmediateAutoScroll(animated: false)
            },
            activeAgentCapsules: {
                activeAgentCapsuleRow
            },
            pendingAttachmentPreview: {
                pendingAttachmentPreview
            },
            composer: {
                inputComposer
            },
            legacyFade: {
                ChatInputBottomFadeBackdrop(
                    colorScheme: colorScheme,
                    tint: inputBottomFadeTint,
                    fadeHeight: inputBottomFadeHeight,
                    fadeOverlap: inputBottomFadeOverlap,
                    inputBottomPadding: inputBarBottomPadding,
                    scrollButtonBottomPadding: scrollToBottomButtonBottomPadding,
                    scrollButtonFadeExclusionSize: scrollToBottomFadeExclusionSize,
                    showsScrollToBottomButton: chatScrollController.shouldShowScrollToBottomButton
                )
            }
        )
    }

    private var topFloatingControls: some View {
        let actionPresentation = conversationActionPresentation
        return ChatTopFloatingControls(
            canCreateConversation: actionPresentation.canCreateConversation,
            showsTemporaryChatNotice: actionPresentation.showsTemporaryChatNotice,
            actionSystemImage: actionPresentation.systemImage,
            actionAccessibilityLabel: actionPresentation.accessibilityLabel,
            actionAccessibilityHint: actionPresentation.accessibilityHint,
            controlSize: topControlSize,
            horizontalPadding: topControlsHorizontalPadding,
            topPadding: topControlsTopPadding,
            glassTint: inputGlassTint,
            glassHighlight: inputGlassHighlight,
            glassFadeExclusionInset: topGlassFadeExclusionInset,
            onAction: {
                triggerConversationActionHapticIfNeeded()
                hideKeyboard()
                handleTopConversationAction()
            }
        ) {
            topConversationTitleMenu
        }
    }

    private func sidebarToggleControl(leadingOffset: CGFloat) -> some View {
        ChatSidebarToggleControl(
            isSidebarVisible: showConversationSidebar,
            controlSize: topControlSize,
            horizontalPadding: topControlsHorizontalPadding,
            leadingOffset: leadingOffset,
            topPadding: topControlsTopPadding,
            glassTint: inputGlassTint,
            glassHighlight: inputGlassHighlight,
            glassFadeExclusionInset: topGlassFadeExclusionInset
        ) {
            hideKeyboard()
            setConversationSidebarVisibility(!showConversationSidebar)
        }
    }

    @ViewBuilder
    private var inputComposer: some View {
        inputComposerContent
    }

    private var inputComposerContent: some View {
        ChatInputComposer(
            inputDraft: inputDraft,
            isGenerating: isGenerating,
            isEditingMessage: isEditingMessage,
            isSpeechRecording: speechInputController.isRecording,
            hasPendingAttachments: hasPendingInputAttachments,
            inputGlassTint: inputGlassTint,
            controlGlassHighlight: controlGlassHighlight,
            onPasteImageProviders: pasteImageProvidersFromInputMenu,
            onExpandInput: presentExpandedInput,
            onToggleSpeechInput: toggleSpeechInput,
            onStopGenerating: {
                stopGenerating()
            },
            onSendMessage: {
                stopSpeechInputIfNeeded()
                sendMessage()
            },
            onCancelEditingMessage: cancelEditingMessage,
            onSaveEditingMessageOnly: {
                stopSpeechInputIfNeeded()
                saveEditingMessageOnly()
            },
            onSaveEditingMessageAndRegenerate: {
                stopSpeechInputIfNeeded()
                saveEditingMessageAndRegenerate()
            }
        ) {
            inputOptionsMenu
        }
    }

    private var pendingAttachmentPreview: some View {
        ChatPendingAttachmentPreview(
            imageAttachments: pendingImageAttachments,
            fileAttachments: pendingFileAttachments,
            onRemoveImage: removePendingImage,
            onRemoveFile: removePendingFile
        )
    }

    private var activeAgentCapsules: [ActiveAgentCapsule] {
        agentCapabilitySelection.capsules(skills: agentSkills, mcpServers: mcpServers)
    }

    private var activeAgentCapsuleRow: some View {
        ActiveAgentCapsuleRow(capsules: activeAgentCapsules) { capsule in
            deactivateAgentCapsule(capsule)
        }
    }

    private var modelMenu: some View {
        ChatModelSelectionMenu(
            configuration: currentConfiguration,
            conversationUsageSummaryText: nil,
            includesPromptSettings: false,
            isDisabled: isGenerating,
            onSelectModel: selectModel,
            onOpenConfiguration: {
                hideKeyboard()
                showConfiguration = true
            },
            onOpenPromptSettings: {}
        ) {
            ChatCircularGlassIconLabel(
                systemName: "cube.transparent",
                size: 19,
                weight: .semibold,
                frame: 48,
                tint: inputGlassTint,
                highlight: controlGlassHighlight
            )
        }
    }

    private var topConversationTitleMenu: some View {
        let title = currentConfiguration.selectedModelDisplayName

        return topGlassControl {
            ChatModelSelectionMenu(
                configuration: currentConfiguration,
                conversationUsageSummaryText: conversationUsageSummaryText,
                includesPromptSettings: true,
                isDisabled: isGenerating,
                onSelectModel: selectModel,
                onOpenConfiguration: {
                    hideKeyboard()
                    showConfiguration = true
                },
                onOpenPromptSettings: {
                    hideKeyboard()
                    showPromptSettings = true
                }
            ) {
                ChatModelTitleMenuLabel(
                    title: title,
                    width: topModelButtonWidth,
                    height: topControlSize
                )
            }
        }
        .accessibilityLabel(AppLocalizations.format(
            "accessibility.currentModel",
            defaultValue: "Current model: %@",
            arguments: [title]
        ))
    }

    private func usageFooterText(for message: ChatMessage) -> String? {
        ChatUsageDisplayFormatter.footerText(for: message, configurations: configurations)
    }

    private var conversationUsageSummaryText: String? {
        ChatUsageDisplayFormatter.conversationSummaryText(
            for: messages,
            configurations: configurations
        )
    }

    private var inputOptionsMenu: some View {
        ChatInputOptionsMenu(
            configuration: currentConfiguration,
            agentSkills: agentSkills,
            mcpServers: mcpServers,
            capabilitySelection: agentCapabilitySelection,
onOpenPhotoPicker: {
            attachmentDraft.isPhotoPickerPresented = true
        },
        onOpenCamera: {
            attachmentDraft.isCameraPresented = true
        },
        onOpenFileImporter: {
            attachmentDraft.isFileImporterPresented = true
        },
            onToggleSkill: toggleSkill,
            onToggleMCPServer: toggleMCPServer,
            onManageSkills: {
                hideKeyboard()
                showAgentCapabilities = true
            },
            onManageMCPServers: {
                hideKeyboard()
                showAgentCapabilities = true
            },
            onSetReasoningEnabled: setReasoningEnabled,
            onSelectReasoningEffort: selectReasoningEffort
        ) {
            ChatCircularGlassIconLabel(
                systemName: "plus",
                size: 16,
                weight: .bold,
                frame: 34,
                tint: inputGlassTint,
                highlight: controlGlassHighlight
            )
        }
    }

    private var conversationActionPresentation: ChatConversationActionPresentation {
        ChatConversationActionPresentation(
            isCurrentConversationBlank: currentConversationIsBlank,
            isPrivateConversationSelected: isPrivateConversationSelected
        )
    }

    private var canCreateConversation: Bool {
        conversationActionPresentation.canCreateConversation
    }

    private var showsPrivateConversationAction: Bool {
        conversationActionPresentation.showsPrivateConversationAction
    }

    private var currentConversationIsBlank: Bool {
        messages.isEmpty
            && inputDraft.trimmedText.isEmpty
            && !attachmentDraft.hasPendingAttachments
    }

    private var currentConfiguration: AIConfiguration {
        AIConfigurationStore.selectedConfiguration(
            from: configurations,
            selectedID: selectedConfigurationID
        )
    }

    private var activeSkills: [AgentSkill] {
        agentCapabilitySelection.activeSkills(in: agentSkills)
    }

    private var activeMCPServers: [MCPServerConfiguration] {
        agentCapabilitySelection.activeMCPServers(in: mcpServers)
    }

    private var toolApprovalMessage: String {
        guard let pendingToolApproval else { return "" }
        let arguments = pendingToolApproval.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !arguments.isEmpty else {
            return pendingToolApproval.toolName
        }
        return "\(pendingToolApproval.toolName)\n\n\(String(arguments.prefix(1_000)))"
    }

    private func reloadAgentCapabilities() {
        AgentCapabilitySelectionCoordinator.reload(
            skills: &agentSkills,
            mcpServers: &mcpServers,
            selection: &agentCapabilitySelection
        )
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func toggleSkill(_ id: UUID) {
        AgentCapabilitySelectionCoordinator.toggleSkill(id, selection: &agentCapabilitySelection)
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func toggleMCPServer(_ id: UUID) {
        AgentCapabilitySelectionCoordinator.toggleMCPServer(id, selection: &agentCapabilitySelection)
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func deactivateAgentCapsule(_ capsule: ActiveAgentCapsule) {
        AgentCapabilitySelectionCoordinator.deactivate(capsule, selection: &agentCapabilitySelection)
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func executeAgentTool(
        _ request: AgentToolCallRequest,
        in conversationID: UUID?
    ) async -> AgentToolCallResult {
        await AgentToolExecutionCoordinator.execute(
            request,
            in: conversationID,
            privateConversationID: privateConversationID,
            mcpServers: mcpServers,
            conversations: fullyLoadedStoredConversations,
            requestApproval: { toolName, arguments in
                await requestToolApproval(toolName: toolName, arguments: arguments)
            },
            saveRefreshedTools: { tools, server in
                AgentCapabilitySelectionCoordinator.applyRefreshedTools(
                    tools,
                    for: server,
                    to: &mcpServers
                )
            }
        )
    }

    @MainActor
    private func requestToolApproval(toolName: String, arguments: String) async -> Bool {
        await chatSession.requestToolApproval(toolName: toolName, arguments: arguments)
    }

    @discardableResult
    func sendMessage() -> Bool {
        stopSpeechInputIfNeeded()
        let userText = inputDraft.trimmedText
        let imageAttachments = pendingImageAttachments
        let fileAttachments = pendingFileAttachments
        ensureCurrentConversation()
        return startStreamingResponse(
            userText: userText,
            imageAttachments: imageAttachments,
            fileAttachments: fileAttachments,
            contextMessages: messages,
            appendsUserMessage: true
        )
    }

    @discardableResult
    private func startStreamingResponse(
        userText: String,
        imageAttachments: [ChatImageAttachment],
        imageContextDescription: String = "",
        fileAttachments: [ChatFileAttachment],
        contextMessages: [ChatMessage],
        appendsUserMessage: Bool,
        existingUserMessageID: UUID? = nil
    ) -> Bool {
        let turnContext = ChatStreamingTurnContextBuilder.make(
            configuration: currentConfiguration,
            activeSkills: activeSkills,
            activeMCPServers: activeMCPServers,
            storedConversations: storedConversations,
            selectedConversationID: selectedConversationID,
            privateConversationID: privateConversationID,
            isHistoryRecallEnabled: isHistoryRecallEnabled,
            isGlobalMemoryEnabled: isGlobalMemoryEnabled
        )

        let preparationContext = ChatSessionViewModel.StreamingTurnPreparationContext(
            conversationID: selectedConversationID,
            userText: userText,
            imageAttachments: imageAttachments,
            imageContextDescription: imageContextDescription,
            fileAttachments: fileAttachments,
            contextMessages: contextMessages,
            appendsUserMessage: appendsUserMessage,
            existingUserMessageID: existingUserMessageID,
            configuration: turnContext.configuration,
            systemPromptAppendix: turnContext.systemPromptAppendix,
            hasActiveMCPServers: turnContext.hasActiveMCPServers,
            mcpTools: turnContext.mcpTools,
            recallTools: turnContext.recallTools,
            maxActiveConversationGenerations: maxActiveConversationGenerations
        )
        let preparation: ChatSessionViewModel.StreamingTurnPreparation
        switch chatSession.prepareStreamingTurn(preparationContext) {
        case .success(let result):
            preparation = result
        case .failure(let failure):
            handleStreamingTurnPreparationFailure(failure)
            return false
        }

        let startResult = preparation.startResult
        let serviceRequest = preparation.serviceRequest
        let conversationID = startResult.generation.conversationID
        let assistantMessageID = startResult.assistantMessageID
        let userMessageIDForImageContext = startResult.userMessageIDForImageContext

        clearInputState()
        prepareStreamingOutputHapticsIfNeeded()
        chatScrollController.returnToBottom()
        messageInteraction.activeActionID = nil

        markdownRenderCache.invalidate(for: assistantMessageID)
        persistCurrentConversation()

        updateBackgroundRequestKeeper()
        if conversationID != privateConversationID {
            backgroundCompletionNotificationCoordinator.requestAuthorizationIfNeeded()
        }

        chatSession.sendStreamingRequest(
            serviceRequest,
            using: startResult,
            handlers: ChatSessionViewModel.StreamingEventHandlers(
                toolExecutor: { request in
                    await executeAgentTool(request, in: conversationID)
                },
                onToolExchangesUpdated: { exchanges in
                    updateToolExchanges(
                        exchanges,
                        for: assistantMessageID,
                        in: conversationID
                    )
                },
                onToolRoundReset: {
                    resetStreamingRoundDisplay(
                        for: assistantMessageID,
                        in: conversationID
                    )
                },
                isReasoningDisplayActive: {
                    isReasoningDisplayActive(
                        for: assistantMessageID,
                        in: conversationID
                    )
                },
                onReasoningToken: { token in
                    handleReasoningToken(
                        token,
                        for: assistantMessageID,
                        in: conversationID
                    )
                },
                onContentToken: { token in
                    handleContentToken(
                        token,
                        for: assistantMessageID,
                        in: conversationID
                    )
                },
                onComplete: { contentText, usage in
                    completeStreamingResponse(
                        for: assistantMessageID,
                        in: conversationID,
                        contentText: contentText,
                        usage: usage,
                        configuration: turnContext.configuration
                    )
                },
                onError: { error in
                    failStreamingResponse(
                        error,
                        for: assistantMessageID,
                        in: conversationID
                    )
                }
            )
        )

        if preparation.shouldGenerateImageContextDescription,
           let userMessageIDForImageContext {
            chatSessionPostProcessor.generateImageContextDescriptionIfNeeded(
                imageAttachments: serviceRequest.imageAttachments,
                baseURL: serviceRequest.baseURL,
                apiFormat: serviceRequest.apiFormat,
                apiKey: serviceRequest.apiKey,
                customHeaders: serviceRequest.customHeaders,
                model: serviceRequest.model,
                modelParameters: serviceRequest.modelParameters,
                anthropicMaxTokens: serviceRequest.anthropicMaxTokens,
                reasoningEnabled: serviceRequest.reasoningEnabled,
                reasoningEffort: serviceRequest.reasoningEffort
            ) { description in
                saveImageContextDescription(
                    description,
                    for: userMessageIDForImageContext,
                    in: conversationID,
                    matching: serviceRequest.imageAttachments
                )
            }
        }

        return true
    }

    private func activeGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) -> ActiveConversationGeneration? {
        chatSession.activeGeneration(for: assistantMessageID, in: conversationID)
    }

    private func isReasoningDisplayActive(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) -> Bool {
        chatSession.isReasoningDisplayActive(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: selectedConversationID
        )
    }

    private func updateToolExchanges(
        _ exchanges: [ChatToolExchange],
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        if selectedConversationID == conversationID {
            if chatSession.updateVisibleToolExchanges(
                exchanges,
                for: assistantMessageID,
                in: conversationID,
                visibleConversationID: selectedConversationID
            ) {
                persistCurrentConversation(refreshesUpdatedAt: false)
            }
            return
        }

        let didUpdateStoredExchanges = ConversationPersistenceCoordinator.setStoredToolExchanges(
            exchanges,
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        )
        if didUpdateStoredExchanges {
            saveConversationsPreservingSelectedConversation()
        }
    }

    /// Clears the streamed content/reasoning of an in-flight assistant message
    /// after a tool round: the streamed text moves into the tool exchange, so
    /// the live message display must start over for the next round.
    private func resetStreamingRoundDisplay(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard let resetEffect = chatSession.resetStreamingRoundDisplay(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: selectedConversationID
        ) else { return }

        if resetEffect.isVisibleConversation {
            if resetEffect.shouldResetLiveContentDisplay {
                resetLiveContentDisplay(for: assistantMessageID)
            }
            if resetEffect.shouldClearLiveReasoningDisplay {
                clearLiveReasoningDisplay(for: assistantMessageID)
            }
            if resetEffect.shouldInvalidateMarkdownCache {
                markdownRenderCache.invalidate(for: assistantMessageID)
            }
            return
        }

        ConversationPersistenceCoordinator.resetStoredStreamingRoundMessageDisplay(
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        )
    }

    private func handleReasoningToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard chatSession.receiveReasoningToken(
            token,
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: selectedConversationID
        ) else { return }

        updateLiveReasoningDisplayIfNeeded(for: assistantMessageID, token: token)
    }

    private func handleContentToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard let effect = chatSession.receiveContentToken(
            token,
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: selectedConversationID
        ) else { return }

        if effect.shouldAppendLiveContent {
            if let collapse = effect.reasoningCollapse {
                applyReasoningCollapseAfterThinking(collapse, for: assistantMessageID)
            }
            appendLiveContentToken(token, for: assistantMessageID)
            scheduleStreamingAutoScroll()
        }

        scheduleTokenFlush(for: assistantMessageID, in: conversationID)
    }

    private func completeStreamingResponse(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        contentText: String,
        usage: ChatUsage?,
        configuration: AIConfiguration
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        cancelScheduledFlush(for: conversationID)
        flushPendingTokens(
            for: assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: selectedConversationID == conversationID
        )
        synchronizeCompletedAssistantContent(
            contentText,
            for: assistantMessageID,
            in: conversationID
        )
        attachAssistantUsage(
            usage,
            to: assistantMessageID,
            in: conversationID,
            configuration: configuration
        )

        let backgroundNotificationTitle = conversations
            .first(where: { $0.id == conversationID })?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationTitle = backgroundNotificationTitle?.isEmpty == false
            ? backgroundNotificationTitle ?? "MewyAI"
            : "MewyAI"
        backgroundCompletionNotificationCoordinator.deliverCompletionNotificationIfNeeded(
            assistantMessageID: assistantMessageID,
            conversationID: conversationID,
            privateConversationID: privateConversationID,
            contentText: contentText,
            title: notificationTitle,
            onPendingCountChanged: {
                updateBackgroundRequestKeeper()
            }
        )

        if selectedConversationID == conversationID {
            triggerOutputCompletionHapticIfNeeded()
            markdownRenderCache.prepareChatCache(for: assistantMessageID, in: messages, colorScheme: colorScheme)
        }

        finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            marksStopped: false,
            triggersCompletionHaptic: false
        )
        persistConversation(conversationID, refreshesUpdatedAt: true)
        generateTitleIfNeeded(for: conversationID, configuration: configuration)
        extractMemoriesIfNeeded(for: conversationID, configuration: configuration)
        updateHistorySummaryIfNeeded(for: conversationID, configuration: configuration)
    }

    private func attachAssistantUsage(
        _ usage: ChatUsage?,
        to assistantMessageID: UUID,
        in conversationID: UUID,
        configuration: AIConfiguration
    ) {
        guard let stampedUsage = ChatSessionViewModel.stampedAssistantUsage(
            usage,
            modelName: configuration.selectedModel,
            configurationID: configuration.id
        ) else { return }

        if selectedConversationID == conversationID {
            chatSession.setVisibleAssistantUsage(
                stampedUsage,
                for: assistantMessageID,
                in: conversationID,
                visibleConversationID: selectedConversationID
            )
            return
        }

        ConversationPersistenceCoordinator.setStoredAssistantUsage(
            stampedUsage,
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        )
    }

    private func synchronizeCompletedAssistantContent(
        _ contentText: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard !contentText.isEmpty else { return }

        if selectedConversationID == conversationID {
            if chatSession.synchronizeVisibleCompletedAssistantContent(
                contentText,
                for: assistantMessageID,
                in: conversationID,
                visibleConversationID: selectedConversationID
            ) {
                markdownRenderCache.invalidate(for: assistantMessageID)
            }
            return
        }

        ConversationPersistenceCoordinator.synchronizeStoredAssistantContent(
            contentText,
            for: assistantMessageID,
            in: conversationID,
            conversations: &conversations
        )
    }

    private func failStreamingResponse(
        _ error: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        cancelScheduledFlush(for: conversationID)
        flushPendingTokens(
            for: assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: false
        )

        let persistentError = ChatStreamingErrorPresentation.persistentAssistantMessage(from: error)

        if selectedConversationID == conversationID {
            if chatSession.setVisibleAssistantErrorContent(
                persistentError,
                for: assistantMessageID,
                in: conversationID,
                visibleConversationID: selectedConversationID
            ) {
                publishLiveContentUpdate(for: assistantMessageID, chunks: [persistentError], resetsText: true)
                markdownRenderCache.prepareChatCache(for: assistantMessageID, in: messages, colorScheme: colorScheme)
            }
        } else {
            ConversationPersistenceCoordinator.setStoredAssistantContent(
                persistentError,
                for: assistantMessageID,
                in: conversationID,
                conversations: &conversations
            )
        }

        finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            marksStopped: false,
            triggersCompletionHaptic: false
        )
        persistConversation(conversationID, refreshesUpdatedAt: true)
    }

    private func finishActiveGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        marksStopped: Bool,
        triggersCompletionHaptic: Bool
    ) {
        guard let finishResult = chatSession.finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            visibleConversationID: selectedConversationID,
            marksStopped: marksStopped
        ) else { return }

        if finishResult.shouldMarkStopped {
            if let stoppedUpdate = ConversationPersistenceCoordinator.setAssistantStopped(
                true,
                for: finishResult.assistantMessageID,
                in: finishResult.conversationID,
                selectedConversationID: selectedConversationID,
                messages: &messages,
                conversations: &conversations
            ) {
                switch stoppedUpdate {
                case .selected:
                    persistCurrentConversation(refreshesUpdatedAt: false)
                case .stored:
                    saveConversationsPreservingSelectedConversation()
                }
            }
        }

        if finishResult.didCompleteVisibleGeneration {
            if triggersCompletionHaptic {
                triggerOutputCompletionHapticIfNeeded()
            }
            streamingOutputHaptics.reset()
        }

        updateBackgroundRequestKeeper()
    }

    private func cancelActiveGeneration(
        in conversationID: UUID,
        marksStopped: Bool,
        triggersCompletionHaptic: Bool = false
    ) {
        guard let cancellation = chatSession.cancelActiveGeneration(
            in: conversationID,
            visibleConversationID: selectedConversationID
        ) else { return }

        flushPendingTokens(
            for: cancellation.assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: selectedConversationID == conversationID
        )
        finishActiveGeneration(
            for: cancellation.assistantMessageID,
            in: conversationID,
            marksStopped: marksStopped,
            triggersCompletionHaptic: triggersCompletionHaptic
        )
    }

    private func appendAssistantError(_ content: String) {
        let result = chatSession.appendAssistantError(content)
        markdownRenderCache.prepareChatCache(
            for: result.messageID,
            content: result.content,
            colorScheme: colorScheme
        )
        persistCurrentConversation()
    }

    private func handleStreamingTurnPreparationFailure(
        _ failure: ChatSessionViewModel.StreamingTurnPreparationFailure
    ) {
        guard let message = ChatStreamingErrorPresentation.assistantMessage(for: failure) else { return }
        appendAssistantError(message)
    }

    private func saveImageContextDescription(
        _ description: String,
        for messageID: UUID,
        in conversationID: UUID,
        matching imageAttachments: [ChatImageAttachment]
    ) {
        let result = ConversationPersistenceCoordinator.saveImageContextDescription(
            description,
            for: messageID,
            in: conversationID,
            matching: imageAttachments,
            selectedConversationID: selectedConversationID,
            messages: &messages,
            conversations: &conversations
        )

        switch result {
        case .selected:
            persistCurrentConversation(refreshesUpdatedAt: false)
        case .stored, .revisionsOnly:
            saveConversationsPreservingSelectedConversation()
        case .unchanged:
            break
        }
    }

    private func messageRevisionNavigationState(for messageID: UUID) -> MessageRevisionNavigationState? {
        ConversationPersistenceCoordinator.messageRevisionNavigationState(
            for: messageID,
            selectedConversationID: selectedConversationID,
            conversations: conversations
        )
    }

    private func selectMessageRevision(_ messageID: UUID, offset: Int) {
        messageInteraction.didTapBubble = true
        guard !isGenerating,
              let revisionMessages = ConversationPersistenceCoordinator.selectMessageRevision(
                messageID,
                offset: offset,
                selectedConversationID: selectedConversationID,
                currentMessages: messages,
                conversations: &conversations
              ) else {
            return
        }

        restoreSelectedMessageRevision(revisionMessages)
        persistCurrentConversation()
    }

    private func restoreSelectedMessageRevision(_ revisionMessages: [ChatMessage]) {
        speechInputController.cancelRecording()
        chatSession.replaceVisibleConversation(
            messages: revisionMessages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
            marksIdle: false
        )
        markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        inputDraft.clearText()
        resetSpeechInputMergeState()
        attachmentDraft.clear()
        messageInteraction.activeActionID = nil
        messageInteraction.editingMessageID = nil
        chatScrollController.restoreAfterConversationChange()
    }

    private func clearInputState() {
        speechInputController.cancelRecording()
        inputDraft.clearAndResignFocus()
        attachmentDraft.clear()
        messageInteraction.editingMessageID = nil
        resetSpeechInputMergeState()
    }

    private func startEditingUserMessage(_ id: UUID) {
        messageInteraction.didTapBubble = true

        guard !isGenerating,
              messageInteraction.editingMessageID != id,
              let message = messages.first(where: { $0.id == id && $0.role == "user" }) else {
            return
        }
        stopSpeechInputIfNeeded()

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            activateEditingInput(
                for: id,
                text: message.content,
                images: message.imageAttachments,
                files: message.fileAttachments
            )
            imageSelectionError = nil
            messageInteraction.activeActionID = nil
        }

        DispatchQueue.main.async {
            var focusTransaction = Transaction(animation: nil)
            focusTransaction.disablesAnimations = true

            withTransaction(focusTransaction) {
                inputDraft.requestFocus()
            }
        }
    }

    private func activateEditingInput(
        for id: UUID,
        text: String,
        images: [ChatImageAttachment],
        files: [ChatFileAttachment]
    ) {
        messageInteraction.editingMessageID = id
        inputDraft.setText(text)
        attachmentDraft.setEditingAttachments(images: images, files: files)
    }

    private func cancelEditingMessage() {
        stopSpeechInputIfNeeded()
        clearInputState()
    }

    @discardableResult
    private func saveEditingMessageOnly() -> Bool {
        stopSpeechInputIfNeeded()
        guard let editingMessageID = messageInteraction.editingMessageID else {
            clearInputState()
            return false
        }

        let edit = ConversationPersistenceCoordinator.UserMessageEdit(
            text: inputDraft.trimmedText,
            imageAttachments: pendingImageAttachments,
            fileAttachments: pendingFileAttachments
        )
        guard ConversationPersistenceCoordinator.saveUserMessageEdit(
            edit,
            for: editingMessageID,
            selectedConversationID: selectedConversationID,
            messages: &messages,
            conversations: &conversations
        ) else {
            clearInputState()
            return false
        }

        markdownRenderCache.invalidate(for: editingMessageID)
        persistCurrentConversation()
        removeUnreferencedConversationImages()
        clearInputState()
        return true
    }

    @discardableResult
    private func saveEditingMessageAndRegenerate() -> Bool {
        stopSpeechInputIfNeeded()
        guard !isGenerating,
              let editingMessageID = messageInteraction.editingMessageID else {
            clearInputState()
            return false
        }

        let edit = ConversationPersistenceCoordinator.UserMessageEdit(
            text: inputDraft.trimmedText,
            imageAttachments: pendingImageAttachments,
            fileAttachments: pendingFileAttachments
        )
        guard let request = ConversationPersistenceCoordinator.saveUserMessageEditAndPrepareRegeneration(
            edit,
            for: editingMessageID,
            selectedConversationID: selectedConversationID,
            messages: &messages,
            conversations: &conversations
        ) else {
            clearInputState()
            return false
        }

        pruneMarkdownCache()
        persistCurrentConversation()
        removeUnreferencedConversationImages()

        return startStreamingResponse(
            userText: request.userText,
            imageAttachments: request.imageAttachments,
            imageContextDescription: request.imageContextDescription,
            fileAttachments: request.fileAttachments,
            contextMessages: request.contextMessages,
            appendsUserMessage: false,
            existingUserMessageID: request.userMessageID
        )
    }

    private func regenerateAssistantResponse(_ id: UUID) {
        messageInteraction.didTapBubble = true

        guard !isGenerating,
              let request = ConversationPersistenceCoordinator.prepareAssistantResponseRegeneration(
                for: id,
                messages: &messages
              ) else {
            return
        }

        messageInteraction.activeActionID = nil
        pruneMarkdownCache()
        persistCurrentConversation()

        startStreamingResponse(
            userText: request.userText,
            imageAttachments: request.imageAttachments,
            imageContextDescription: request.imageContextDescription,
            fileAttachments: request.fileAttachments,
            contextMessages: request.contextMessages,
            appendsUserMessage: false,
            existingUserMessageID: request.userMessageID
        )
    }

    private func branchFromMessage(_ id: UUID) {
        messageInteraction.didTapBubble = true

        guard !isGenerating,
              let currentSelectionID = selectedConversationID,
              let sourceConversation = conversations.first(where: { $0.id == currentSelectionID }),
              let branch = ConversationPersistenceCoordinator.prepareBranchFromMessage(
                id,
                in: sourceConversation,
                messages: messages,
                activeSkillIDs: agentCapabilitySelection.activeSkillIDs,
                activeMCPServerIDs: agentCapabilitySelection.activeMCPServerIDs
              ) else {
            return
        }

        prepareCurrentConversationForNavigation()

        let newConversation = branch.conversation
        conversations.insert(newConversation, at: 0)
        selectedConversationID = newConversation.id

        chatSession.replaceVisibleConversation(
            messages: newConversation.messages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
            marksIdle: false
        )
        agentCapabilitySelection.restore(
            skillIDs: newConversation.activeSkillIDs,
            mcpServerIDs: newConversation.activeMCPServerIDs
        )
        markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        inputDraft.clearText()
        resetSpeechInputMergeState()
        attachmentDraft.clear()
        messageInteraction.activeActionID = nil
        messageInteraction.editingMessageID = nil
        chatScrollController.restoreAfterConversationChange()
        saveSelectedConversationIDIfStored(newConversation.id)
        saveStoredConversations()
        setConversationSidebarVisibility(false)

        let request = branch.generationRequest
        startStreamingResponse(
            userText: request.userText,
            imageAttachments: request.imageAttachments,
            imageContextDescription: request.imageContextDescription,
            fileAttachments: request.fileAttachments,
            contextMessages: request.contextMessages,
            appendsUserMessage: false,
            existingUserMessageID: request.userMessageID
        )
    }

    private func requestClearGeneratedContent(_ id: UUID) {
        messageInteraction.didTapBubble = true
        pendingClearGeneratedContentMessageID = id
    }

    private func confirmClearGeneratedContent() {
        guard let messageID = pendingClearGeneratedContentMessageID else { return }
        pendingClearGeneratedContentMessageID = nil
        clearGeneratedContent(messageID)
    }

    private func clearGeneratedContent(_ messageID: UUID) {
        if let selectedConversationID,
           activeGeneration(for: messageID, in: selectedConversationID) != nil {
            cancelActiveGeneration(
                in: selectedConversationID,
                marksStopped: false
            )
        }

        guard chatSession.clearGeneratedContent(for: messageID) else { return }

        markdownRenderCache.invalidate(for: messageID)
        withAnimation(.easeOut(duration: 0.16)) {
            messageInteraction.activeActionID = nil
        }
        persistCurrentConversation()
    }

    func scheduleTokenFlush(for messageID: UUID) {
        guard let selectedConversationID else { return }
        scheduleTokenFlush(for: messageID, in: selectedConversationID)
    }

    func scheduleTokenFlush(for messageID: UUID, in conversationID: UUID) {
        chatSession.scheduleTokenFlush(
            for: messageID,
            in: conversationID,
            visibleConversationID: selectedConversationID
        ) { messageID, conversationID in
            flushPendingTokens(
                for: messageID,
                in: conversationID,
                flushesReasoning: false,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }
    }

    func flushPendingTokens(
        for messageID: UUID,
        in conversationID: UUID,
        flushesReasoning: Bool = true,
        invalidatesMarkdownCache: Bool = true,
        requestsAutoScroll: Bool = true
    ) {
        guard let generation = activeGeneration(for: messageID, in: conversationID) else { return }

        if selectedConversationID == conversationID {
            flushPendingTokens(
                for: messageID,
                flushesReasoning: flushesReasoning,
                invalidatesMarkdownCache: invalidatesMarkdownCache,
                requestsAutoScroll: requestsAutoScroll
            )
            return
        }

        flushPendingTokensFromBackgroundGeneration(
            generation,
            flushesReasoning: flushesReasoning
        )
    }

    func flushPendingTokens(
        for messageID: UUID,
        flushesReasoning: Bool = true,
        invalidatesMarkdownCache: Bool = true,
        requestsAutoScroll: Bool = true
    ) {
        guard let selectedConversationID else { return }

        var transaction = Transaction()
        transaction.animation = nil

        var flushResult: ChatSessionViewModel.TokenFlushResult?
        withTransaction(transaction) {
            flushResult = chatSession.flushVisiblePendingTokens(
                for: messageID,
                in: selectedConversationID,
                visibleConversationID: selectedConversationID,
                flushesReasoning: flushesReasoning,
                invalidatesMarkdownCache: invalidatesMarkdownCache,
                requestsAutoScroll: requestsAutoScroll
            )
        }

        guard let flushResult else { return }

        if flushResult.shouldInvalidateMarkdownCache {
            markdownRenderCache.invalidate(for: messageID)
        }

        if flushResult.shouldRequestAutoScroll {
            scheduleStreamingAutoScroll()
        }
    }

    func cancelScheduledFlush() {
        chatSession.cancelVisibleScheduledFlush()
    }

    private func cancelScheduledFlush(for conversationID: UUID) {
        chatSession.cancelScheduledFlush(
            in: conversationID,
            visibleConversationID: selectedConversationID
        )
    }

    private func flushPendingTokensFromBackgroundGeneration(
        _ generation: ActiveConversationGeneration,
        flushesReasoning: Bool
    ) {
        let flushResult = ConversationPersistenceCoordinator.flushBackgroundPendingTokens(
            from: generation,
            conversations: &conversations,
            flushesReasoning: flushesReasoning
        )
        guard flushResult?.messageWasFound == true else { return }
        saveConversationsPreservingSelectedConversation()
    }

    private func appendLiveContentToken(_ token: String, for messageID: UUID) {
        publishLiveContentUpdate(for: messageID, chunks: [token], resetsText: false)
    }

    private func updateLiveReasoningDisplayIfNeeded(for messageID: UUID, token: String) {
        guard chatSession.shouldPublishLiveReasoningUpdate(for: messageID) else { return }

        publishLiveReasoningUpdate(
            for: messageID,
            chunks: [token],
            resetsText: false,
            appendsProgressively: token.utf16.count > Self.liveReasoningProgressiveAppendThreshold
        )
    }

    private func applyReasoningCollapseAfterThinking(
        _ effect: ChatSessionViewModel.ReasoningCollapseEffect,
        for messageID: UUID
    ) {
        if chatSession.applyReasoningCollapseAfterThinking(effect, for: messageID) {
            clearLiveReasoningDisplay(for: messageID)
        }
    }

    private func handleReasoningExpansionChange(for messageID: UUID, isExpanded: Bool) {
        guard chatSession.setReasoningExpansion(
            isExpanded,
            for: messageID,
            in: selectedConversationID
        ) else { return }

        if isExpanded {
            publishLiveReasoningReset(for: messageID, appendsProgressively: true)
        } else {
            clearLiveReasoningDisplay(for: messageID)
        }
    }

    private func publishLiveReasoningReset(
        for messageID: UUID,
        appendsProgressively: Bool
    ) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }

        var chunks: [String] = []
        if !message.reasoningContent.isEmpty {
            chunks.append(message.reasoningContent)
        }
        chunks.append(contentsOf: message.reasoningChunks)
        chunks.append(contentsOf: chatSession.streamingReasoningChunksSnapshot)

        publishLiveReasoningUpdate(
            for: messageID,
            chunks: chunks,
            resetsText: true,
            appendsProgressively: appendsProgressively
        )
    }

    private func publishLiveReasoningUpdate(
        for messageID: UUID,
        chunks: [String],
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        guard let reasoningChannel = chatSession.liveReasoningChannel(for: messageID) else { return }

        reasoningChannel.publish(
            chunks: chunks,
            resetsText: resetsText,
            appendsProgressively: appendsProgressively
        )
        triggerStreamingOutputHapticIfNeeded(chunks: chunks, resetsText: resetsText)
    }

    private func clearLiveReasoningDisplay(for messageID: UUID) {
        publishLiveReasoningUpdate(for: messageID, chunks: [], resetsText: true)
    }

    private func resetLiveContentDisplay(for messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }

        publishLiveContentUpdate(
            for: messageID,
            chunks: message.content.isEmpty ? [] : [message.content],
            resetsText: true
        )
    }

    private func publishLiveContentUpdate(for messageID: UUID, chunks: [String], resetsText: Bool) {
        guard let contentChannel = chatSession.liveContentChannel(for: messageID) else { return }

        contentChannel.publish(chunks: chunks, resetsText: resetsText)
        triggerStreamingOutputHapticIfNeeded(chunks: chunks, resetsText: resetsText)
    }

    private func triggerStreamingOutputHapticIfNeeded(chunks: [String], resetsText: Bool) {
        guard isHapticFeedbackEnabled,
              !resetsText,
              chunks.contains(where: { !$0.isEmpty }) else { return }

        streamingOutputHaptics.impactForOutputRefresh(chunks: chunks)
    }

    private func prepareStreamingOutputHapticsIfNeeded() {
        guard isHapticFeedbackEnabled else {
            streamingOutputHaptics.reset()
            return
        }

        streamingOutputHaptics.prepareForStreaming()
    }

    private func triggerOutputCompletionHapticIfNeeded() {
        guard isHapticFeedbackEnabled else { return }
        streamingOutputHaptics.impactForOutputCompletion()
    }

    private func triggerConversationActionHapticIfNeeded() {
        guard isHapticFeedbackEnabled else { return }
        conversationActionHaptics.impact()
    }

    private func pruneLiveAssistantDisplays() {
        let messageIDs = Set(messages.map(\.id))
        chatSession.pruneLiveAssistantDisplays(validMessageIDs: messageIDs)
    }

    private func scheduleStreamingAutoScroll() {
        chatScrollController.scheduleStreamingAutoScroll()
    }

    private static let liveReasoningProgressiveAppendThreshold = 720

    private func pruneMarkdownCache() {
        let messageIDs = Set(messages.map(\.id))
        markdownRenderCache.prune(validMessageIDs: messageIDs)
        pruneLiveAssistantDisplays()
    }

    func stopGenerating(triggersCompletionHaptic: Bool = true) {
        guard let selectedConversationID,
              let cancellation = chatSession.cancelActiveGeneration(
                  in: selectedConversationID,
                  visibleConversationID: selectedConversationID
              ) else {
            detachVisibleGenerationState()
            return
        }

        flushPendingTokens(
            for: cancellation.assistantMessageID,
            in: selectedConversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: true
        )
        markdownRenderCache.prepareChatCache(
            for: cancellation.assistantMessageID,
            in: messages,
            colorScheme: colorScheme
        )
        finishActiveGeneration(
            for: cancellation.assistantMessageID,
            in: selectedConversationID,
            marksStopped: true,
            triggersCompletionHaptic: triggersCompletionHaptic
        )
        persistConversation(selectedConversationID, refreshesUpdatedAt: true)
    }

    func hideKeyboard() {
        inputDraft.isFocused = false
        KeyboardDismissal.dismissNowAndDeferred()
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        guard let request = ChatAttachmentInputHandler.prepareSelectedImageLoad(
            from: items,
            supportsImages: currentConfiguration.selectedModelSupportsImages,
            storesImagesLocally: !isPrivateConversationSelected,
            draft: &attachmentDraft
        ) else { return }

        Task {
            let attachments = await ChatAttachmentLoader.imageAttachments(
                from: request.items,
                storesLocally: request.storesImagesLocally
            )

            ChatAttachmentInputHandler.applySelectedImageLoadResult(
                attachments,
                originalItemCount: request.itemCount,
                draft: &attachmentDraft
            )
        }
    }

    private func handleCameraImage(_ image: UIImage) {
        attachmentDraft.isCameraPresented = false

        guard currentConfiguration.selectedModelSupportsImages else {
            attachmentDraft.rejectImagesUnsupported(message: AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            ))
            return
        }

        if !isPrivateConversationSelected, isSaveCapturedPhotosToLibraryEnabled {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        guard let attachment = ChatAttachmentLoader.imageAttachment(
            from: image,
            storesLocally: !isPrivateConversationSelected
        ) else {
            attachmentDraft.appendPendingImageAttachments(
                [],
                source: AppLocalizations.string("attachment.source.camera", defaultValue: "camera"),
                supportsImages: true
            )
            return
        }

        attachmentDraft.appendPendingImageAttachments(
            [attachment],
            source: AppLocalizations.string("attachment.source.camera", defaultValue: "camera"),
            supportsImages: true
        )
    }

    private func handleDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        guard let request = ChatAttachmentInputHandler.prepareDroppedImageLoad(
            from: providers,
            supportsImages: currentConfiguration.selectedModelSupportsImages,
            storesImagesLocally: !isPrivateConversationSelected,
            draft: &attachmentDraft
        ) else { return false }

        Task {
            let attachments = await ChatAttachmentLoader.imageAttachments(
                from: request.providers,
                storesLocally: request.storesImagesLocally
            )

            ChatAttachmentInputHandler.applyImageProviderLoadResult(
                attachments,
                request: request,
                supportsImages: currentConfiguration.selectedModelSupportsImages,
                draft: &attachmentDraft
            )
        }

        return true
    }

    private func loadSelectedFiles(_ result: Result<[URL], Error>) {
        guard let request = ChatAttachmentInputHandler.prepareSelectedFileLoad(
            from: result,
            draft: &attachmentDraft
        ) else { return }

        Task {
            let result = ChatAttachmentLoader.fileAttachments(from: request.urls)

            ChatAttachmentInputHandler.applySelectedFileLoadResult(
                result,
                request: request,
                draft: &attachmentDraft
            )
        }
    }

    private func handleDroppedAttachments(_ providers: [NSItemProvider]) -> Bool {
        let handledImages = handleDroppedImages(providers)
        let handledFiles = handleDroppedFiles(providers)
        return handledImages || handledFiles
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let request = ChatAttachmentInputHandler.prepareDroppedFileLoad(from: providers) else { return false }

        Task {
            let attachments = await ChatAttachmentLoader.fileAttachments(from: request.providers)

            ChatAttachmentInputHandler.applyFileProviderLoadResult(
                attachments,
                request: request,
                draft: &attachmentDraft
            )
        }

        return true
    }

    private func pasteImageProvidersFromInputMenu(_ providers: [NSItemProvider]) {
        guard let request = ChatAttachmentInputHandler.preparePastedImageLoad(
            from: providers,
            supportsImages: currentConfiguration.selectedModelSupportsImages,
            storesImagesLocally: !isPrivateConversationSelected,
            draft: &attachmentDraft
        ) else { return }

        Task {
            let attachments = await ChatAttachmentLoader.imageAttachments(
                from: request.providers,
                storesLocally: request.storesImagesLocally
            )

            ChatAttachmentInputHandler.applyImageProviderLoadResult(
                attachments,
                request: request,
                supportsImages: currentConfiguration.selectedModelSupportsImages,
                draft: &attachmentDraft
            )
        }
    }

    private func removePendingImage(_ id: UUID) {
        attachmentDraft.removePendingImage(id)
        removeUnreferencedConversationImages()
    }

    private func removePendingFile(_ id: UUID) {
        attachmentDraft.removePendingFile(id)
    }

    private func selectModel(_ model: String) {
        AIConfigurationSelectionCoordinator.selectModel(
            model,
            currentConfiguration: currentConfiguration,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID,
            attachmentDraft: &attachmentDraft
        )
    }

    private func selectReasoningEffort(_ effort: ReasoningEffort) {
        AIConfigurationSelectionCoordinator.selectReasoningEffort(
            effort,
            currentConfiguration: currentConfiguration,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    private func setReasoningEnabled(_ isEnabled: Bool) {
        AIConfigurationSelectionCoordinator.setReasoningEnabled(
            isEnabled,
            currentConfiguration: currentConfiguration,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    @discardableResult
    private func selectBuiltInDefaultPromptForCurrentConfiguration() -> AIConfiguration {
        AIConfigurationSelectionCoordinator.selectBuiltInDefaultPrompt(
            currentConfiguration: currentConfiguration,
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    private func reloadConfigurations() {
        AIConfigurationSelectionCoordinator.reload(
            configurations: &configurations,
            selectedConfigurationID: &selectedConfigurationID
        )
    }

    private func loadSelectedConversation() {
        if let selectedConversationID,
           let conversation = fullConversationIfNeeded(id: selectedConversationID) {
            restoreConversation(conversation, closesSidebar: false)
        } else if let firstConversation = conversations.first {
            restoreConversation(fullConversationIfNeeded(firstConversation), closesSidebar: false)
        } else {
            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            chatSession.replaceVisibleConversation(
                messages: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
                marksIdle: false
            )
            agentCapabilitySelection.restore(
                skillIDs: conversation.activeSkillIDs,
                mcpServerIDs: conversation.activeMCPServerIDs
            )
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
            chatScrollController.restoreAfterConversationChange()
            saveSelectedConversationIDIfStored(conversation.id)
            saveStoredConversations()
        }
    }

    private func ensureCurrentConversation() {
        let result = ConversationPersistenceCoordinator.ensureCurrentConversation(
            conversations: &conversations,
            selectedConversationID: &selectedConversationID
        )
        guard let conversation = result.conversation else { return }

        agentCapabilitySelection.clear()
        saveSelectedConversationIDIfStored(conversation.id)
        saveStoredConversations()
    }

    private func selectConversation(_ id: UUID) {
        selectConversation(id, closesSidebar: true)
    }

    private func selectConversation(_ id: UUID, closesSidebar: Bool) {
        guard id != privateConversationID,
              let conversation = fullConversationIfNeeded(id: id) else {
            return
        }

        if isPrivateConversationSelected {
            discardPrivateConversation()
        } else {
            prepareCurrentConversationForNavigation()
        }

        restoreConversation(conversation, closesSidebar: closesSidebar)
    }

    private func prepareCurrentConversationForNavigation() {
        if let selectedConversationID,
           let generation = chatSession.activeGeneration(in: selectedConversationID) {
            cancelScheduledFlush(for: selectedConversationID)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: selectedConversationID,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
            persistConversation(selectedConversationID, refreshesUpdatedAt: false)
        } else {
            persistCurrentConversation(refreshesUpdatedAt: false)
        }

        detachVisibleGenerationState()
    }

    private func discardPrivateConversation() {
        guard let privateConversationID else { return }

        if let cancellation = chatSession.cancelActiveGeneration(
            in: privateConversationID,
            visibleConversationID: selectedConversationID
        ) {
            _ = chatSession.finishActiveGeneration(
                for: cancellation.assistantMessageID,
                in: privateConversationID,
                visibleConversationID: selectedConversationID,
                marksStopped: false
            )
        }

        let wasSelected = selectedConversationID == privateConversationID
        conversations.removeAll { $0.id == privateConversationID }
        self.privateConversationID = nil

        if wasSelected {
            speechInputController.cancelRecording()
            selectedConversationID = nil
            chatSession.replaceVisibleConversation(
                messages: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
                marksIdle: true
            )
            agentCapabilitySelection.clear()
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
            inputDraft.clearText()
            resetSpeechInputMergeState()
            attachmentDraft.clear()
            messageInteraction.activeActionID = nil
            messageInteraction.editingMessageID = nil
            chatScrollController.restoreAfterConversationChange()
            ConversationStore.clearSelectedConversationID()
        }

        updateBackgroundRequestKeeper()
        removeUnreferencedConversationImages()
    }

    private func detachVisibleGenerationState() {
        chatSession.detachVisibleGenerationState()
        streamingOutputHaptics.reset()
    }

    private func attachVisibleGenerationStateIfNeeded(for conversationID: UUID) {
        guard let generation = chatSession.activeGeneration(in: conversationID) else {
            chatSession.clearVisibleGenerationSelection()
            return
        }

        chatSession.bindVisibleGeneration(generation)
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: false,
            requestsAutoScroll: false
        )
        resetLiveContentDisplay(for: generation.assistantMessageID)
        if generation.reasoningIsExpanded {
            publishLiveReasoningReset(for: generation.assistantMessageID, appendsProgressively: true)
        }
        prepareStreamingOutputHapticsIfNeeded()
    }

    private func restoreConversation(_ conversation: AIConversation, closesSidebar: Bool) {
        speechInputController.cancelRecording()
        selectedConversationID = conversation.id
        chatSession.replaceVisibleConversation(
            messages: conversation.messages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
            marksIdle: false
        )
        agentCapabilitySelection.restore(
            skillIDs: conversation.activeSkillIDs,
            mcpServerIDs: conversation.activeMCPServerIDs
        )
        markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        inputDraft.clearText()
        resetSpeechInputMergeState()
        attachmentDraft.clear()
        messageInteraction.activeActionID = nil
        messageInteraction.editingMessageID = nil
        chatScrollController.restoreAfterConversationChange()
        attachVisibleGenerationStateIfNeeded(for: conversation.id)
        saveSelectedConversationIDIfStored(conversation.id)

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func openConfigurationFromSidebar(closesSidebar: Bool) {
        hideKeyboard()
        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
        showConfiguration = true
    }

    private func handleTopConversationAction() {
        if showsTemporaryChatNotice {
            exitTemporaryConversation()
        } else if showsPrivateConversationAction {
            startPrivateConversation(closesSidebar: true)
        } else {
            createConversation()
        }
    }

    private func createConversation() {
        createConversation(closesSidebar: true)
    }

    private func startPrivateConversation(closesSidebar: Bool) {
        guard canCreateConversation,
              currentConversationIsBlank,
              !isPrivateConversationSelected else {
            createConversation(closesSidebar: closesSidebar)
            return
        }

        let defaultPromptConfiguration = selectBuiltInDefaultPromptForCurrentConfiguration()
        discardPrivateConversation()
        prepareCurrentConversationForNavigation()

        let conversation = AIConversation()
        privateConversationID = conversation.id
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        chatSession.replaceVisibleConversation(
            messages: [],
            systemPrompt: defaultPromptConfiguration.systemPrompt,
            usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages,
            marksIdle: true
        )
        agentCapabilitySelection.clear()
        markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        speechInputController.cancelRecording()
        inputDraft.clearText()
        resetSpeechInputMergeState()
        attachmentDraft.clear()
        messageInteraction.activeActionID = nil
        messageInteraction.editingMessageID = nil
        chatScrollController.restoreAfterConversationChange()
        ConversationStore.clearSelectedConversationID()

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func exitTemporaryConversation() {
        guard showsTemporaryChatNotice else { return }

        discardPrivateConversation()

        if let emptyConversation = storedConversations.first(where: { !$0.hasInformation }) {
            restoreConversation(emptyConversation, closesSidebar: false)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        restoreConversation(conversation, closesSidebar: false)
        saveStoredConversations()
    }

    private func createConversation(closesSidebar: Bool) {
        guard canCreateConversation else {
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        let defaultPromptConfiguration = selectBuiltInDefaultPromptForCurrentConfiguration()

        let wasPrivateConversationSelected = isPrivateConversationSelected
        if wasPrivateConversationSelected {
            discardPrivateConversation()
        } else {
            prepareCurrentConversationForNavigation()
        }

        if !wasPrivateConversationSelected, currentConversationIsBlank {
            chatSession.replaceVisibleConversation(
                messages: [],
                systemPrompt: defaultPromptConfiguration.systemPrompt,
                usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages,
                marksIdle: true
            )
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        if let emptyConversation = storedConversations.first(where: { conversation in
            conversation.id != selectedConversationID && !conversation.hasInformation
        }) {
            selectConversation(emptyConversation.id, closesSidebar: closesSidebar)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        chatSession.replaceVisibleConversation(
            messages: [],
            systemPrompt: defaultPromptConfiguration.systemPrompt,
            usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages,
            marksIdle: true
        )
        agentCapabilitySelection.clear()
        markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
        speechInputController.cancelRecording()
        inputDraft.clearText()
        resetSpeechInputMergeState()
        attachmentDraft.clear()
        messageInteraction.activeActionID = nil
        messageInteraction.editingMessageID = nil
        chatScrollController.restoreAfterConversationChange()
        saveSelectedConversationIDIfStored(conversation.id)
        saveStoredConversations()

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func beginRenamingConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        hideKeyboard()
        conversationRenameDraft.begin(conversation: conversation)
    }

    private func commitRenamingConversation() {
        guard let renamingConversationID = conversationRenameDraft.conversationID else {
            resetRenamingConversationState()
            return
        }

        renameConversation(id: renamingConversationID, title: conversationRenameDraft.title)
        resetRenamingConversationState()
    }

    private func resetRenamingConversationState() {
        conversationRenameDraft.reset()
    }

    private func renameConversation(id: UUID, title: String) {
        persistCurrentConversation(refreshesUpdatedAt: false)
        guard ConversationPersistenceCoordinator.renameConversation(
            id: id,
            title: title,
            conversations: &conversations
        ) else { return }
        saveStoredConversations()
    }

    private func toggleConversationPin(_ id: UUID) {
        persistCurrentConversation(refreshesUpdatedAt: false)
        guard ConversationPersistenceCoordinator.toggleConversationPin(
            id: id,
            conversations: &conversations
        ) else { return }
        saveStoredConversations()
    }

    private func beginExportingConversation(_ id: UUID) {
        hideKeyboard()

        if let generation = chatSession.activeGeneration(in: id) {
            cancelScheduledFlush(for: id)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: id,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }

        persistConversation(id, refreshesUpdatedAt: false)

        guard let conversation = fullConversationIfNeeded(id: id) else { return }
        conversationExportDraft.prepare(for: conversation)
    }

    private func deleteConversation(_ id: UUID) {
        cancelActiveGeneration(in: id, marksStopped: false)

        let deletion = ConversationPersistenceCoordinator.deleteConversation(
            id,
            selectedConversationID: selectedConversationID,
            conversations: &conversations
        )

        if deletion.didReplaceWithNewConversation,
           let conversation = deletion.selectedConversation {
            selectedConversationID = conversation.id
            chatSession.replaceVisibleConversation(
                messages: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
                marksIdle: true
            )
            agentCapabilitySelection.clear()
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
            speechInputController.cancelRecording()
            inputDraft.clearText()
            resetSpeechInputMergeState()
            attachmentDraft.clear()
            messageInteraction.activeActionID = nil
            messageInteraction.editingMessageID = nil
            chatScrollController.restoreAfterConversationChange()
            setConversationSidebarVisibility(false)
            saveSelectedConversationIDIfStored(conversation.id)
            saveStoredConversations()
            removeUnreferencedConversationImages()
            return
        }

        if let selectedConversation = deletion.selectedConversation {
            let nextConversation = fullConversationIfNeeded(selectedConversation)
            selectedConversationID = nextConversation.id
            chatSession.replaceVisibleConversation(
                messages: nextConversation.messages,
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages,
                marksIdle: false
            )
            agentCapabilitySelection.restore(
                skillIDs: nextConversation.activeSkillIDs,
                mcpServerIDs: nextConversation.activeMCPServerIDs
            )
            markdownRenderCache.resetChatCaches(for: messages, colorScheme: colorScheme)
            attachmentDraft.clear()
            messageInteraction.activeActionID = nil
            messageInteraction.editingMessageID = nil
            chatScrollController.restoreAfterConversationChange()
            attachVisibleGenerationStateIfNeeded(for: nextConversation.id)
            saveSelectedConversationIDIfStored(nextConversation.id)
        }

        saveStoredConversations()
        removeUnreferencedConversationImages()
    }

    private func persistApplicationStateForLifecycle() {
        let activeConversationIDs = chatSession.activeConversationIDs
        for conversationID in activeConversationIDs {
            guard let generation = chatSession.activeGeneration(in: conversationID) else { continue }
            cancelScheduledFlush(for: conversationID)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: conversationID,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
            persistConversation(
                conversationID,
                refreshesUpdatedAt: true
            )
        }

        if let selectedConversationID,
           !activeConversationIDs.contains(selectedConversationID) {
            persistCurrentConversation(synchronize: true, refreshesUpdatedAt: false)
        } else {
            saveStoredConversations(synchronize: true)
        }

        updateBackgroundRequestKeeper()
    }

    private func persistConversation(
        _ conversationID: UUID,
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        if selectedConversationID == conversationID {
            persistCurrentConversation(
                synchronize: synchronize,
                refreshesUpdatedAt: refreshesUpdatedAt
            )
            return
        }

        guard ConversationPersistenceCoordinator.prepareStoredConversationForPersistence(
            conversationID,
            conversations: &conversations,
            refreshesUpdatedAt: refreshesUpdatedAt
        ) else { return }
        saveConversationsPreservingSelectedConversation(synchronize: synchronize)
    }

    private func updateBackgroundRequestKeeper() {
        backgroundRequestKeeper.update(
            activeRequestCount: chatSession.activeConversationGenerationCount
                + backgroundCompletionNotificationCoordinator.pendingNotificationCount
                + chatSessionPostProcessor.activeHistorySummaryUpdateCount,
            isSceneBackgrounded: UIApplication.shared.applicationState != .active
        ) {
            persistApplicationStateForLifecycle()
        }
    }

    @discardableResult
    private func saveStoredConversations(synchronize: Bool = false) -> Bool {
        let conversationsForStorage = storedConversations
        let didSave = ConversationPersistenceCoordinator.saveConversations(
            conversationsForStorage,
            synchronize: synchronize
        )
        if !didSave {
            conversationSaveErrorMessage = ConversationPersistenceCoordinator.saveFailureMessage
        }
        return didSave
    }

    @discardableResult
    private func saveConversationForStorage(_ conversationID: UUID, synchronize: Bool = false) -> Bool {
        guard conversationID != privateConversationID else { return true }
        let conversationsForStorage = storedConversations
        guard let conversation = conversationsForStorage.first(where: { $0.id == conversationID }) else {
            return false
        }

        let didSave = ConversationPersistenceCoordinator.saveConversation(
            conversation,
            in: conversationsForStorage,
            synchronize: synchronize
        )
        if !didSave {
            conversationSaveErrorMessage = ConversationPersistenceCoordinator.saveFailureMessage
        }
        return didSave
    }

    private func saveSelectedConversationIDIfStored(_ id: UUID) {
        ConversationPersistenceCoordinator.saveSelectedConversationIDIfStored(
            id,
            privateConversationID: privateConversationID,
            storedConversations: storedConversations
        )
    }

    @discardableResult
    private func saveConversationsPreservingSelectedConversation(synchronize: Bool = false) -> Bool {
        flushSelectedGenerationForStorage()
        synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: false)
        return saveStoredConversations(synchronize: synchronize)
    }

    private func flushSelectedGenerationForStorage() {
        guard let selectedConversationID,
              let generation = chatSession.activeGeneration(in: selectedConversationID) else {
            return
        }

        cancelScheduledFlush(for: selectedConversationID)
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: selectedConversationID,
            invalidatesMarkdownCache: false,
            requestsAutoScroll: false
        )
    }

    @discardableResult
    private func synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: Bool) -> Bool {
        ConversationPersistenceCoordinator.synchronizeSelectedConversationSnapshot(
            conversations: &conversations,
            selectedConversationID: selectedConversationID,
            messages: messages,
            activeSkillIDs: agentCapabilitySelection.activeSkillIDs,
            activeMCPServerIDs: agentCapabilitySelection.activeMCPServerIDs,
            refreshesUpdatedAt: refreshesUpdatedAt
        )
    }

    private func persistCurrentConversation(
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        guard synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: refreshesUpdatedAt) else {
            return
        }
        guard let selectedConversationID else { return }
        saveConversationForStorage(selectedConversationID, synchronize: synchronize)
    }

    // Folds a conversation written by an out-of-process source (App Intents)
    // into the in-memory `conversations` list so the running scene's next
    // save does not overwrite or prune it. If the conversation is the
    // currently selected one and not actively generating, the live message
    // list is refreshed to match disk. Concurrent generation on the same
    // conversation is an edge case where the in-flight stream will resync the
    // selected conversation on completion; the external write stays on disk
    // for the next launch even if the in-memory snapshot lags in that case.
    private func mergeExternalConversation(_ conversation: AIConversation?) {
        guard let conversation else { return }

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else if let emptyIndex = conversations.firstIndex(where: { !$0.hasInformation }) {
            conversations[emptyIndex] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }

        conversations.sort { $0.updatedAt > $1.updatedAt }

        guard selectedConversationID == conversation.id,
              !isGenerating else {
            return
        }

        chatSession.messages = conversation.messages
    }

    private func removeUnreferencedConversationImages() {
        var retainedConversations = fullyLoadedStoredConversations()
        if let selectedConversationID,
           selectedConversationID != privateConversationID,
           let index = retainedConversations.firstIndex(where: { $0.id == selectedConversationID }) {
            retainedConversations[index].messages = messages
        }
        let retainedPendingImageAttachments = isPrivateConversationSelected ? [] : pendingImageAttachments
        ConversationImageStore.removeUnreferencedImages(
            retainedBy: retainedConversations,
            additionalAttachments: retainedPendingImageAttachments
        )
    }

    private func generateTitleIfNeeded() {
        guard let selectedConversationID else { return }
        generateTitleIfNeeded(for: selectedConversationID, configuration: currentConfiguration)
    }

    private func generateTitleIfNeeded(for conversationID: UUID, configuration: AIConfiguration) {
        if selectedConversationID == conversationID {
            persistCurrentConversation(refreshesUpdatedAt: false)
        }

        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }

        chatSessionPostProcessor.generateTitleIfNeeded(
            for: conversation,
            configuration: configuration,
            privateConversationID: privateConversationID
        ) { conversationID, title in
            if self.selectedConversationID == conversationID {
                persistCurrentConversation(refreshesUpdatedAt: false)
            }

            guard let currentIndex = conversations.firstIndex(where: { $0.id == conversationID }),
                  !conversations[currentIndex].hasGeneratedTitle,
                  !title.isEmpty else {
                return
            }

            conversations[currentIndex].title = title
            conversations[currentIndex].hasGeneratedTitle = true
            saveConversationsPreservingSelectedConversation()
        }
    }

    private func extractMemoriesIfNeeded(for conversationID: UUID, configuration: AIConfiguration) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }

        chatSessionPostProcessor.extractMemoriesIfNeeded(
            for: conversation,
            configuration: configuration,
            isMemoryEnabled: { isGlobalMemoryEnabled },
            privateConversationID: privateConversationID
        )
    }

    private func updateHistorySummaryIfNeeded(for conversationID: UUID, configuration: AIConfiguration) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }

        chatSessionPostProcessor.updateHistorySummaryIfNeeded(
            for: conversation,
            configuration: configuration,
            isMemoryEnabled: { isGlobalMemoryEnabled },
            privateConversationID: privateConversationID
        ) {
            updateBackgroundRequestKeeper()
        }
    }

    private func updateMissingHistorySummariesIfNeeded(configuration: AIConfiguration) {
        chatSessionPostProcessor.updateMissingHistorySummariesIfNeeded(
            for: storedConversations,
            configuration: configuration,
            isMemoryEnabled: { isGlobalMemoryEnabled },
            privateConversationID: privateConversationID
        ) {
            updateBackgroundRequestKeeper()
        }
    }

}

#Preview {
    ContentView()
}
