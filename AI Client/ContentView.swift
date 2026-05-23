import SwiftUI
import Combine
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private enum ChatScrollMetrics {
    static let coordinateSpaceName = "ChatScrollCoordinateSpace"
    static let bottomThreshold: CGFloat = 32
}

private struct ChatScrollBottomDistancePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
private final class ChatScrollController: ObservableObject {
    @Published private var shouldAutoScroll = true
    @Published private var isScrolledToBottom = true

    private var isUserDragging = false
    private var isAutoScrollScheduled = false
    private var isBottomDistanceUpdateScheduled = false
    private var pendingDistanceFromBottom: CGFloat?
    private var autoScrollTask: Task<Void, Never>?
    private var scrollAction: ((Bool) -> Void)?

    var shouldShowScrollToBottomButton: Bool {
        !shouldAutoScroll && !isScrolledToBottom
    }

    deinit {
        autoScrollTask?.cancel()
    }

    func setScrollAction(_ action: @escaping (Bool) -> Void) {
        scrollAction = action
    }

    func clearScrollAction() {
        scrollAction = nil
    }

    func beginUserDrag() {
        isUserDragging = true

        guard !isScrolledToBottom else { return }
        setShouldAutoScroll(false)
        cancelScheduledAutoScroll()
    }

    func endUserDrag() {
        isUserDragging = false
    }

    func scheduleBottomDistanceUpdate(_ distanceFromBottom: CGFloat) {
        pendingDistanceFromBottom = distanceFromBottom

        guard !isBottomDistanceUpdateScheduled else { return }
        isBottomDistanceUpdateScheduled = true

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }

            let distanceFromBottom = pendingDistanceFromBottom ?? 0
            pendingDistanceFromBottom = nil
            isBottomDistanceUpdateScheduled = false
            updateBottomDistance(distanceFromBottom)
        }
    }

    private func updateBottomDistance(_ distanceFromBottom: CGFloat) {
        let isAtBottom = distanceFromBottom <= ChatScrollMetrics.bottomThreshold

        if isScrolledToBottom != isAtBottom {
            setIsScrolledToBottom(isAtBottom)
        }

        if isAtBottom {
            setShouldAutoScroll(true)
        } else if isUserDragging {
            setShouldAutoScroll(false)
            cancelScheduledAutoScroll()
        }
    }

    func returnToBottom() {
        setShouldAutoScroll(true)
        requestImmediateAutoScroll(animated: false)
    }

    func requestImmediateAutoScroll(animated: Bool = false) {
        guard shouldAutoScroll else { return }
        cancelScheduledAutoScroll()
        scrollAction?(animated)
    }

    func scheduleStreamingAutoScroll() {
        guard shouldAutoScroll else { return }
        guard !isAutoScrollScheduled else { return }
        isAutoScrollScheduled = true
        autoScrollTask?.cancel()

        autoScrollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard let self, !Task.isCancelled else { return }
            if shouldAutoScroll {
                scrollAction?(false)
            }
            isAutoScrollScheduled = false
            autoScrollTask = nil
        }
    }

    func cancelScheduledAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrollScheduled = false
    }

    private func setShouldAutoScroll(_ value: Bool) {
        guard shouldAutoScroll != value else { return }
        shouldAutoScroll = value
    }

    private func setIsScrolledToBottom(_ value: Bool) {
        guard isScrolledToBottom != value else { return }
        isScrolledToBottom = value
    }
}

private struct ScrollToBottomButtonOverlay<Label: View>: View {
    @ObservedObject var scrollController: ChatScrollController
    let label: () -> Label

    var body: some View {
        ZStack {
            if scrollController.shouldShowScrollToBottomButton {
                Button {
                    scrollController.returnToBottom()
                } label: {
                    label()
                }
                .buttonStyle(.plain)
                .padding(.bottom, 92)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: 0.18),
            value: scrollController.shouldShowScrollToBottomButton
        )
    }
}

@MainActor
private final class StreamingTokenBuffer {
    private var pendingReasoningChunks: [String] = []
    private var pendingContentChunks: [String] = []

    var hasPendingReasoningText: Bool {
        !pendingReasoningChunks.isEmpty
    }

    var hasPendingContentText: Bool {
        !pendingContentChunks.isEmpty
    }

    var reasoningChunksSnapshot: [String] {
        pendingReasoningChunks
    }

    func appendReasoning(_ text: String) {
        pendingReasoningChunks.append(text)
    }

    func appendContent(_ text: String) {
        pendingContentChunks.append(text)
    }

    func consumePendingReasoningChunks() -> [String] {
        let chunks = pendingReasoningChunks
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        return chunks
    }

    func consumePendingContentText() -> String {
        let text = pendingContentChunks.joined()
        pendingContentChunks.removeAll(keepingCapacity: true)
        return text
    }

    func clearPendingTokens() {
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        pendingContentChunks.removeAll(keepingCapacity: true)
    }

    func reset() {
        clearPendingTokens()
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var conversations = ConversationStore.loadConversations()
    @State private var selectedConversationID: UUID? = ConversationStore.loadSelectedConversationID()
    @State private var isGenerating = false
    @State private var showConfiguration = false
    @State private var showConversationSidebar = false
    @State private var chatScrollController = ChatScrollController()
    @State private var streamingTokenBuffer = StreamingTokenBuffer()
    @State private var activeAssistantHasReasoning = false
    @State private var activeAssistantHasContent = false
    @State private var activeAssistantReasoningIsExpanded = false
    @State private var activeAssistantDidCollapseReasoningAfterThinking = false
    @State private var liveAssistantReasoningChannel = StreamingTextUpdateChannel()
    @State private var liveAssistantContentChannel = StreamingTextUpdateChannel()
    @State private var isFlushScheduled = false
    @State private var flushTask: Task<Void, Never>?
    @State private var activeAssistantMessageID: UUID?
    @State private var markdownRenderCache: [UUID: MarkdownRenderCacheEntry] = [:]
    @State private var markdownRenderTasks: [UUID: Task<Void, Never>] = [:]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var pendingImageAttachments: [ChatImageAttachment] = []
    @State private var imageSelectionError: String?
    @State private var isImageDropTargeted = false
    @State private var activeMessageActionID: UUID?
    @State private var didTapMessageBubble = false
    @State private var editingMessageID: UUID?
    @State private var isInputFocused = false
    @State private var inputFocusRequestID = 0
    @State private var hasLoadedInitialConversation = false

    let aiService = AIService()
    private let maxImageAttachmentCount = 4
    private let inputBarBottomPadding: CGFloat = 8
    private let inputBottomFadeHeight: CGFloat = 178
    private let inputBottomFadeOverlap: CGFloat = 118

    private var inputGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.22)
    }

    private var inputGlassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.62)
    }

    private var sendControlBackground: Color {
        !canSendMessage && !isGenerating
            ? inputGlassTint
            : Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.16)
    }

    private var cancelControlBackground: Color {
        Color.red.opacity(colorScheme == .dark ? 0.24 : 0.12)
    }

    private var inputBottomFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.40) : Color.white.opacity(0.62)
    }

    @ViewBuilder
    private func inputGlassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)

        if #available(iOS 26.0, *) {
            content()
                .background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(inputGlassTint), in: shape)
                }
        } else {
            content()
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(inputGlassTint))
                .overlay(
                    shape
                        .stroke(inputGlassHighlight, lineWidth: 1)
                        .blendMode(.screen)
                )
        }
    }

    @ViewBuilder
    private func controlGlassBackground(_ tint: Color, isInteractive: Bool = true) -> some View {
        Circle()
            .fill(.thinMaterial)
            .overlay(Circle().fill(tint))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45), lineWidth: 1)
            )
    }

    private func controlGlassIcon(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight,
        frame: CGFloat,
        tint: Color,
        foreground: Color = .primary
    ) -> some View {
        ZStack {
            controlGlassBackground(tint)

            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(foreground)
        }
        .frame(width: frame, height: frame)
    }

    private var inputBottomFade: some View {
        Rectangle()
            .fill(.thickMaterial)
            .overlay(inputBottomFadeTint)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.08), location: 0.00),
                        .init(color: .black.opacity(0.18), location: 0.10),
                        .init(color: .black.opacity(0.36), location: 0.24),
                        .init(color: .black.opacity(0.66), location: 0.48),
                        .init(color: .black.opacity(0.90), location: 0.72),
                        .init(color: .black.opacity(1.00), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }

    private var canSendMessage: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingImageAttachments.isEmpty
    }

    private var isEditingMessage: Bool {
        editingMessageID != nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                mainContent
                    .disabled(showConversationSidebar)
                    .offset(x: showConversationSidebar ? min(geometry.size.width * 0.72, 320) : 0)
                    .animation(.easeOut(duration: 0.22), value: showConversationSidebar)

                if showConversationSidebar {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showConversationSidebar = false
                        }
                }

                if !showConversationSidebar {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 28)
                        .ignoresSafeArea()
                        .gesture(openSidebarGesture)
                }

                ConversationSidebarView(
                    conversations: conversations,
                    selectedConversationID: selectedConversationID,
                    onSelect: selectConversation,
                    onCreate: createConversation,
                    onDelete: deleteConversation,
                    canCreateConversation: canCreateConversation
                )
                .frame(width: min(geometry.size.width * 0.72, 320))
                .offset(x: showConversationSidebar ? 0 : -min(geometry.size.width * 0.72, 320))
                .animation(.easeOut(duration: 0.22), value: showConversationSidebar)
            }
            .simultaneousGesture(closeSidebarGesture)
        }
        .onAppear {
            guard !hasLoadedInitialConversation else { return }
            hasLoadedInitialConversation = true
            loadSelectedConversation()
        }
        .sheet(isPresented: $showConfiguration) {
            AIConfigurationView()
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: maxImageAttachmentCount,
            matching: .images
        )
        .onChange(of: showConfiguration) { _, isPresented in
            if !isPresented {
                reloadConfigurations()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadSelectedImages(from: newItems)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            persistApplicationStateForLifecycle()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            configurationBar

            Divider()

            ScrollViewReader { proxy in
                GeometryReader { scrollGeometry in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach($messages) { $message in
                                let isStreamingMessage = isGenerating && activeAssistantMessageID == message.id
                                let liveReasoningChannel = isStreamingMessage && activeAssistantReasoningIsExpanded
                                    ? liveAssistantReasoningChannel
                                    : nil
                                MessageBubble(
                                    message: $message,
                                    isStreaming: isStreamingMessage,
                                    hasStreamingReasoning: isStreamingMessage && activeAssistantHasReasoning,
                                    hasStreamingContent: isStreamingMessage && activeAssistantHasContent,
                                    streamingContentChannel: isStreamingMessage ? liveAssistantContentChannel : nil,
                                    streamingReasoningChannel: liveReasoningChannel,
                                    markdownRenderCache: markdownRenderCache[message.id],
                                    showsActions: activeMessageActionID == message.id,
                                    onSelect: {
                                        selectMessageAction(for: message.id)
                                    },
                                    onReasoningExpansionChanged: { isExpanded in
                                        handleReasoningExpansionChange(for: message.id, isExpanded: isExpanded)
                                    },
                                    onRegenerate: {
                                        regenerateAssistantResponse(message.id)
                                    },
                                    onEdit: {
                                        startEditingUserMessage(message.id)
                                    }
                                )
                                    .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottomAnchor")
                                .background(
                                    GeometryReader { bottomGeometry in
                                        Color.clear.preference(
                                            key: ChatScrollBottomDistancePreferenceKey.self,
                                            value: chatScrollBottomDistance(
                                                bottomGeometry: bottomGeometry,
                                                viewportHeight: scrollGeometry.size.height
                                            )
                                        )
                                    }
                                )
                        }
                        .padding()
                        .frame(
                            maxWidth: .infinity,
                            minHeight: scrollGeometry.size.height,
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                    }
                    .coordinateSpace(name: ChatScrollMetrics.coordinateSpaceName)
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in
                                chatScrollController.beginUserDrag()
                            }
                            .onEnded { _ in
                                chatScrollController.endUserDrag()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            DispatchQueue.main.async {
                                if didTapMessageBubble {
                                    didTapMessageBubble = false
                                    return
                                }

                                hideKeyboard()

                                withAnimation(.easeOut(duration: 0.16)) {
                                    activeMessageActionID = nil
                                }
                            }
                        }
                    )
                    .onChange(of: messages.count) { _, _ in
                        chatScrollController.requestImmediateAutoScroll(animated: true)
                    }
                    .onPreferenceChange(ChatScrollBottomDistancePreferenceKey.self) { distanceFromBottom in
                        chatScrollController.scheduleBottomDistanceUpdate(distanceFromBottom)
                    }
                    .onAppear {
                        chatScrollController.setScrollAction { animated in
                            forceScrollToBottom(proxy: proxy, animated: animated)
                        }
                    }
                    .onDisappear {
                        chatScrollController.clearScrollAction()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .overlay(alignment: .bottom) {
            ScrollToBottomButtonOverlay(scrollController: chatScrollController) {
                controlGlassIcon(
                    systemName: "arrow.down",
                    size: 15,
                    weight: .semibold,
                    frame: 36,
                    tint: inputGlassTint
                )
            }
        }
    }

    private var inputBar: some View {
        inputGlassContainer {
            VStack(alignment: .leading, spacing: 8) {
                if !pendingImageAttachments.isEmpty {
                    imageAttachmentPreview
                }

                if let imageSelectionError {
                    Text(imageSelectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                }

                if isEditingMessage {
                    Text("正在修改消息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                inputComposer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    isImageDropTargeted ? Color.accentColor.opacity(0.56) : Color.secondary.opacity(0.12),
                    lineWidth: isImageDropTargeted ? 2 : 1
                )
        )
        .onDrop(
            of: [UTType.image.identifier],
            isTargeted: $isImageDropTargeted,
            perform: handleDroppedImages
        )
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, inputBarBottomPadding)
        .background(alignment: .bottom) {
            inputBottomFade
                .frame(height: inputBottomFadeHeight)
                .offset(y: inputBottomFadeHeight - inputBottomFadeOverlap - inputBarBottomPadding)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var inputComposer: some View {
        inputComposerContent
    }

    private var inputComposerContent: some View {
        HStack(alignment: .center, spacing: 10) {
            inputOptionsMenu

            ImagePastingTextView(
                text: $inputText,
                isFocused: $isInputFocused,
                focusRequestID: inputFocusRequestID,
                placeholder: "输入消息...",
                onPasteImages: pasteImagesFromInputMenu
            )
            .font(.body)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)

            inputActionControl
        }
    }

    @ViewBuilder
    private var inputActionControl: some View {
        if isEditingMessage {
            HStack(spacing: 8) {
                Button {
                    cancelEditingMessage()
                } label: {
                    controlGlassIcon(
                        systemName: "xmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: cancelControlBackground,
                        foreground: .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消修改")

                Menu {
                    Button("仅修改") {
                        saveEditingMessageOnly()
                    }

                    Button("修改并发送") {
                        saveEditingMessageAndRegenerate()
                    }
                } label: {
                    controlGlassIcon(
                        systemName: "checkmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: sendControlBackground
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
            }
        } else {
            Button {
                if isGenerating {
                    stopGenerating()
                } else {
                    sendMessage()
                }
            } label: {
                controlGlassIcon(
                    systemName: isGenerating ? "stop.fill" : "paperplane.fill",
                    size: 19,
                    weight: .semibold,
                    frame: 48,
                    tint: sendControlBackground
                )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSendMessage)
        }
    }

    private var imageAttachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImageAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        DataURLImage(dataURL: attachment.dataURL)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            removePendingImage(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white, .black.opacity(0.60))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(currentConfiguration.models) { model in
                Button {
                    selectModel(model.name)
                } label: {
                    if model.name == currentConfiguration.selectedModel {
                        Label(model.name, systemImage: "checkmark")
                    } else {
                        Text(model.name)
                    }
                }
            }

            Divider()

            Button {
                hideKeyboard()
                showConfiguration = true
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
        } label: {
            controlGlassIcon(
                systemName: "cube.transparent",
                size: 19,
                weight: .semibold,
                frame: 48,
                tint: inputGlassTint
            )
        }
        .disabled(isGenerating)
    }

    private var topModelMenu: some View {
        Menu {
            ForEach(currentConfiguration.models) { model in
                Button {
                    selectModel(model.name)
                } label: {
                    if model.name == currentConfiguration.selectedModel {
                        Label(model.name, systemImage: "checkmark")
                    } else {
                        Text(model.name)
                    }
                }
            }

            Divider()

            Button {
                hideKeyboard()
                showConfiguration = true
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 4) {
                Text(configurationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .disabled(isGenerating)
    }

    private var inputOptionsMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label(
                    currentConfiguration.selectedModelSupportsImages ? "上传图片" : "当前模型不支持图片",
                    systemImage: "photo"
                )
            }
            .disabled(!currentConfiguration.selectedModelSupportsImages)

            if currentConfiguration.selectedModelSupportsReasoning {
                Divider()

                Button {
                    setReasoningEnabled(false)
                } label: {
                    if currentConfiguration.reasoningEnabled {
                        Text("思考强度：关闭")
                    } else {
                        Label("思考强度：关闭", systemImage: "checkmark")
                    }
                }

                ForEach(ReasoningEffort.allCases) { effort in
                    Button {
                        selectReasoningEffort(effort)
                    } label: {
                        if currentConfiguration.reasoningEnabled,
                           effort == currentConfiguration.reasoningEffort {
                            Label("思考强度：\(effort.title)", systemImage: "checkmark")
                        } else {
                            Text("思考强度：\(effort.title)")
                        }
                    }
                }
            }
        } label: {
            controlGlassIcon(
                systemName: "plus",
                size: 16,
                weight: .bold,
                frame: 34,
                tint: inputGlassTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多输入选项")
    }

    private var configurationBar: some View {
        HStack(spacing: 12) {
            Button {
                hideKeyboard()
                showConversationSidebar = true
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 4) {
                Text(currentConversationTitle)
                    .font(.headline)
                    .lineLimit(1)

                topModelMenu
            }

            Spacer()

            Button {
                hideKeyboard()
                createConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating || !canCreateConversation)

            Button {
                hideKeyboard()
                showConfiguration = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var openSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if !showConversationSidebar,
                   value.translation.width > 46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.6 {
                    hideKeyboard()
                    showConversationSidebar = true
                }
            }
    }

    private var closeSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                if showConversationSidebar,
                   value.translation.width < -46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    showConversationSidebar = false
                }
            }
    }

    private var currentConversationTitle: String {
        guard let selectedConversationID,
              let conversation = conversations.first(where: { $0.id == selectedConversationID }) else {
            return "新对话"
        }

        return conversation.title
    }

    private var canCreateConversation: Bool {
        !isGenerating
    }

    private var currentConversationIsBlank: Bool {
        messages.isEmpty
            && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingImageAttachments.isEmpty
    }

    private var currentConfiguration: AIConfiguration {
        AIConfigurationStore.selectedConfiguration(
            from: configurations,
            selectedID: selectedConfigurationID
        )
    }

    private var configurationSummary: String {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCustomHeaders = !configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let authSummary = hasAPIKey ? "API Key" : (hasCustomHeaders ? "自定义请求头" : "未配置认证")

        let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointSummary = endpoint.isEmpty ? "未配置 Endpoint" : endpoint
        let reasoningSummary = configuration.selectedModelSupportsReasoning
            ? (configuration.reasoningEnabled ? "思考 \(configuration.reasoningEffort.title)" : "思考关闭")
            : "无推理"
        let imageSummary = configuration.selectedModelSupportsImages ? "图片" : "文字"
        return "\(configuration.name) · \(configuration.selectedModel) · \(imageSummary) · \(reasoningSummary) · \(trimmedBaseURL.isEmpty ? "未配置 Base URL" : trimmedBaseURL) · \(endpointSummary) · \(authSummary)"
    }

    func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageAttachments = pendingImageAttachments
        ensureCurrentConversation()
        startStreamingResponse(
            userText: userText,
            imageAttachments: imageAttachments,
            contextMessages: messages,
            appendsUserMessage: true
        )
    }

    private func startStreamingResponse(
        userText: String,
        imageAttachments: [ChatImageAttachment],
        contextMessages: [ChatMessage],
        appendsUserMessage: Bool
    ) {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil

        guard !userText.isEmpty || !imageAttachments.isEmpty else { return }

        guard imageAttachments.isEmpty || configuration.selectedModelSupportsImages else {
            appendAssistantError("当前模型不支持图片输入，请切换到支持图片的多模态模型，或在配置页为该模型开启“支持图片”。")
            return
        }

        guard !trimmedBaseURL.isEmpty else {
            appendAssistantError("请先配置 Base URL。")
            return
        }

        guard !model.isEmpty else {
            appendAssistantError("请先选择模型。")
            return
        }

        aiService.resetConversation(with: contextMessages, systemPrompt: configuration.systemPrompt)
        clearInputState()
        isGenerating = true
        chatScrollController.returnToBottom()
        streamingTokenBuffer.reset()
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        clearLiveReasoningDisplay()
        clearLiveContentDisplay()
        isFlushScheduled = false
        activeMessageActionID = nil

        if appendsUserMessage {
            messages.append(
                ChatMessage(
                    role: "user",
                    content: userText,
                    imageAttachments: imageAttachments
                )
            )
        }

        let assistantMessage = ChatMessage(role: "assistant", content: "")
        messages.append(assistantMessage)
        invalidateMarkdownCache(for: assistantMessage.id)
        persistCurrentConversation()

        let assistantMessageID = assistantMessage.id
        activeAssistantMessageID = assistantMessageID

        aiService.sendStreamingMessage(
            message: userText,
            imageAttachments: imageAttachments,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            isReasoningDisplayActive: {
                activeAssistantMessageID == assistantMessageID && activeAssistantReasoningIsExpanded
            },
            onReasoningToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }

                streamingTokenBuffer.appendReasoning(token)
                if !activeAssistantHasReasoning {
                    activeAssistantHasReasoning = true
                }
                updateLiveReasoningDisplayIfNeeded(for: assistantMessageID, token: token)
            },
            onContentToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }

                collapseReasoningAfterThinkingIfNeeded(for: assistantMessageID)
                appendLiveContentToken(token)
                if !activeAssistantHasContent {
                    activeAssistantHasContent = true
                }
                streamingTokenBuffer.appendContent(token)
                scheduleTokenFlush(for: assistantMessageID)
                scheduleStreamingAutoScroll()
            },
            onComplete: { _ in
                guard activeAssistantMessageID == assistantMessageID else { return }

                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: true)
                isGenerating = false
                activeAssistantMessageID = nil
                activeAssistantHasReasoning = false
                activeAssistantHasContent = false
                activeAssistantReasoningIsExpanded = false
                activeAssistantDidCollapseReasoningAfterThinking = false
                clearLiveStreamingText()
                prepareMarkdownCache(for: assistantMessageID)
                persistCurrentConversation()
                generateTitleIfNeeded()
            },
            onError: { error in
                guard activeAssistantMessageID == assistantMessageID else { return }

                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: false)

                if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                    messages[index].content = error
                }

                isGenerating = false
                activeAssistantMessageID = nil
                activeAssistantHasReasoning = false
                activeAssistantHasContent = false
                activeAssistantReasoningIsExpanded = false
                activeAssistantDidCollapseReasoningAfterThinking = false
                clearLiveStreamingText()
                prepareMarkdownCache(for: assistantMessageID)
                persistCurrentConversation()
            }
        )
    }

    private func appendAssistantError(_ content: String) {
        let message = ChatMessage(role: "assistant", content: content)
        messages.append(message)
        prepareMarkdownCache(for: message.id, content: content)
        persistCurrentConversation()
    }

    private func clearInputState() {
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        editingMessageID = nil
        isInputFocused = false
        inputFocusRequestID += 1
    }

    private func startEditingUserMessage(_ id: UUID) {
        didTapMessageBubble = true

        guard !isGenerating,
              editingMessageID != id,
              let message = messages.first(where: { $0.id == id && $0.role == "user" }) else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            activateEditingInput(for: id, text: message.content, images: message.imageAttachments)
            imageSelectionError = nil
            activeMessageActionID = nil
        }

        DispatchQueue.main.async {
            var focusTransaction = Transaction(animation: nil)
            focusTransaction.disablesAnimations = true

            withTransaction(focusTransaction) {
                isInputFocused = true
                inputFocusRequestID += 1
            }
        }
    }

    private func activateEditingInput(for id: UUID, text: String, images: [ChatImageAttachment]) {
        editingMessageID = id
        inputText = text
        pendingImageAttachments = images
        selectedPhotoItems = []
    }

    private func selectMessageAction(for id: UUID) {
        didTapMessageBubble = true
        guard activeMessageActionID != id else { return }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                activeMessageActionID = id
            }
        }
    }

    private func cancelEditingMessage() {
        clearInputState()
    }

    private func saveEditingMessageOnly() {
        guard let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return
        }

        messages[index].content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages[index].imageAttachments = pendingImageAttachments
        invalidateMarkdownCache(for: editingMessageID)
        persistCurrentConversation()
        clearInputState()
    }

    private func saveEditingMessageAndRegenerate() {
        guard !isGenerating,
              let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return
        }

        let editedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedImages = pendingImageAttachments
        messages[index].content = editedText
        messages[index].imageAttachments = editedImages
        messages.removeSubrange((index + 1)..<messages.count)
        pruneMarkdownCache()
        let context = Array(messages.prefix(index))
        persistCurrentConversation()

        startStreamingResponse(
            userText: editedText,
            imageAttachments: editedImages,
            contextMessages: context,
            appendsUserMessage: false
        )
    }

    private func regenerateAssistantResponse(_ id: UUID) {
        didTapMessageBubble = true

        guard !isGenerating,
              let assistantIndex = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }),
              let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == "user" }) else {
            return
        }

        activeMessageActionID = nil
        let userMessage = messages[userIndex]
        messages.removeSubrange((userIndex + 1)..<messages.count)
        pruneMarkdownCache()
        let context = Array(messages.prefix(userIndex))
        persistCurrentConversation()

        startStreamingResponse(
            userText: userMessage.content,
            imageAttachments: userMessage.imageAttachments,
            contextMessages: context,
            appendsUserMessage: false
        )
    }

    func scheduleTokenFlush(for messageID: UUID) {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        flushTask?.cancel()

        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flushPendingTokens(
                for: messageID,
                flushesReasoning: false,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }
    }

    func flushPendingTokens(
        for messageID: UUID,
        flushesReasoning: Bool = true,
        invalidatesMarkdownCache: Bool = true,
        requestsAutoScroll: Bool = true
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            streamingTokenBuffer.clearPendingTokens()
            isFlushScheduled = false
            flushTask = nil
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            if flushesReasoning, streamingTokenBuffer.hasPendingReasoningText {
                messages[index].reasoningChunks.append(
                    contentsOf: streamingTokenBuffer.consumePendingReasoningChunks()
                )
            }

            if streamingTokenBuffer.hasPendingContentText {
                messages[index].content += streamingTokenBuffer.consumePendingContentText()
                activeAssistantHasContent = true
                if invalidatesMarkdownCache {
                    invalidateMarkdownCache(for: messageID)
                }
            }
        }

        if requestsAutoScroll {
            scheduleStreamingAutoScroll()
        }

        isFlushScheduled = false
        flushTask = nil
    }

    func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }

    private func appendLiveContentToken(_ token: String) {
        publishLiveContentUpdate(chunks: [token], resetsText: false)
    }

    private func updateLiveReasoningDisplayIfNeeded(for messageID: UUID, token: String) {
        guard activeAssistantMessageID == messageID,
              activeAssistantReasoningIsExpanded else { return }

        publishLiveReasoningUpdate(
            chunks: [token],
            resetsText: false,
            appendsProgressively: token.utf16.count > Self.liveReasoningProgressiveAppendThreshold
        )
    }

    private func collapseReasoningAfterThinkingIfNeeded(for messageID: UUID) {
        guard activeAssistantMessageID == messageID,
              activeAssistantHasReasoning,
              !activeAssistantDidCollapseReasoningAfterThinking else { return }

        activeAssistantDidCollapseReasoningAfterThinking = true
        let wasReasoningExpanded = activeAssistantReasoningIsExpanded
        activeAssistantReasoningIsExpanded = false

        if let index = messages.firstIndex(where: { $0.id == messageID }),
           messages[index].isReasoningExpanded {
            messages[index].isReasoningExpanded = false
            clearLiveReasoningDisplay()
        } else if wasReasoningExpanded {
            clearLiveReasoningDisplay()
        }
    }

    private func handleReasoningExpansionChange(for messageID: UUID, isExpanded: Bool) {
        guard activeAssistantMessageID == messageID else { return }

        activeAssistantReasoningIsExpanded = isExpanded
        if isExpanded {
            publishLiveReasoningReset(for: messageID, appendsProgressively: true)
        } else {
            clearLiveReasoningDisplay()
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
        chunks.append(contentsOf: streamingTokenBuffer.reasoningChunksSnapshot)

        publishLiveReasoningUpdate(
            chunks: chunks,
            resetsText: true,
            appendsProgressively: appendsProgressively
        )
    }

    private func publishLiveReasoningUpdate(
        chunks: [String],
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        liveAssistantReasoningChannel.publish(
            chunks: chunks,
            resetsText: resetsText,
            appendsProgressively: appendsProgressively
        )
    }

    private func clearLiveReasoningDisplay() {
        publishLiveReasoningUpdate(chunks: [], resetsText: true)
    }

    private func publishLiveContentUpdate(chunks: [String], resetsText: Bool) {
        liveAssistantContentChannel.publish(chunks: chunks, resetsText: resetsText)
    }

    private func clearLiveContentDisplay() {
        publishLiveContentUpdate(chunks: [], resetsText: true)
    }

    private func clearLiveStreamingText() {
        clearLiveReasoningDisplay()
        clearLiveContentDisplay()
    }

    private func scheduleStreamingAutoScroll() {
        chatScrollController.scheduleStreamingAutoScroll()
    }

    private static let liveReasoningProgressiveAppendThreshold = 720

    private func prepareMarkdownCaches(for messages: [ChatMessage]) {
        messages
            .filter { $0.role == "assistant" && !$0.content.isEmpty }
            .forEach { prepareMarkdownCache(for: $0.id, content: $0.content) }
    }

    private func prepareMarkdownCache(for messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID && $0.role == "assistant" }),
              !message.content.isEmpty else {
            invalidateMarkdownCache(for: messageID)
            return
        }
        prepareMarkdownCache(for: messageID, content: message.content)
    }

    private func prepareMarkdownCache(for messageID: UUID, content: String) {
        let signature = MarkdownRenderCacheEntry.signature(for: content)
        guard markdownRenderCache[messageID]?.signature != signature else { return }

        markdownRenderTasks[messageID]?.cancel()
        markdownRenderTasks[messageID] = Task { @MainActor in
            let entry = await Task.detached(priority: .utility) {
                MarkdownRenderCacheEntry(content: content)
            }.value

            guard !Task.isCancelled else { return }
            markdownRenderCache[messageID] = entry
            markdownRenderTasks[messageID] = nil
        }
    }

    private func invalidateMarkdownCache(for messageID: UUID) {
        markdownRenderTasks[messageID]?.cancel()
        markdownRenderTasks[messageID] = nil
        markdownRenderCache[messageID] = nil
    }

    private func resetMarkdownCache(for messages: [ChatMessage]) {
        markdownRenderTasks.values.forEach { $0.cancel() }
        markdownRenderTasks = [:]
        markdownRenderCache = [:]
        prepareMarkdownCaches(for: messages)
    }

    private func pruneMarkdownCache() {
        let messageIDs = Set(messages.map(\.id))
        markdownRenderCache = markdownRenderCache.filter { messageIDs.contains($0.key) }
        for (messageID, task) in markdownRenderTasks where !messageIDs.contains(messageID) {
            task.cancel()
            markdownRenderTasks[messageID] = nil
        }
    }

    func stopGenerating() {
        let stoppedMessageID = activeAssistantMessageID

        aiService.cancelStreaming()
        cancelScheduledFlush()

        if let stoppedMessageID {
            flushPendingTokens(for: stoppedMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: true)

            if let index = messages.firstIndex(where: { $0.id == stoppedMessageID }) {
                messages[index].isStopped = true
                prepareMarkdownCache(for: stoppedMessageID)
            }
        }

        activeAssistantMessageID = nil
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isGenerating = false
        streamingTokenBuffer.reset()
        clearLiveStreamingText()
        isFlushScheduled = false
        persistCurrentConversation()
    }

    func hideKeyboard() {
        isInputFocused = false
        KeyboardDismissal.dismissNowAndDeferred()
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        guard currentConfiguration.selectedModelSupportsImages else {
            selectedPhotoItems = []
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        imageSelectionError = nil

        Task {
            var attachments = [ChatImageAttachment]()

            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let dataURL = compressedImageDataURL(from: data) else {
                    continue
                }

                attachments.append(ChatImageAttachment(dataURL: dataURL))
            }

            if attachments.isEmpty, !items.isEmpty {
                imageSelectionError = "图片读取失败，请重新选择。"
            } else {
                setPendingImageAttachments(attachments)
                imageSelectionError = nil
            }
        }
    }

    private func compressedImageDataURL(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return compressedImageDataURL(from: image)
    }

    private func compressedImageDataURL(from image: UIImage) -> String? {
        let scaledImage = image.scaledDown(maxDimension: 1600)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    private func setPendingImageAttachments(_ attachments: [ChatImageAttachment]) {
        pendingImageAttachments = Array(attachments.prefix(maxImageAttachmentCount))
        if attachments.count > maxImageAttachmentCount {
            imageSelectionError = "最多只能添加 \(maxImageAttachmentCount) 张图片，已保留前 \(maxImageAttachmentCount) 张。"
        }
    }

    private func appendPendingImageAttachments(_ attachments: [ChatImageAttachment], source: String) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        guard !attachments.isEmpty else {
            imageSelectionError = "\(source)图片读取失败。"
            return
        }

        let remainingCount = maxImageAttachmentCount - pendingImageAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = "最多只能添加 \(maxImageAttachmentCount) 张图片。"
            return
        }

        pendingImageAttachments.append(contentsOf: attachments.prefix(remainingCount))
        imageSelectionError = attachments.count > remainingCount
            ? "最多只能添加 \(maxImageAttachmentCount) 张图片，已保留前 \(maxImageAttachmentCount) 张。"
            : nil
    }

    private func handleDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入。"
            return false
        }

        let imageProviders = providers.filter { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }
        }

        guard !imageProviders.isEmpty else { return false }
        imageSelectionError = nil

        Task {
            var attachments = [ChatImageAttachment]()

            for provider in imageProviders.prefix(maxImageAttachmentCount) {
                guard let data = await imageData(from: provider),
                      let dataURL = compressedImageDataURL(from: data) else {
                    continue
                }

                attachments.append(ChatImageAttachment(dataURL: dataURL))
            }

            appendPendingImageAttachments(attachments, source: "拖拽")
        }

        return true
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func pasteImagesFromInputMenu(_ images: [UIImage]) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        guard !images.isEmpty else {
            imageSelectionError = "剪贴板中没有可粘贴的图片。"
            return
        }

        let attachments = images.compactMap { image -> ChatImageAttachment? in
            guard let dataURL = compressedImageDataURL(from: image) else { return nil }
            return ChatImageAttachment(dataURL: dataURL)
        }

        appendPendingImageAttachments(attachments, source: "剪贴板")
    }

    private func removePendingImage(_ id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
        if pendingImageAttachments.isEmpty {
            selectedPhotoItems = []
        }
    }

    private func chatScrollBottomDistance(bottomGeometry: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let bottomY = bottomGeometry.frame(in: .named(ChatScrollMetrics.coordinateSpaceName)).maxY
        return max(0, bottomY - viewportHeight)
    }

    func forceScrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func selectModel(_ model: String) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].selectedModel = model
        if !configurations[index].models.contains(where: { $0.name == model }) {
            configurations[index].models.append(AIModelConfiguration(name: model))
        }
        if !configurations[index].selectedModelSupportsImages {
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
        }
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func selectReasoningEffort(_ effort: ReasoningEffort) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].reasoningEnabled = true
        configurations[index].reasoningEffort = effort
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func setReasoningEnabled(_ isEnabled: Bool) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].reasoningEnabled = isEnabled
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func reloadConfigurations() {
        configurations = AIConfigurationStore.loadConfigurations()
        selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
        if selectedConfigurationID == nil,
           let firstConfiguration = configurations.first {
            selectedConfigurationID = firstConfiguration.id
            AIConfigurationStore.saveSelectedConfigurationID(firstConfiguration.id)
        }
    }

    private func loadSelectedConversation() {
        if let selectedConversationID,
           let conversation = conversations.first(where: { $0.id == selectedConversationID }) {
            restoreConversation(conversation, closesSidebar: false)
        } else if let firstConversation = conversations.first {
            restoreConversation(firstConversation, closesSidebar: false)
        } else {
            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            resetMarkdownCache(for: messages)
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            clearLiveStreamingText()
            aiService.resetConversation(with: [], systemPrompt: currentConfiguration.systemPrompt)
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
        }
    }

    private func ensureCurrentConversation() {
        if selectedConversationID == nil || !conversations.contains(where: { $0.id == selectedConversationID }) {
            let conversation = AIConversation()
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
        }
    }

    private func selectConversation(_ id: UUID) {
        selectConversation(id, closesSidebar: true)
    }

    private func selectConversation(_ id: UUID, closesSidebar: Bool) {
        if isGenerating {
            stopGenerating()
        } else {
            persistCurrentConversation()
        }

        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        restoreConversation(conversation, closesSidebar: closesSidebar)
    }

    private func restoreConversation(_ conversation: AIConversation, closesSidebar: Bool) {
        selectedConversationID = conversation.id
        messages = conversation.messages
        resetMarkdownCache(for: messages)
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        activeMessageActionID = nil
        editingMessageID = nil
        streamingTokenBuffer.reset()
        clearLiveStreamingText()
        isFlushScheduled = false
        chatScrollController.returnToBottom()
        aiService.resetConversation(with: messages, systemPrompt: currentConfiguration.systemPrompt)
        ConversationStore.saveSelectedConversationID(conversation.id)

        if closesSidebar {
            showConversationSidebar = false
        }
    }

    private func createConversation() {
        createConversation(closesSidebar: true)
    }

    private func createConversation(closesSidebar: Bool) {
        guard canCreateConversation else {
            if closesSidebar {
                showConversationSidebar = false
            }
            return
        }

        if isGenerating {
            stopGenerating()
        } else {
            persistCurrentConversation()
        }

        if currentConversationIsBlank {
            if closesSidebar {
                showConversationSidebar = false
            }
            return
        }

        if let emptyConversation = conversations.first(where: { conversation in
            conversation.id != selectedConversationID && !conversation.hasInformation
        }) {
            selectConversation(emptyConversation.id, closesSidebar: closesSidebar)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        messages = []
        resetMarkdownCache(for: messages)
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        activeMessageActionID = nil
        editingMessageID = nil
        streamingTokenBuffer.reset()
        clearLiveStreamingText()
        isFlushScheduled = false
        aiService.resetConversation(with: [], systemPrompt: currentConfiguration.systemPrompt)
        ConversationStore.saveSelectedConversationID(conversation.id)
        ConversationStore.saveConversations(conversations)

        if closesSidebar {
            showConversationSidebar = false
        }
    }

    private func deleteConversation(_ id: UUID) {
        if conversations.count <= 1 {
            if selectedConversationID == id && isGenerating {
                aiService.cancelStreaming()
                isGenerating = false
            }

            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            resetMarkdownCache(for: messages)
            inputText = ""
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeAssistantMessageID = nil
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            activeMessageActionID = nil
            editingMessageID = nil
            streamingTokenBuffer.reset()
            clearLiveStreamingText()
            isFlushScheduled = false
            showConversationSidebar = false
            aiService.resetConversation(with: [], systemPrompt: currentConfiguration.systemPrompt)
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
            return
        }

        if selectedConversationID == id && isGenerating {
            stopGenerating()
        }

        conversations.removeAll { $0.id == id }

        if selectedConversationID == id || selectedConversationID == nil {
            let nextConversation = conversations[0]
            selectedConversationID = nextConversation.id
            messages = nextConversation.messages
            resetMarkdownCache(for: messages)
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeAssistantMessageID = nil
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            activeMessageActionID = nil
            editingMessageID = nil
            streamingTokenBuffer.reset()
            clearLiveStreamingText()
            isFlushScheduled = false
            aiService.resetConversation(with: messages, systemPrompt: currentConfiguration.systemPrompt)
            ConversationStore.saveSelectedConversationID(nextConversation.id)
        }

        ConversationStore.saveConversations(conversations)
    }

    private func persistApplicationStateForLifecycle() {
        let shouldRefreshUpdatedAt = activeAssistantMessageID != nil

        if let activeAssistantMessageID {
            cancelScheduledFlush()
            flushPendingTokens(for: activeAssistantMessageID, invalidatesMarkdownCache: false, requestsAutoScroll: false)
        }

        persistCurrentConversation(synchronize: true, refreshesUpdatedAt: shouldRefreshUpdatedAt)
    }

    private func persistCurrentConversation(
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return
        }

        conversations[index].messages = messages
        if refreshesUpdatedAt {
            conversations[index].updatedAt = Date()
        }
        ConversationStore.saveConversations(conversations, synchronize: synchronize)
    }

    private func generateTitleIfNeeded() {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }),
              !conversations[index].hasGeneratedTitle,
              conversations[index].messages.contains(where: { $0.role == "assistant" && !$0.content.isEmpty }) else {
            return
        }

        let titleMessages = conversations[index].messages
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil

        guard !model.isEmpty else { return }

        aiService.generateConversationTitle(
            messages: titleMessages,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ) { title in
            if self.selectedConversationID == selectedConversationID {
                persistCurrentConversation()
            }

            guard let title,
                  let currentIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }),
                  !title.isEmpty else {
                return
            }

            conversations[currentIndex].title = title
            conversations[currentIndex].hasGeneratedTitle = true
            conversations[currentIndex].updatedAt = Date()
            ConversationStore.saveConversations(conversations)
        }
    }

}

struct MessageBubble: View {
    @Binding var message: ChatMessage
    let isStreaming: Bool
    let hasStreamingReasoning: Bool
    let hasStreamingContent: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let streamingReasoningChannel: StreamingTextUpdateChannel?
    let markdownRenderCache: MarkdownRenderCacheEntry?
    let showsActions: Bool
    let onSelect: () -> Void
    let onReasoningExpansionChanged: (Bool) -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool {
        message.role == "user"
    }

    private var userBubbleColor: Color {
        colorScheme == .dark ? Color.blue.opacity(0.72) : Color.accentColor
    }

    private var assistantBubbleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.gray.opacity(0.16)
    }

    private var assistantReasoningColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.10)
    }

    private var displayContent: String {
        message.content
    }

    private var displayReasoningContent: String {
        message.reasoningContent
    }

    private var displayReasoningChunks: [String] {
        message.reasoningChunks
    }

    private var hasReasoningContent: Bool {
        hasStreamingReasoning || !displayReasoningContent.isEmpty || !displayReasoningChunks.isEmpty
    }

    private var shouldShowMessageContentBubble: Bool {
        if isUser {
            return !displayContent.isEmpty
        }

        if !displayContent.isEmpty || hasStreamingContent || message.isStopped {
            return true
        }

        return !isStreaming && !hasReasoningContent
    }

    private var messageContentBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                SelectableTextView(
                    text: displayContent,
                    textColor: .white,
                    font: .preferredFont(forTextStyle: .body),
                    textAlignment: .left,
                    sizing: .natural,
                    onTap: onSelect
                )
            } else if displayContent.isEmpty, !hasStreamingContent {
                Text(message.isStopped ? "已停止生成。" : "正在生成回答...")
            } else {
                AssistantMessageContent(
                    content: displayContent,
                    isStreaming: isStreaming,
                    streamingContentChannel: streamingContentChannel,
                    isStopped: message.isStopped,
                    markdownRenderCache: markdownRenderCache
                )
            }
        }
        .font(.body)
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? userBubbleColor : assistantBubbleColor)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 48)
                userMessageStack
            } else {
                assistantMessageStack
                Spacer(minLength: 48)
            }
        }
    }

    private var userMessageStack: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.imageAttachments.isEmpty {
                messageImages
            }

            if !message.content.isEmpty {
                messageContentBubble
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
            }

            if showsActions {
                Button {
                    onEdit()
                } label: {
                    Label("修改", systemImage: "pencil")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private var assistantMessageStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasReasoningContent {
                reasoningBlock
            }

            if shouldShowMessageContentBubble {
                messageContentBubble
            }

            if showsActions, !displayContent.isEmpty {
                Button {
                    onRegenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private var messageImages: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88, maximum: 140), spacing: 8)],
            alignment: .trailing,
            spacing: 8
        ) {
            ForEach(message.imageAttachments) { attachment in
                DataURLImage(dataURL: attachment.dataURL)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
            }
        }
        .frame(width: imageGridWidth, alignment: .trailing)
        .onTapGesture {
            onSelect()
        }
    }

    private var imageGridWidth: CGFloat {
        let count = min(message.imageAttachments.count, 2)
        guard count > 0 else { return 0 }
        return CGFloat(count) * 112 + CGFloat(count - 1) * 8
    }

    private var reasoningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                message.isReasoningExpanded.toggle()
                onReasoningExpansionChanged(message.isReasoningExpanded)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: message.isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)

                    Text("思考过程")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if message.isReasoningExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ReasoningMessageContent(
                        content: displayReasoningContent,
                        chunks: displayReasoningChunks,
                        isStreaming: isStreaming,
                        streamingChannel: streamingReasoningChannel
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(assistantReasoningColor)
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
                .clipped()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .clipped()
    }
}

struct AssistantMessageContent: View {
    let content: String
    let isStreaming: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let isStopped: Bool
    let markdownRenderCache: MarkdownRenderCacheEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let streamingContentChannel {
                StreamingAssistantMarkdownText(streamingChannel: streamingContentChannel)
            } else if isStreaming {
                StreamingAssistantMarkdownText(content)
            } else if let markdownRenderCache {
                AssistantMarkdownText(renderCache: markdownRenderCache)
            } else {
                PlainAssistantText(content)
            }

            if isStopped {
                Text("已停止生成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReasoningMessageContent: View {
    let content: String
    let chunks: [String]
    let isStreaming: Bool
    let streamingChannel: StreamingTextUpdateChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let streamingChannel {
                ScrollableSelectableTextView(
                    text: "",
                    streamingChannel: streamingChannel,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: true
                )
            } else if !chunks.isEmpty {
                ScrollableSelectableTextView(
                    text: "",
                    chunks: chunks,
                    appendsChunksProgressively: true,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: false
                )
            } else if usesScrollableTextView {
                ScrollableSelectableTextView(
                    text: content,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: isStreaming
                )
            } else {
                ReasoningPlainText(content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesScrollableTextView: Bool {
        isStreaming || !chunks.isEmpty || content.utf16.count > Self.inlineCharacterLimit
    }

    private static let inlineCharacterLimit = 1_800
}

private struct ReasoningPlainText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .secondaryLabel,
            font: .preferredFont(forTextStyle: .caption1),
            textAlignment: .left
        )
    }
}

struct StreamingAssistantMarkdownText: View {
    let content: String
    let streamingChannel: StreamingTextUpdateChannel?
    @State private var renderedContent: String
    @State private var pendingAppendChunks: [String] = []
    @State private var renderedSegments: [ChatMarkdownBlockSegment]
    @State private var renderTask: Task<Void, Never>?
    @State private var streamingObserverID: UUID?

    init(_ content: String) {
        self.content = content
        streamingChannel = nil
        _renderedContent = State(initialValue: content)
        _renderedSegments = State(initialValue: Self.renderSegments(for: content))
    }

    init(streamingChannel: StreamingTextUpdateChannel) {
        content = ""
        self.streamingChannel = streamingChannel
        _renderedContent = State(initialValue: "")
        _renderedSegments = State(initialValue: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(renderedSegments) { segment in
                switch segment.kind {
                case let .text(text):
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
                        StreamingMarkdownText(trimmedText)
                            .equatable()
                    }
                case let .code(language, code):
                    StreamingCodeBlock(content: code, language: language)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            attachStreamingChannelIfNeeded()
        }
        .onChange(of: content) { _, newContent in
            guard streamingChannel == nil else { return }
            renderedContent = newContent
            scheduleRender()
        }
        .onDisappear {
            cancelRenderTask()
            detachStreamingChannel()
        }
    }

    private func scheduleRender() {
        guard renderTask == nil else { return }

        renderTask = Task { @MainActor in
            try? await Task.sleep(for: Self.renderInterval)
            guard !Task.isCancelled else { return }
            applyPendingChunks()
            renderedSegments = Self.renderSegments(for: renderedContent)
            renderTask = nil
        }
    }

    private func renderImmediately() {
        cancelRenderTask()
        applyPendingChunks()
        renderedSegments = Self.renderSegments(for: renderedContent)
    }

    private func applyPendingChunks() {
        guard !pendingAppendChunks.isEmpty else { return }
        renderedContent += pendingAppendChunks.joined()
        pendingAppendChunks.removeAll(keepingCapacity: true)
    }

    private func applyStreamingUpdate(_ update: StreamingTextUpdate) {
        if update.resetsText {
            cancelRenderTask()
            pendingAppendChunks.removeAll(keepingCapacity: true)
            renderedContent = update.chunks.joined()
            renderedSegments = Self.renderSegments(for: renderedContent)
            return
        }

        guard !update.chunks.isEmpty else { return }
        pendingAppendChunks.append(contentsOf: update.chunks)
        if renderedContent.isEmpty {
            renderImmediately()
        } else {
            scheduleRender()
        }
    }

    private func attachStreamingChannelIfNeeded() {
        guard let streamingChannel, streamingObserverID == nil else { return }

        applyStreamingUpdate(streamingChannel.latest)
        streamingObserverID = streamingChannel.addObserver { update in
            applyStreamingUpdate(update)
        }
    }

    private func detachStreamingChannel() {
        if let streamingObserverID {
            streamingChannel?.removeObserver(streamingObserverID)
        }
        streamingObserverID = nil
    }

    private func cancelRenderTask() {
        renderTask?.cancel()
        renderTask = nil
    }

    private static func renderSegments(for content: String) -> [ChatMarkdownBlockSegment] {
        ChatMarkdownBlockSegment.split(content)
    }

    private static let renderInterval: Duration = .milliseconds(50)
}

private struct StreamingMarkdownText: View, Equatable {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    static func == (lhs: StreamingMarkdownText, rhs: StreamingMarkdownText) -> Bool {
        lhs.markdown == rhs.markdown
    }

    var body: some View {
        Text(Self.attributedString(from: markdown))
            .font(.body)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func attributedString(from markdown: String) -> AttributedString {
        let fullOptions = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: fullOptions) {
            return attributed
        }

        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: inlineOptions)) ?? AttributedString(markdown)
    }
}

private struct StreamingCodeBlock: View {
    let content: String
    let language: String?
    @Environment(\.colorScheme) private var colorScheme

    private var languageName: String {
        let value = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "text"
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(languageName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(content.isEmpty ? " " : content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct PlainAssistantText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .label,
            font: .preferredFont(forTextStyle: .body),
            textAlignment: .left
        )
    }
}

nonisolated struct MarkdownRenderCacheEntry: @unchecked Sendable {
    let signature: String
    let renderedMarkdown: String
    let segments: [ChatMarkdownBlockSegment]

    nonisolated init(content: String) {
        signature = Self.signature(for: content)
        renderedMarkdown = ChatMarkdownPreprocessor.preprocess(content)
        segments = ChatMarkdownBlockSegment.split(renderedMarkdown)
    }

    nonisolated static func signature(for content: String) -> String {
        "\(content.count):\(content.hashValue)"
    }
}

struct AssistantMarkdownText: View {
    let renderCache: MarkdownRenderCacheEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(renderCache.segments) { segment in
                switch segment.kind {
                case let .text(text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SelectableMarkdownTextView(
                            markdown: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            textColor: .label,
                            baseFont: .preferredFont(forTextStyle: .body),
                            textAlignment: .left
                        )
                    }
                case let .code(language, code):
                    ChatCodeBlock(content: code, language: language)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatMarkdownBlockSegment: Identifiable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text(String)
        case code(language: String?, code: String)
    }

    nonisolated static func split(_ content: String) -> [ChatMarkdownBlockSegment] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [ChatMarkdownBlockSegment] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendText() {
            guard !textBuffer.isEmpty else { return }
            segments.append(
                ChatMarkdownBlockSegment(
                    id: segments.count,
                    kind: .text(textBuffer.joined(separator: "\n"))
                )
            )
            textBuffer.removeAll()
        }

        func appendCode() {
            segments.append(
                ChatMarkdownBlockSegment(
                    id: segments.count,
                    kind: .code(language: codeLanguage, code: codeBuffer.joined(separator: "\n"))
                )
            )
            codeBuffer.removeAll()
            codeLanguage = nil
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                if codeFence.isClosing(line) {
                    appendCode()
                    activeCodeFence = nil
                } else {
                    codeBuffer.append(line)
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendText()
                activeCodeFence = codeFence
                codeLanguage = codeFence.language
            } else {
                textBuffer.append(line)
            }
        }

        if activeCodeFence != nil {
            appendCode()
        } else {
            appendText()
        }

        return segments
    }
}

private struct ChatMarkdownCodeFence {
    let marker: Character
    let length: Int
    let language: String?

    nonisolated static func opening(in line: String) -> ChatMarkdownCodeFence? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first, marker == "`" || marker == "~" else { return nil }

        let length = trimmedLine.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }

        let language = trimmedLine
            .dropFirst(length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)

        return ChatMarkdownCodeFence(marker: marker, length: length, language: language)
    }

    nonisolated func isClosing(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let closingLength = trimmedLine.prefix { $0 == marker }.count
        guard closingLength >= length else { return false }
        return trimmedLine.dropFirst(closingLength).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum ChatMarkdownPreprocessor {
    nonisolated static func preprocess(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = splitByCodeFence(normalized)
        return segments
            .map { segment in
                segment.isCode ? segment.text : preprocessMarkdownText(segment.text)
            }
            .joined()
    }

    private nonisolated static func preprocessMarkdownText(_ text: String) -> String {
        var processed = text
        processed = removeHTMLComments(from: processed)
        processed = removeTOCLines(from: processed)
        processed = transformCustomContainers(in: processed)
        processed = transformBlockMath(in: processed)
        processed = normalizeTables(in: processed)
        processed = transformInlineExtensions(in: processed)
        processed = stripAttributeLists(from: processed)
        processed = appendFootnotes(in: processed)
        return processed
    }

    private nonisolated static func splitByCodeFence(_ content: String) -> [(text: String, isCode: Bool)] {
        let lines = content.components(separatedBy: "\n")
        var segments: [(text: String, isCode: Bool)] = []
        var buffer: [String] = []
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendBuffer(isCode: Bool, appendsTrailingNewline: Bool) {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: "\n") + (appendsTrailingNewline ? "\n" : "")
            segments.append((text, isCode))
            buffer = []
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                buffer.append(line)
                if codeFence.isClosing(line) {
                    appendBuffer(isCode: true, appendsTrailingNewline: true)
                    activeCodeFence = nil
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendBuffer(isCode: false, appendsTrailingNewline: true)
                activeCodeFence = codeFence
                buffer.append(line)
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            segments.append((buffer.joined(separator: "\n"), activeCodeFence != nil))
        }
        return segments
    }

    private nonisolated static func removeHTMLComments(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func removeTOCLines(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?mi)^\s*\[(?:toc|TOC)\]\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func transformCustomContainers(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var containerTitle: String?
        var containerLines: [String] = []

        func flushContainer() {
            guard let containerTitle else { return }
            result.append("> **\(containerTitle)**")
            result.append(contentsOf: containerLines.map { $0.isEmpty ? ">" : "> \($0)" })
            containerLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":::") {
                if containerTitle == nil {
                    let rawTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    containerTitle = rawTitle.isEmpty ? "提示" : rawTitle
                    containerLines = []
                } else {
                    flushContainer()
                    containerTitle = nil
                }
                continue
            }

            if containerTitle != nil {
                containerLines.append(line)
            } else {
                result.append(line)
            }
        }

        flushContainer()
        return result.joined(separator: "\n")
    }

    private nonisolated static func transformBlockMath(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)\$\$\s*(.*?)\s*\$\$"#,
            with: "\n```math\n$1\n```\n",
            options: .regularExpression
        )
    }

    private nonisolated static func normalizeTables(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if isTableHeader(lines: lines, at: index) {
                if let previous = result.last, !previous.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }

                var tableLines: [String] = []
                let columnCount = tableCellCount(in: lines[index])
                while index < lines.count, looksLikeTableLine(lines[index]) {
                    tableLines.append(normalizedTableLine(lines[index], columnCount: columnCount))
                    index += 1
                }
                result.append(contentsOf: tableLines)

                if index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }
                continue
            }

            result.append(lines[index])
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private nonisolated static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count,
              looksLikeTableLine(lines[index]) else {
            return false
        }
        return isTableSeparatorLine(lines[index + 1])
    }

    private nonisolated static func looksLikeTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") || trimmed.contains("｜")
    }

    private nonisolated static func normalizedTableLine(_ line: String) -> String {
        normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func normalizedTableLine(_ line: String, columnCount: Int) -> String {
        let cells = normalizedTableCells(in: line)
        guard !cells.isEmpty else { return normalizedTableLine(line) }

        let normalizedCells: [String]
        if isTableSeparatorLine(line) {
            normalizedCells = normalizedSeparatorCells(from: cells, columnCount: columnCount)
        } else {
            normalizedCells = normalizedDataCells(from: cells, columnCount: columnCount)
        }

        return "| " + normalizedCells.joined(separator: " | ") + " |"
    }

    private nonisolated static func normalizedTableText(_ line: String) -> String {
        line
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    private nonisolated static func normalizedTableCells(in line: String) -> [String] {
        let normalized = normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))

        return normalized
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private nonisolated static func tableCellCount(in line: String) -> Int {
        max(normalizedTableCells(in: line).count, 1)
    }

    private nonisolated static func normalizedDataCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount))
        while normalizedCells.count < columnCount {
            normalizedCells.append("")
        }
        return normalizedCells
    }

    private nonisolated static func normalizedSeparatorCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount)).map { cell in
            let compact = cell.filter { !$0.isWhitespace }
            let leftAligned = compact.hasPrefix(":")
            let rightAligned = compact.hasSuffix(":")
            let marker = String(repeating: "-", count: max(3, compact.filter { $0 == "-" }.count))

            switch (leftAligned, rightAligned) {
            case (true, true):
                return ":" + marker + ":"
            case (true, false):
                return ":" + marker
            case (false, true):
                return marker + ":"
            case (false, false):
                return marker
            }
        }

        while normalizedCells.count < columnCount {
            normalizedCells.append("---")
        }
        return normalizedCells
    }

    private nonisolated static func isTableSeparatorLine(_ line: String) -> Bool {
        let cells = normalizedTableCells(in: line)

        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.filter { !$0.isWhitespace }
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private nonisolated static func transformInlineExtensions(in text: String) -> String {
        var processed = text
        processed = processed.replacingOccurrences(
            of: #"==([^=\n]+)=="#,
            with: "**$1**",
            options: .regularExpression
        )
        processed = processed.replacingOccurrences(
            of: #"<u>(.*?)</u>"#,
            with: "_$1_",
            options: [.regularExpression, .caseInsensitive]
        )
        processed = processed.replacingOccurrences(
            of: #"(?<!\\)\$([^\n$]+?)\$"#,
            with: "`$1`",
            options: .regularExpression
        )
        return processed
    }

    private nonisolated static func stripAttributeLists(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+\{[#.][^}\n]*\}"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func appendFootnotes(in text: String) -> String {
        var footnotes: [(id: String, body: String)] = []
        var bodyLines: [String] = []
        let pattern = #"^\[\^([^\]]+)\]:\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        for line in text.components(separatedBy: "\n") {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
                  match.numberOfRanges == 3,
                  let idRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line) else {
                bodyLines.append(line)
                continue
            }

            footnotes.append((String(line[idRange]), String(line[bodyRange])))
        }

        guard !footnotes.isEmpty else { return text }
        let renderedFootnotes = footnotes.map { "[^\($0.id)]: \($0.body)" }.joined(separator: "\n")
        return bodyLines.joined(separator: "\n") + "\n\n---\n\n" + renderedFootnotes
    }
}

struct ImagePastingTextView: UIViewRepresentable {
    @Binding var text: String

    @Binding var isFocused: Bool
    let focusRequestID: Int
    let placeholder: String
    let onPasteImages: ([UIImage]) -> Void

    func makeUIView(context: Context) -> ImagePastingUITextView {
        let textView = ImagePastingUITextView()
        textView.delegate = context.coordinator
        textView.onPasteImages = onPasteImages
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: ImagePastingUITextView, context: Context) {
        if (textView.text ?? "") != text {
            textView.text = text
        }

        textView.onPasteImages = onPasteImages
        textView.isEditable = true
        textView.isSelectable = true
        textView.placeholderText = placeholder
        textView.accessibilityLabel = placeholder
        textView.updatePlaceholderVisibility()

        context.coordinator.updateFocus(
            for: textView,
            shouldBeFocused: isFocused,
            requestID: focusRequestID
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        let fittingWidth = width > 0 ? width : UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        )
        let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let maxHeight = lineHeight * 5
        let height = min(max(fittingSize.height, lineHeight), maxHeight)
        let shouldScroll = fittingSize.height > maxHeight
        if uiView.isScrollEnabled != shouldScroll {
            uiView.isScrollEnabled = shouldScroll
        }
        return CGSize(width: fittingWidth, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let isFocused: Binding<Bool>
        private var lastHandledFocusRequestID: Int?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            if text.wrappedValue != updatedText {
                text.wrappedValue = updatedText
            }
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
        }

        func updateFocus(
            for textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            requestID: Int
        ) {
            let isNewRequest = lastHandledFocusRequestID != requestID
            guard isNewRequest || shouldBeFocused != textView.isFirstResponder else { return }
            lastHandledFocusRequestID = requestID

            if shouldBeFocused, textView.window != nil {
                if !textView.becomeFirstResponder() {
                    retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
                }
                return
            }

            retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
        }

        private func retryFocus(
            to textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            attemptsRemaining: Int
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.isFocused.wrappedValue == shouldBeFocused,
                      shouldBeFocused != textView.isFirstResponder else {
                    return
                }

                if shouldBeFocused {
                    guard textView.window != nil else {
                        if attemptsRemaining > 0 {
                            self.retryFocus(
                                to: textView,
                                shouldBeFocused: shouldBeFocused,
                                attemptsRemaining: attemptsRemaining - 1
                            )
                        }
                        return
                    }

                    if !textView.becomeFirstResponder(), attemptsRemaining > 0 {
                        self.retryFocus(
                            to: textView,
                            shouldBeFocused: shouldBeFocused,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                } else {
                    textView.resignFirstResponder()
                }
            }
        }
    }
}

final class ImagePastingUITextView: UITextView {
    var onPasteImages: (([UIImage]) -> Void)?
    private let placeholderLabel = UILabel()

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func setupPlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = font ?? .preferredFont(forTextStyle: .body)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)),
           UIPasteboard.general.hasImages {
            return true
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        guard let images = UIPasteboard.general.images, !images.isEmpty else {
            super.paste(sender)
            return
        }

        onPasteImages?(images)
    }
}

struct DataURLImage: View {
    let dataURL: String

    var body: some View {
        if let image = UIImage(dataURL: dataURL) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

extension UIImage {
    convenience init?(dataURL: String) {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = dataURL[dataURL.index(after: commaIndex)...]
        guard let data = Data(base64Encoded: String(base64)) else { return nil }
        self.init(data: data)
    }

    func scaledDown(maxDimension: CGFloat) -> UIImage {
        let largestDimension = max(size.width, size.height)
        guard largestDimension > maxDimension else { return self }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

#Preview {
    ContentView()
}
