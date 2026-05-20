import SwiftUI

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
    @State private var activeAssistantMessageID: UUID?
    @FocusState private var isInputFocused: Bool
    
    let aiService = AIService()
    
    private var inputFieldBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.82)
    }
    
    private var inputControlBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }
    
    private var sendControlBackground: Color {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
            ? inputControlBackground
            : Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.16)
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
            .gesture(sidebarGesture)
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
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            configurationBar
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($messages) { $message in
                            MessageBubble(message: $message)
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
    }
    
    private var inputBar: some View {
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
            
            Button {
                shouldAutoScroll = true
                scrollVersion += 1
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(inputControlBackground))
            }
            .buttonStyle(.plain)
            
            modelMenu
            
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
            .disabled(
                !isGenerating
                && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
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
    
    private var modelMenu: some View {
        Menu {
            ForEach(currentConfiguration.models, id: \.self) { model in
                Button {
                    selectModel(model)
                } label: {
                    if model == currentConfiguration.selectedModel {
                        Label(model, systemImage: "checkmark")
                    } else {
                        Text(model)
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
                
                Text(configurationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    
    private var sidebarGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if !showConversationSidebar,
                   value.startLocation.x < 32,
                   value.translation.width > 70 {
                    showConversationSidebar = true
                } else if showConversationSidebar,
                          value.translation.width < -70 {
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
        return "\(configuration.name) · \(configuration.selectedModel) · \(trimmedBaseURL.isEmpty ? "未配置 Base URL" : trimmedBaseURL) · \(endpointSummary) · \(authSummary)"
    }
    
    func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !userText.isEmpty else { return }
        
        guard !trimmedBaseURL.isEmpty else {
            messages.append(
                ChatMessage(
                    role: "assistant",
                    content: "请先配置 Base URL。"
                )
            )
            persistCurrentConversation()
            return
        }
        
        guard !model.isEmpty else {
            messages.append(
                ChatMessage(
                    role: "assistant",
                    content: "请先选择模型。"
                )
            )
            persistCurrentConversation()
            return
        }
        
        ensureCurrentConversation()
        aiService.resetConversation(with: messages)
        
        inputText = ""
        isInputFocused = false
        isGenerating = true
        shouldAutoScroll = true
        scrollVersion += 1
        pendingReasoningText = ""
        pendingContentText = ""
        isFlushScheduled = false
        
        messages.append(
            ChatMessage(
                role: "user",
                content: userText
            )
        )
        
        messages.append(
            ChatMessage(
                role: "assistant",
                content: ""
            )
        )
        persistCurrentConversation()
        
        let assistantMessageID = messages.last?.id
        activeAssistantMessageID = assistantMessageID
        
        aiService.sendStreamingMessage(
            message: userText,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            onReasoningToken: { token in
                guard let assistantMessageID else { return }
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }
                
                pendingReasoningText += token
                scheduleTokenFlush(for: assistantMessageID)
            },
            onContentToken: { token in
                guard let assistantMessageID else { return }
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }
                
                pendingContentText += token
                scheduleTokenFlush(for: assistantMessageID)
            },
            onComplete: { _, _ in
                guard let assistantMessageID else {
                    isGenerating = false
                    activeAssistantMessageID = nil
                    return
                }
                guard activeAssistantMessageID == assistantMessageID else { return }
                
                flushPendingTokens(for: assistantMessageID)
                finalizeMessageLayout(for: assistantMessageID)
                isGenerating = false
                activeAssistantMessageID = nil
                persistCurrentConversation()
                generateTitleIfNeeded()
            },
            onError: { error in
                guard let assistantMessageID else { return }
                guard activeAssistantMessageID == assistantMessageID else { return }
                
                flushPendingTokens(for: assistantMessageID)
                
                if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                    messages[index].content = error
                    messages[index].contentChunks = []
                }
                
                isGenerating = false
                activeAssistantMessageID = nil
                persistCurrentConversation()
            }
        )
    }
    
    func finalizeMessageLayout(for messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        
        var transaction = Transaction()
        transaction.animation = nil
        
        withTransaction(transaction) {
            if !messages[index].contentChunks.isEmpty {
                messages[index].content = messages[index].contentChunks.joined()
                messages[index].contentChunks = []
            }
            
            if !messages[index].reasoningChunks.isEmpty {
                messages[index].reasoningContent = messages[index].reasoningChunks.joined()
                messages[index].reasoningChunks = []
            }
        }
    }
    
    func scheduleTokenFlush(for messageID: UUID) {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            flushPendingTokens(for: messageID)
        }
    }
    
    func flushPendingTokens(for messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            pendingReasoningText = ""
            pendingContentText = ""
            isFlushScheduled = false
            return
        }
        
        var transaction = Transaction()
        transaction.animation = nil
        
        withTransaction(transaction) {
            if !pendingReasoningText.isEmpty {
                messages[index].reasoningContent += pendingReasoningText
                
                if let lastChunk = messages[index].reasoningChunks.last,
                   lastChunk.count < 1600 {
                    messages[index].reasoningChunks[messages[index].reasoningChunks.count - 1] += pendingReasoningText
                } else {
                    messages[index].reasoningChunks.append(pendingReasoningText)
                }
                
                pendingReasoningText = ""
            }
            
            if !pendingContentText.isEmpty {
                if let lastChunk = messages[index].contentChunks.last,
                   lastChunk.count < 1600 {
                    messages[index].contentChunks[messages[index].contentChunks.count - 1] += pendingContentText
                } else {
                    messages[index].contentChunks.append(pendingContentText)
                }
                
                messages[index].isReasoningExpanded = false
                pendingContentText = ""
            }
        }
        
        if shouldAutoScroll {
            scrollVersion += 1
        }
        
        isFlushScheduled = false
        persistCurrentConversation()
    }
    
    func stopGenerating() {
        let stoppedMessageID = activeAssistantMessageID
        
        aiService.cancelStreaming()
        
        if let stoppedMessageID {
            flushPendingTokens(for: stoppedMessageID)
            finalizeMessageLayout(for: stoppedMessageID)
            
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
        if !configurations[index].models.contains(model) {
            configurations[index].models.append(model)
        }
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
        activeAssistantMessageID = nil
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
        activeAssistantMessageID = nil
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
            activeAssistantMessageID = nil
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
        
        guard !model.isEmpty else { return }
        
        aiService.generateConversationTitle(
            messages: titleMessages,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model
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
    
    private func messageContentBubble(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.content.isEmpty && message.contentChunks.isEmpty {
                Text(message.isStopped ? "已停止生成。" : "正在生成回答...")
            } else if message.contentChunks.isEmpty {
                Text(message.isStopped ? message.content + "\n\n已停止生成。" : message.content)
            } else {
                ForEach(message.contentChunks.indices, id: \.self) { index in
                    Text(message.contentChunks[index])
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.body)
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? userBubbleColor : assistantBubbleColor)
        )
        .frame(
            maxWidth: maxWidth,
            alignment: isUser ? .trailing : .leading
        )
        .textSelection(.enabled)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                if isUser {
                    Spacer(minLength: 48)
                }
                
                VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                    if !isUser && !message.reasoningContent.isEmpty {
                        reasoningBlock(maxWidth: geometry.size.width * 0.78)
                    }
                    
                    messageContentBubble(maxWidth: geometry.size.width * 0.78)
                }
                
                if !isUser {
                    Spacer(minLength: 48)
                }
            }
        }
        .frame(minHeight: 1)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func reasoningBlock(maxWidth: CGFloat) -> some View {
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
                    if message.reasoningChunks.isEmpty {
                        Text(message.reasoningContent)
                    } else {
                        ForEach(message.reasoningChunks.indices, id: \.self) { index in
                            Text(message.reasoningChunks[index])
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .clipped()
    }
}

#Preview {
    ContentView()
}
