//
//  AIService.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool
    let thinking: ThinkingConfig?
    let reasoningEffort: ReasoningEffort?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

struct ThinkingConfig: Codable {
    let type: String
}

struct Message: Codable {
    let role: String
    let content: String
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: ChatRequestContent
    
    init(role: String, text: String) {
        self.role = role
        self.content = .text(text)
    }
    
    init(role: String, text: String, imageAttachments: [ChatImageAttachment]) {
        self.role = role
        
        guard !imageAttachments.isEmpty else {
            content = .text(text)
            return
        }
        
        var parts = [ChatRequestContent.Part]()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(.text(trimmedText))
        }
        parts.append(contentsOf: imageAttachments.map { .imageURL($0.dataURL) })
        content = .parts(parts)
    }
}

enum ChatRequestContent: Encodable {
    case text(String)
    case parts([Part])
    
    enum Part: Encodable {
        case text(String)
        case imageURL(String)
        
        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
        
        enum ImageURLCodingKeys: String, CodingKey {
            case url
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                var imageContainer = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
                try imageContainer.encode(url, forKey: .url)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct OpenAIStreamResponse: Codable {
    let choices: [StreamChoice]
}

struct StreamChoice: Codable {
    let delta: StreamDelta
}

struct StreamDelta: Codable {
    let reasoningContent: String?
    let content: String?
    
    enum CodingKeys: String, CodingKey {
        case reasoningContent = "reasoning_content"
        case content
    }
}

struct ModelListResponse: Decodable {
    let data: [ModelItem]
}

struct ModelItem: Decodable {
    let id: String
    let supportsReasoning: Bool?
    let supportsImages: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case supportsReasoning = "supports_reasoning"
        case supportsImages = "supports_images"
        case multimodal
        case vision
        case reasoning
        case thinking
        case capabilities
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let directSupport = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning)
        let reasoningSupport = try container.decodeIfPresent(Bool.self, forKey: .reasoning)
        let thinkingSupport = try container.decodeIfPresent(Bool.self, forKey: .thinking)
        let directImageSupport = try container.decodeIfPresent(Bool.self, forKey: .supportsImages)
        let multimodalSupport = try container.decodeIfPresent(Bool.self, forKey: .multimodal)
        let visionSupport = try container.decodeIfPresent(Bool.self, forKey: .vision)
        let capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities)
        supportsReasoning = directSupport
            ?? reasoningSupport
            ?? thinkingSupport
            ?? capabilities?.supportsReasoning
        supportsImages = directImageSupport
            ?? multimodalSupport
            ?? visionSupport
            ?? capabilities?.supportsImages
    }
}

struct ModelCapabilities: Decodable {
    let supportsReasoning: Bool?
    let supportsImages: Bool?
    
    enum CodingKeys: String, CodingKey {
        case supportsReasoning = "supports_reasoning"
        case supportsImages = "supports_images"
        case multimodal
        case vision
        case reasoning
        case thinking
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning)
            ?? container.decodeIfPresent(Bool.self, forKey: .reasoning)
            ?? container.decodeIfPresent(Bool.self, forKey: .thinking)
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages)
            ?? container.decodeIfPresent(Bool.self, forKey: .multimodal)
            ?? container.decodeIfPresent(Bool.self, forKey: .vision)
    }
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case encodingFailed
    case requestFailed(String)
    case decodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL 无效"
        case .encodingFailed:
            return "请求体编码失败"
        case .requestFailed(let message), .decodingFailed(let message):
            return message
        }
    }
}

class AIService {
    private var conversationHistory = AIService.initialConversationHistory(
        systemPrompt: AIConfiguration.defaultSystemPrompt
    )
    
    private var streamingTask: Task<Void, Never>?
    
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }
    
    func resetConversation(
        with messages: [ChatMessage],
        systemPrompt: String = AIConfiguration.defaultSystemPrompt
    ) {
        conversationHistory = Self.initialConversationHistory(systemPrompt: systemPrompt)
        
        conversationHistory.append(
            contentsOf: messages.compactMap { message in
                let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasImages = !message.imageAttachments.isEmpty
                guard (hasImages || !content.isEmpty), message.role == "user" || message.role == "assistant" else {
                    return nil
                }
                
                return ChatRequestMessage(
                    role: message.role,
                    text: content,
                    imageAttachments: message.role == "user" ? message.imageAttachments : []
                )
            }
        )
    }

    private static func initialConversationHistory(systemPrompt: String) -> [ChatRequestMessage] {
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return [] }
        return [ChatRequestMessage(role: "system", text: trimmedPrompt)]
    }
    
    func fetchModels(
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        completion: @escaping (Result<[AIModelConfiguration], AIServiceError>) -> Void
    ) {
        guard let url = modelsURL(from: baseURL, filtersTextChatModels: true) else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = makeRequest(
            url: url,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false
        )
        request.httpMethod = "GET"
        request.httpBody = nil
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(.requestFailed("模型列表请求失败：\(error.localizedDescription)")))
                }
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let responseText = Self.responseText(from: data)
            
            guard let statusCode, (200...299).contains(statusCode) else {
                DispatchQueue.main.async {
                    completion(.failure(.requestFailed(Self.errorMessage(statusCode: statusCode, body: responseText))))
                }
                return
            }
            
            DispatchQueue.main.async {
                guard let data,
                      let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                    completion(.failure(.decodingFailed("模型列表解析失败：\(responseText)")))
                    return
                }
                
                let models = decoded.data
                    .filter { !$0.id.isEmpty }
                    .filter { Self.isTextChatModel($0.id) }
                    .map { item in
                        AIModelConfiguration(
                            name: item.id,
                            supportsReasoning: item.supportsReasoning ?? Self.infersReasoningSupport(for: item.id),
                            supportsImages: item.supportsImages ?? Self.infersImageSupport(for: item.id)
                        )
                    }
                    .sorted { $0.name < $1.name }
                completion(.success(models))
            }
        }
        .resume()
    }
    
    func generateConversationTitle(
        messages: [ChatMessage],
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String?) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion(nil)
            return
        }
        
        let transcript = messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")
        
        guard !transcript.isEmpty else {
            completion(nil)
            return
        }
        
        let titleMessages = [
            ChatRequestMessage(
                role: "system",
                text: "请根据对话内容生成一个中文标题。只输出标题文字，不要解释，不要引号、方框、括号、Markdown、项目符号或任何额外格式，最多10个字。"
            ),
            ChatRequestMessage(role: "user", text: transcript)
        ]
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: titleMessages,
            stream: false,
            thinking: thinkingConfig(from: reasoningEnabled),
            reasoningEffort: reasoningEnabled == true ? reasoningEffort : nil
        )
        
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            completion(nil)
            return
        }
        
        var request = makeRequest(
            url: url,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false
        )
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let data,
                      let statusCode,
                      (200...299).contains(statusCode),
                      let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data) else {
                    completion(nil)
                    return
                }
                
                let title = Self.sanitizedConversationTitle(decoded.choices.first?.message.content)
                
                completion(title?.isEmpty == false ? title : nil)
            }
        }
        .resume()
    }

    private nonisolated static func sanitizedConversationTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle else { return nil }

        let formatCharacters = CharacterSet(charactersIn: "\"'“”‘’[]【】()（）{}《》<>#*-_`·•「」『』")
        let words = rawTitle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(formatCharacters)) }
            .filter { !$0.isEmpty }
        var title = (words.first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(formatCharacters))
        for prefix in ["标题：", "标题:", "题目：", "题目:"] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(formatCharacters))
            break
        }

        guard !title.isEmpty else { return nil }
        return String(title.prefix(10))
    }
    
    func sendMessage(
        message: String,
        imageAttachments: [ChatImageAttachment] = [],
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        completion: @escaping (String) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion("Base URL 无效")
            return
        }
        
        conversationHistory.append(
            ChatRequestMessage(
                role: "user",
                text: message,
                imageAttachments: imageAttachments
            )
        )
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: conversationHistory,
            stream: false,
            thinking: thinkingConfig(from: reasoningEnabled),
            reasoningEffort: reasoningEnabled == true ? reasoningEffort : nil
        )
        
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            completion("请求体编码失败")
            return
        }
        
        var request = makeRequest(
            url: url,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: false
        )
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion("请求失败：\(error.localizedDescription)")
                }
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let responseText = Self.responseText(from: data)
            
            guard let statusCode, (200...299).contains(statusCode) else {
                DispatchQueue.main.async {
                    completion(Self.errorMessage(statusCode: statusCode, body: responseText))
                }
                return
            }
            
            DispatchQueue.main.async {
                if let data,
                   let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data) {
                    let text = decoded.choices.first?.message.content ?? "无回复"
                    self.conversationHistory.append(ChatRequestMessage(role: "assistant", text: text))
                    completion(text)
                } else {
                    completion("解析失败：\(responseText)")
                }
            }
        }
        .resume()
    }
    
    func sendStreamingMessage(
        message: String,
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ reasoningText: String, _ contentText: String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        cancelStreaming()
        
        guard let url = URL(string: baseURL) else {
            onError("Base URL 无效")
            return
        }
        
        conversationHistory.append(
            ChatRequestMessage(
                role: "user",
                text: message,
                imageAttachments: imageAttachments
            )
        )
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: conversationHistory,
            stream: true,
            thinking: thinkingConfig(from: reasoningEnabled),
            reasoningEffort: reasoningEnabled == true ? reasoningEffort : nil
        )
        
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            onError("请求体编码失败")
            return
        }
        
        var request = makeRequest(
            url: url,
            apiKey: apiKey,
            customHeaders: customHeaders,
            acceptsEventStream: true
        )
        request.httpBody = jsonData
        
        streamingTask = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let errorBody = await Self.collectErrorBody(from: bytes)
                    await MainActor.run {
                        onError(Self.errorMessage(statusCode: httpResponse.statusCode, body: errorBody))
                    }
                    return
                }
                
                var fullReasoningText = ""
                var fullContentText = ""
                
                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }
                    
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonString = String(line.dropFirst(6))
                    
                    if jsonString == "[DONE]" {
                        conversationHistory.append(ChatRequestMessage(role: "assistant", text: fullContentText))
                        
                        await MainActor.run {
                            onComplete(fullReasoningText, fullContentText)
                        }
                        
                        streamingTask = nil
                        return
                    }
                    
                    guard let data = jsonString.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: data) else {
                        continue
                    }
                    
                    let delta = decoded.choices.first?.delta
                    
                    if let reasoningToken = delta?.reasoningContent,
                       !reasoningToken.isEmpty {
                        fullReasoningText += reasoningToken
                        
                        await MainActor.run {
                            onReasoningToken(reasoningToken)
                        }
                    }
                    
                    if let contentToken = delta?.content,
                       !contentToken.isEmpty {
                        fullContentText += contentToken
                        
                        await MainActor.run {
                            onContentToken(contentToken)
                        }
                    }
                }
                
                conversationHistory.append(ChatRequestMessage(role: "assistant", text: fullContentText))
                
                await MainActor.run {
                    onComplete(fullReasoningText, fullContentText)
                }
                
                streamingTask = nil
            } catch {
                if Task.isCancelled {
                    return
                }
                
                await MainActor.run {
                    onError("流式请求失败：\(error.localizedDescription)")
                }
                
                streamingTask = nil
            }
        }
    }
    
    private func makeRequest(
        url: URL,
        apiKey: String,
        customHeaders: String,
        acceptsEventStream: Bool
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if acceptsEventStream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }
        
        for header in parseCustomHeaders(customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        
        return request
    }
    
    private func parseCustomHeaders(_ text: String) -> [(name: String, value: String)] {
        text
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty,
                      let separatorIndex = trimmedLine.firstIndex(of: ":") else {
                    return nil
                }
                
                let name = trimmedLine[..<separatorIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmedLine[trimmedLine.index(after: separatorIndex)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !name.isEmpty, !value.isEmpty else {
                    return nil
                }
                
                return (name: String(name), value: String(value))
            }
    }
    
    private func thinkingConfig(from reasoningEnabled: Bool?) -> ThinkingConfig? {
        guard let reasoningEnabled else { return nil }
        return ThinkingConfig(type: reasoningEnabled ? "enabled" : "disabled")
    }
    
    private func modelsURL(from baseURL: String, filtersTextChatModels: Bool) -> URL? {
        guard let url = URL(string: baseURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let path = components.path
        if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/responses") {
            components.path = String(path.dropLast("/responses".count)) + "/models"
        } else {
            let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty ? "/models" : "/" + basePath + "/models"
        }
        components.query = nil
        
        if filtersTextChatModels {
            components.queryItems = [
                URLQueryItem(name: "type", value: "text"),
                URLQueryItem(name: "sub_type", value: "chat")
            ]
        }
        
        return components.url
    }
    
    private nonisolated static func isTextChatModel(_ modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let nonChatKeywords = [
            "embedding",
            "embeddings",
            "embed",
            "rerank",
            "reranker",
            "ranker",
            "stable-diffusion",
            "sdxl",
            "flux",
            "kolors",
            "qwen-image",
            "image-edit",
            "text-to-image",
            "image-to-image",
            "cogvideo",
            "video",
            "wan",
            "audio",
            "speech",
            "voice",
            "tts",
            "whisper",
            "sensevoice",
            "funaudio",
            "cosyvoice",
            "fish-speech"
        ]
        
        return !nonChatKeywords.contains { lowercasedID.contains($0) }
    }
    
    private nonisolated static func infersReasoningSupport(for modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let reasoningKeywords = [
            "deepseek-r1",
            "qwq",
            "qvq",
            "qwen3",
            "glm-z1",
            "glm-4.5",
            "glm-5",
            "o1",
            "o3",
            "o4",
            "gpt-5",
            "grok-3-mini",
            "grok-4",
            "magistral",
            "thinking"
        ]
        
        return reasoningKeywords.contains { lowercasedID.contains($0) }
    }
    
    private nonisolated static func infersImageSupport(for modelID: String) -> Bool {
        let lowercasedID = modelID.lowercased()
        let imageInputKeywords = [
            "vision",
            "visual",
            "vl",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "qwen3-vl",
            "glm-4v",
            "glm-4.1v",
            "gpt-4o",
            "gpt-4.1",
            "gpt-5",
            "claude-3",
            "claude-4",
            "gemini",
            "llava",
            "internvl",
            "minicpm-v",
            "mllama",
            "pixtral"
        ]
        
        return imageInputKeywords.contains { lowercasedID.contains($0) }
    }
    
    private static func responseText(from data: Data?) -> String {
        guard let data, !data.isEmpty else { return "无响应正文" }
        return String(data: data, encoding: .utf8) ?? "响应正文不是 UTF-8 文本"
    }
    
    private static func errorMessage(statusCode: Int?, body: String) -> String {
        if let statusCode {
            return "请求失败，状态码：\(statusCode)\n\n\(body)"
        }
        
        return "请求失败\n\n\(body)"
    }
    
    private static func collectErrorBody(
        from bytes: URLSession.AsyncBytes,
        maxCharacters: Int = 4000
    ) async -> String {
        var body = ""
        
        do {
            for try await line in bytes.lines {
                if !body.isEmpty {
                    body += "\n"
                }
                body += line
                if body.count >= maxCharacters {
                    return String(body.prefix(maxCharacters))
                }
            }
        } catch {
            return "读取错误响应失败：\(error.localizedDescription)"
        }
        
        return body.isEmpty ? "无响应正文" : body
    }
}
