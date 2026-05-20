//
//  AIService.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//
import Foundation

struct OpenAIRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
}

struct Message: Codable {
    let role: String
    let content: String
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

struct ModelListResponse: Codable {
    let data: [ModelItem]
}

struct ModelItem: Codable {
    let id: String
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
    private var conversationHistory: [Message] = [
        Message(
            role: "system",
            content: "你是一个友好且有帮助的AI助手。"
        )
    ]
    
    private var streamingTask: Task<Void, Never>?
    
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }
    
    func resetConversation(with messages: [ChatMessage]) {
        conversationHistory = [
            Message(
                role: "system",
                content: "你是一个友好且有帮助的AI助手。"
            )
        ]
        
        conversationHistory.append(
            contentsOf: messages.compactMap { message in
                let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty, message.role == "user" || message.role == "assistant" else {
                    return nil
                }
                
                return Message(role: message.role, content: content)
            }
        )
    }
    
    func fetchModels(
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        completion: @escaping (Result<[String], AIServiceError>) -> Void
    ) {
        guard let url = modelsURL(from: baseURL) else {
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
                
                let models = decoded.data.map(\.id).filter { !$0.isEmpty }.sorted()
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
            Message(
                role: "system",
                content: "请根据对话内容生成一个简短中文标题。只输出标题，不要解释，不要加引号，最多12个字。"
            ),
            Message(role: "user", content: transcript)
        ]
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: titleMessages,
            stream: false
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
                
                let title = decoded.choices.first?.message.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
                
                completion(title?.isEmpty == false ? title : nil)
            }
        }
        .resume()
    }
    
    func sendMessage(
        message: String,
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
        completion: @escaping (String) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion("Base URL 无效")
            return
        }
        
        conversationHistory.append(Message(role: "user", content: message))
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: conversationHistory,
            stream: false
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
                    self.conversationHistory.append(Message(role: "assistant", content: text))
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
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
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
        
        conversationHistory.append(Message(role: "user", content: message))
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: conversationHistory,
            stream: true
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
                        conversationHistory.append(Message(role: "assistant", content: fullContentText))
                        
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
                
                conversationHistory.append(Message(role: "assistant", content: fullContentText))
                
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
    
    private func modelsURL(from baseURL: String) -> URL? {
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
        
        return components.url
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
