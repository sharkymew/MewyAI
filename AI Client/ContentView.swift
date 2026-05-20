import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
    var contentChunks: [String] = []
    var reasoningContent: String = ""
    var reasoningChunks: [String] = []
    var isReasoningExpanded: Bool = false
    var isStopped: Bool = false
}

struct ContentView: View {
    
    @AppStorage("apiKey") private var apiKey = ""
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var showAPIKey = false
    @State private var shouldAutoScroll = true
    @State private var scrollVersion = 0
    @State private var pendingReasoningText = ""
    @State private var pendingContentText = ""
    @State private var isFlushScheduled = false
    @State private var activeAssistantMessageID: UUID?
    @FocusState private var isInputFocused: Bool
    
    let openAIService = OpenAIService()
    
    var body: some View {
        VStack(spacing: 0) {
            apiKeyInputView
            
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
                .onChange(of: messages.count) { _, _ in
                    forceScrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: scrollVersion) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            
            Divider()
            
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "输入消息...",
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .disabled(isGenerating)
                
                Button {
                    shouldAutoScroll = true
                    scrollVersion += 1
                } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.bordered)
                
                Button {
                    hideKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.bordered)
                
                Button {
                    if isGenerating {
                        stopGenerating()
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !isGenerating
                    && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding()
            .background(.regularMaterial)
        }
    }
    
    private var apiKeyInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.headline)
                
                Spacer()
                
                Button(showAPIKey ? "隐藏" : "显示") {
                    showAPIKey.toggle()
                }
                .font(.caption)
            }
            
            if showAPIKey {
                TextField(
                    "输入你的 API Key",
                    text: $apiKey
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } else {
                SecureField(
                    "输入你的 API Key",
                    text: $apiKey
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            
            Text("API Key 会保存在本机 AppStorage 中，适合自己测试用；正式发布 App 时不要把供应商 Key 放在客户端。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
    }
    
    func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !userText.isEmpty else { return }
        
        guard !trimmedAPIKey.isEmpty else {
            messages.append(
                ChatMessage(
                    role: "assistant",
                    content: "请先输入 API Key。"
                )
            )
            return
        }
        
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
        
        let assistantMessageID = messages.last?.id
        activeAssistantMessageID = assistantMessageID
        
        openAIService.sendStreamingMessage(
            message: userText,
            apiKey: trimmedAPIKey,
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
    }
    
    func stopGenerating() {
        let stoppedMessageID = activeAssistantMessageID
        
        openAIService.cancelStreaming()
        
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
}

struct MessageBubble: View {
    @Binding var message: ChatMessage
    
    private var isUser: Bool {
        message.role == "user"
    }
    
    private var messageContentBubble: some View {
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
        .foregroundStyle(isUser ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? Color.accentColor : Color.gray.opacity(0.16))
        )
        .frame(
            maxWidth: UIScreen.main.bounds.width * 0.78,
            alignment: isUser ? .trailing : .leading
        )
        .textSelection(.enabled)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 48)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !isUser && !message.reasoningContent.isEmpty {
                    reasoningBlock
                }
                
                messageContentBubble
            }
            
            if !isUser {
                Spacer(minLength: 48)
            }
        }
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
                        .fill(Color.gray.opacity(0.10))
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
        .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .clipped()
    }
}

#Preview {
    ContentView()
}
