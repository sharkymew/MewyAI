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
    
    func sendMessage(
        message: String,
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        completion: @escaping (String) -> Void
    ) {
        guard let url = URL(string: baseURL) else {
            completion("Base URL 无效")
            return
        }
        
        conversationHistory.append(
            Message(
                role: "user",
                content: message
            )
        )
        
        let requestBody = OpenAIRequest(
            model: "deepseek-v4-pro",
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
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    completion("请求失败")
                }
                return
            }
            
            print(String(data: data, encoding: .utf8) ?? "无数据")
            
            DispatchQueue.main.async {
                if let decoded = try? JSONDecoder()
                    .decode(OpenAIResponse.self, from: data) {
                    
                    let text = decoded
                        .choices
                        .first?
                        .message
                        .content ?? "无回复"
                    
                    self.conversationHistory.append(
                        Message(
                            role: "assistant",
                            content: text
                        )
                    )
                    
                    completion(text)
                } else {
                    completion("解析失败")
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
            Message(
                role: "user",
                content: message
            )
        )
        
        let requestBody = OpenAIRequest(
            model: "deepseek-v4-pro",
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
                    await MainActor.run {
                        onError("请求失败，状态码：\(httpResponse.statusCode)")
                    }
                    return
                }
                
                var fullReasoningText = ""
                var fullContentText = ""
                
                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }
                    
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        
                        if jsonString == "[DONE]" {
                            conversationHistory.append(
                                Message(
                                    role: "assistant",
                                    content: fullContentText
                                )
                            )
                            
                            await MainActor.run {
                                onComplete(fullReasoningText, fullContentText)
                            }
                            
                            streamingTask = nil
                            return
                        }
                        
                        guard let data = jsonString.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(
                                OpenAIStreamResponse.self,
                                from: data
                              ) else {
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
                }
                
                conversationHistory.append(
                    Message(
                        role: "assistant",
                        content: fullContentText
                    )
                )
                
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
}
