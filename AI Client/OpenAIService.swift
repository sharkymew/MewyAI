//
//  OpenAIService.swift
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

class OpenAIService {
    private var conversationHistory: [Message] = [
        Message(
            role: "system",
            content: "你是一个友好且有帮助的AI助手。"
        )
    ]
    
    func sendMessage(
        message: String,
        apiKey: String,
        completion: @escaping (String) -> Void
    ) {
        
        guard let url = URL(
            string: "https://api.deepseek.com/chat/completions"
        ) else {
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
            return
        }
        
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) {
            data,
            response,
            error in
            
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
        apiKey: String,
        onReasoningToken: @escaping (String) -> Void,
        onContentToken: @escaping (String) -> Void,
        onComplete: @escaping (_ reasoningText: String, _ contentText: String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let url = URL(
            string: "https://api.deepseek.com/chat/completions"
        ) else {
            onError("URL无效")
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
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        request.setValue(
            "text/event-stream",
            forHTTPHeaderField: "Accept"
        )
        
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        
        request.httpBody = jsonData
        
        Task {
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
            } catch {
                await MainActor.run {
                    onError("流式请求失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
