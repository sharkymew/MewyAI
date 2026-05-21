import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var conversations = ConversationStore.loadConversations()
    @State private var selectedConversationID: UUID? = ConversationStore.loadSelectedConversationID()
    @State private var isGenerating = false
    @State private var showConfiguration = false
    @State private var showConversationSidebar = false
    @State private var shouldAutoScroll = true
    @State private var scrollVersion = 0
    @State private var pendingReasoningText = ""
    @State private var pendingContentText = ""
    @State private var isFlushScheduled = false
    @State private var flushTask: Task<Void, Never>?
    @State private var activeAssistantMessageID: UUID?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImageAttachments: [ChatImageAttachment] = []
    @State private var imageSelectionError: String?
    @State private var activeMessageActionID: UUID?
    @State private var editingMessageID: UUID?
    @FocusState private var isInputFocused: Bool
    
    let aiService = AIService()
    
    private var inputFieldBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.82)
    }
    
    private var inputControlBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }
    
    private var sendControlBackground: Color {
        !canSendMessage && !isGenerating
            ? inputControlBackground
            : Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.16)
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
            loadSelectedConversation()
        }
        .sheet(isPresented: $showConfiguration) {
            AIConfigurationView()
        }
        .onChange(of: showConfiguration) { _, isPresented in
            if !isPresented {
                reloadConfigurations()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadSelectedImages(from: newItems)
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            configurationBar
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($messages) { $message in
                            MessageBubble(
                                message: $message,
                                showsActions: activeMessageActionID == message.id,
                                onSelect: {
                                    DispatchQueue.main.async {
                                        withAnimation(.easeOut(duration: 0.16)) {
                                            activeMessageActionID = message.id
                                        }
                                    }
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
                    }
                    .padding()
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        shouldAutoScroll = false
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        hideKeyboard()
                        withAnimation(.easeOut(duration: 0.16)) {
                            activeMessageActionID = nil
                        }
                    }
                )
                .onChange(of: messages.count) { _, _ in
                    forceScrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: scrollVersion) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            
            inputBar
        }
        .overlay(alignment: .bottom) {
            if !shouldAutoScroll {
                Button {
                    shouldAutoScroll = true
                    scrollVersion += 1
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.regularMaterial))
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 92)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: shouldAutoScroll)
    }
    
    private var inputBar: some View {
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
                HStack(spacing: 10) {
                    Text("正在修改消息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("取消") {
                        cancelEditingMessage()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
            }
            
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "输入消息...",
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .disabled(isGenerating)
                .font(.body)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(inputFieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(inputControlBackground))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating || !currentConfiguration.selectedModelSupportsImages)
                .opacity(currentConfiguration.selectedModelSupportsImages ? 1 : 0.35)
                
                if currentConfiguration.selectedModelSupportsReasoning {
                    reasoningEffortMenu
                }
                
                if isEditingMessage {
                    Menu {
                        Button("仅修改") {
                            saveEditingMessageOnly()
                        }
                        
                        Button("修改并发送") {
                            saveEditingMessageAndRegenerate()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(sendControlBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendMessage)
                } else {
                    Button {
                        if isGenerating {
                            stopGenerating()
                        } else {
                            sendMessage()
                        }
                    } label: {
                        Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(sendControlBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isGenerating && !canSendMessage)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
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
                showConfiguration = true
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "cube.transparent")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(inputControlBackground))
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
    
    private var reasoningEffortMenu: some View {
        Menu {
            Button {
                setReasoningEnabled(!currentConfiguration.reasoningEnabled)
            } label: {
                Label(
                    currentConfiguration.reasoningEnabled ? "关闭思考" : "开启思考",
                    systemImage: currentConfiguration.reasoningEnabled ? "brain.head.profile" : "brain"
                )
            }
            
            Divider()
            
            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    selectReasoningEffort(effort)
                } label: {
                    if effort == currentConfiguration.reasoningEffort {
                        Label(effort.title, systemImage: "checkmark")
                    } else {
                        Text(effort.title)
                    }
                }
            }
        } label: {
            Image(systemName: currentConfiguration.reasoningEnabled ? "brain.head.profile" : "brain")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(inputControlBackground))
        }
        .disabled(isGenerating)
    }
    
    private var configurationBar: some View {
        HStack(spacing: 12) {
            Button {
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
                createConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating || !canCreateConversation)
            
            Button {
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
        guard !isGenerating else { return false }
        return !messages.isEmpty
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
        
        aiService.resetConversation(with: contextMessages)
        clearInputState()
        isGenerating = true
        shouldAutoScroll = true
        scrollVersion += 1
        pendingReasoningText = ""
        pendingContentText = ""
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
            onReasoningToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }
                
                pendingReasoningText += token
                scheduleTokenFlush(for: assistantMessageID)
            },
            onContentToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }
                
                pendingContentText += token
                scheduleTokenFlush(for: assistantMessageID)
            },
            onComplete: { _, _ in
                guard activeAssistantMessageID == assistantMessageID else { return }
                
                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID)
                isGenerating = false
                activeAssistantMessageID = nil
                persistCurrentConversation()
                generateTitleIfNeeded()
            },
            onError: { error in
                guard activeAssistantMessageID == assistantMessageID else { return }
                
                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID)
                
                if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                    messages[index].content = error
                }
                
                isGenerating = false
                activeAssistantMessageID = nil
                persistCurrentConversation()
            }
        )
    }
    
    private func appendAssistantError(_ content: String) {
        messages.append(ChatMessage(role: "assistant", content: content))
        persistCurrentConversation()
    }
    
    private func clearInputState() {
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        editingMessageID = nil
        isInputFocused = false
    }
    
    private func startEditingUserMessage(_ id: UUID) {
        guard !isGenerating,
              editingMessageID != id,
              let message = messages.first(where: { $0.id == id && $0.role == "user" }) else {
            return
        }
        
        editingMessageID = id
        inputText = message.content
        pendingImageAttachments = message.imageAttachments
        selectedPhotoItems = []
        imageSelectionError = nil
        activeMessageActionID = nil
        isInputFocused = true
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
        guard !isGenerating,
              let assistantIndex = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }),
              let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == "user" }) else {
            return
        }
        
        activeMessageActionID = nil
        let userMessage = messages[userIndex]
        messages.removeSubrange((userIndex + 1)..<messages.count)
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
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            flushPendingTokens(for: messageID)
        }
    }
    
    func flushPendingTokens(for messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            pendingReasoningText = ""
            pendingContentText = ""
            isFlushScheduled = false
            flushTask = nil
            return
        }
        
        var transaction = Transaction()
        transaction.animation = nil
        
        withTransaction(transaction) {
            if !pendingReasoningText.isEmpty {
                messages[index].reasoningContent += pendingReasoningText
                pendingReasoningText = ""
            }
            
            if !pendingContentText.isEmpty {
                messages[index].content += pendingContentText
                messages[index].isReasoningExpanded = false
                pendingContentText = ""
            }
        }
        
        if shouldAutoScroll {
            scrollVersion += 1
        }
        
        isFlushScheduled = false
        flushTask = nil
        persistCurrentConversation()
    }
    
    func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }
    
    func stopGenerating() {
        let stoppedMessageID = activeAssistantMessageID
        
        aiService.cancelStreaming()
        cancelScheduledFlush()
        
        if let stoppedMessageID {
            flushPendingTokens(for: stoppedMessageID)
            
            if let index = messages.firstIndex(where: { $0.id == stoppedMessageID }) {
                messages[index].isStopped = true
            }
        }
        
        activeAssistantMessageID = nil
        isGenerating = false
        pendingReasoningText = ""
        pendingContentText = ""
        isFlushScheduled = false
        persistCurrentConversation()
    }
    
    func hideKeyboard() {
        isInputFocused = false
    }
    
    private func loadSelectedImages(from items: [PhotosPickerItem]) {
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
                pendingImageAttachments = attachments
                imageSelectionError = nil
            }
        }
    }
    
    private func compressedImageDataURL(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scaledImage = image.scaledDown(maxDimension: 1600)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }
    
    private func removePendingImage(_ id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
        if pendingImageAttachments.isEmpty {
            selectedPhotoItems = []
        }
    }

    func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard shouldAutoScroll else { return }
        forceScrollToBottom(proxy: proxy, animated: animated)
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
           conversations.contains(where: { $0.id == selectedConversationID }) {
            selectConversation(selectedConversationID, closesSidebar: false)
        } else if let firstConversation = conversations.first {
            selectConversation(firstConversation.id, closesSidebar: false)
        } else {
            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            aiService.resetConversation(with: [])
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
        selectedConversationID = conversation.id
        messages = conversation.messages
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        activeMessageActionID = nil
        editingMessageID = nil
        pendingReasoningText = ""
        pendingContentText = ""
        isFlushScheduled = false
        shouldAutoScroll = true
        scrollVersion += 1
        aiService.resetConversation(with: messages)
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
        
        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        messages = []
        inputText = ""
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        activeMessageActionID = nil
        editingMessageID = nil
        aiService.resetConversation(with: [])
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
            inputText = ""
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeAssistantMessageID = nil
            activeMessageActionID = nil
            editingMessageID = nil
            pendingReasoningText = ""
            pendingContentText = ""
            isFlushScheduled = false
            showConversationSidebar = false
            aiService.resetConversation(with: [])
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
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeMessageActionID = nil
            editingMessageID = nil
            aiService.resetConversation(with: messages)
            ConversationStore.saveSelectedConversationID(nextConversation.id)
        }
        
        ConversationStore.saveConversations(conversations)
    }
    
    private func persistCurrentConversation() {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return
        }
        
        conversations[index].messages = messages
        conversations[index].updatedAt = Date()
        ConversationStore.saveConversations(conversations)
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
    let showsActions: Bool
    let onSelect: () -> Void
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
    
    private var messageContentBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.content.isEmpty, !isUser {
                Text(message.isStopped ? "已停止生成。" : "正在生成回答...")
            } else if !message.content.isEmpty {
                if isUser {
                    InlineMarkdownText(message.content)
                } else {
                    AssistantMarkdownText(message.isStopped ? message.content + "\n\n已停止生成。" : message.content)
                }
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
        .textSelection(.enabled)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onTapGesture {
            onSelect()
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
            if !message.reasoningContent.isEmpty {
                reasoningBlock
            }
            
            messageContentBubble
            
            if showsActions, !message.content.isEmpty {
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
                    Text(message.reasoningContent)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(assistantReasoningColor)
                )
                .textSelection(.enabled)
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

struct AssistantMarkdownText: View {
    let content: String
    
    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(content)
    }
    
    init(_ content: String) {
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if case .table(let headers, let rows) = block {
                    MarkdownTableView(headers: headers, rows: rows)
                        .padding(.horizontal, -14)
                } else {
                    MarkdownBlockView(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownText: View {
    let content: String
    
    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(content)
    }
    
    init(_ content: String) {
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case code(language: String, code: String)
    case table(headers: [String], rows: [[String]])
    case divider
}

enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks = [MarkdownBlock]()
        var index = 0
        
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                index += 1
                continue
            }
            
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines = [String]()
                
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                
                blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }
            
            if let heading = headingBlock(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }
            
            if isDivider(trimmed) {
                blocks.append(.divider)
                index += 1
                continue
            }
            
            if isTableStart(lines: lines, at: index) {
                let parsed = tableBlock(lines: lines, startIndex: index)
                blocks.append(parsed.block)
                index = parsed.nextIndex
                continue
            }
            
            if trimmed.hasPrefix(">") {
                var quoteLines = [String]()
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }
            
            if unorderedListMarker(trimmed) != nil {
                var items = [String]()
                while index < lines.count {
                    let itemLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = unorderedListMarker(itemLine) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }
            
            if let orderedItem = orderedListItem(trimmed) {
                var items = [orderedItem]
                index += 1
                while index < lines.count {
                    let itemLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = orderedListItem(itemLine) else { break }
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }
            
            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                guard !nextTrimmed.isEmpty,
                      !nextTrimmed.hasPrefix("```"),
                      !nextTrimmed.hasPrefix("~~~"),
                      headingBlock(from: nextTrimmed) == nil,
                      !isDivider(nextTrimmed),
                      !isTableStart(lines: lines, at: index),
                      !nextTrimmed.hasPrefix(">"),
                      unorderedListMarker(nextTrimmed) == nil,
                      orderedListItem(nextTrimmed) == nil else {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }
        
        return blocks
    }
    
    private static func headingBlock(from line: String) -> MarkdownBlock? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              line.dropFirst(markerCount).first == " " else {
            return nil
        }
        return .heading(
            level: markerCount,
            text: String(line.dropFirst(markerCount)).trimmingCharacters(in: .whitespaces)
        )
    }
    
    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }
    
    private static func unorderedListMarker(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    private static func orderedListItem(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dotIndex]
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber),
              line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)] == " " else {
            return nil
        }
        return String(line[line.index(dotIndex, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)
    }
    
    private static func isTableStart(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count,
              lines[index].contains("|") else {
            return false
        }
        return isTableSeparator(lines[index + 1])
    }
    
    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(from: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.filter { !$0.isWhitespace }
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
    
    private static func tableBlock(lines: [String], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int) {
        let headers = tableCells(from: lines[startIndex])
        var rows = [[String]]()
        var index = startIndex + 2
        
        while index < lines.count, lines[index].contains("|") {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { break }
            rows.append(tableCells(from: lines[index]))
            index += 1
        }
        
        return (.table(headers: headers, rows: rows), index)
    }
    
    private static func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    
    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(text)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            InlineMarkdownText(text)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        InlineMarkdownText(item)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                        InlineMarkdownText(item)
                    }
                }
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                InlineMarkdownText(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
        case .divider:
            Divider()
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2
        case 2:
            return .title3
        case 3:
            return .headline
        default:
            return .subheadline
        }
    }
}

struct InlineMarkdownText: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var didCopy = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var codeBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.055)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = code
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(codeBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var highlightedCode: AttributedString {
        CodeHighlighter.highlight(code, language: language, colorScheme: colorScheme)
    }
}

enum CodeHighlighter {
    static func highlight(_ code: String, language: String, colorScheme: ColorScheme) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = colorScheme == .dark ? .white.opacity(0.88) : .primary
        
        apply(pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: .green, to: &attributed, source: code)
        apply(pattern: #"(?m)//.*$|#.*$"#, color: .secondary, to: &attributed, source: code)
        apply(pattern: #"\b(\d+)(\.\d+)?\b"#, color: .orange, to: &attributed, source: code)
        
        let keywords = keywordPattern(for: language)
        apply(pattern: keywords, color: .blue, to: &attributed, source: code)
        
        return attributed
    }
    
    private static func keywordPattern(for language: String) -> String {
        let lowercasedLanguage = language.lowercased()
        if lowercasedLanguage.contains("swift") {
            return #"\b(import|struct|class|enum|protocol|extension|func|var|let|if|else|guard|switch|case|for|while|return|throw|throws|async|await|private|public|internal|static|self|nil|true|false)\b"#
        }
        if lowercasedLanguage.contains("python") || lowercasedLanguage == "py" {
            return #"\b(import|from|def|class|if|elif|else|for|while|return|try|except|finally|with|as|lambda|None|True|False|async|await|yield|in|is|not|and|or)\b"#
        }
        if lowercasedLanguage.contains("js") || lowercasedLanguage.contains("ts") || lowercasedLanguage.contains("javascript") || lowercasedLanguage.contains("typescript") {
            return #"\b(import|export|function|const|let|var|if|else|switch|case|for|while|return|async|await|class|extends|new|this|null|undefined|true|false|type|interface)\b"#
        }
        return #"\b(if|else|for|while|return|class|struct|enum|func|function|let|var|const|true|false|null|nil|import|from|export|async|await)\b"#
    }
    
    private static func apply(pattern: String, color: Color, to attributed: inout AttributedString, source: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)
        
        for match in matches {
            guard let stringRange = Range(match.range, in: source),
                  let attributedRange = Range(stringRange, in: attributed) else {
                continue
            }
            attributed[attributedRange].foregroundColor = color
        }
    }
}

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    @Environment(\.colorScheme) private var colorScheme
    
    private var columnWidths: [CGFloat] {
        headers.indices.map { index in
            let values = [headers[index]] + rows.map { index < $0.count ? $0[index] : "" }
            let longest = values.map(\.count).max() ?? 0
            let width = CGFloat(longest) * 18 + 28
            return min(max(width, 132), 240)
        }
    }
    
    private var borderColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.28 : 0.20)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { column, header in
                        tableCell(header, isHeader: true)
                            .frame(width: columnWidths[safe: column] ?? 168, alignment: .leading)
                    }
                }
                
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { column in
                            tableCell(column < row.count ? row[column] : "", isHeader: false)
                                .frame(width: columnWidths[safe: column] ?? 168, alignment: .leading)
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
    }
    
    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        InlineMarkdownText(text)
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isHeader ? Color.secondary.opacity(0.10) : Color.clear)
            .border(borderColor, width: 0.5)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
