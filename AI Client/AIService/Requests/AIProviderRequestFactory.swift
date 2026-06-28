//
//  AIProviderRequestFactory.swift
//  AI Client
//
//  Created by Codex on 2026/6/18.
//
import Foundation

enum AIProviderRequestFactory {
    static func makeRequest(
        url: URL,
        apiFormat: AIAPIFormat,
        model: String = "",
        apiKey: String,
        customHeaders: String,
        acceptsEventStream: Bool
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if acceptsEventStream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            switch apiFormat {
            case .openAIChatCompletions, .openAIResponses:
                request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
            case .vertexAIExpress:
                break
            }
        }

        if apiFormat == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        for header in CustomHeaderSecurity.requestHeaders(from: customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        return request
    }

    static func requestURL(
        from urlString: String,
        apiFormat: AIAPIFormat,
        model: String,
        apiKey: String,
        isStreaming: Bool
    ) throws -> URL {
        var resolvedURLString = urlString
        if apiFormat == .vertexAIExpress {
            let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            resolvedURLString = resolvedURLString.replacingOccurrences(of: "{model}", with: encodedModel)
        }

        let url = try AIService.validatedRequestURL(from: resolvedURLString)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AIServiceError.invalidURL
        }

        if apiFormat == .vertexAIExpress {
            if isStreaming, components.path.hasSuffix(":generateContent") {
                components.path = String(components.path.dropLast(":generateContent".count)) + ":streamGenerateContent"
            }

            var queryItems = components.queryItems ?? []
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAPIKey.isEmpty {
                queryItems.removeAll { $0.name == "key" }
                queryItems.append(URLQueryItem(name: "key", value: trimmedAPIKey))
            }
            if isStreaming {
                queryItems.removeAll { $0.name == "alt" }
                queryItems.append(URLQueryItem(name: "alt", value: "sse"))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems
        }

        guard let requestURL = components.url else {
            throw AIServiceError.invalidURL
        }
        return requestURL
    }

    static func decodedResponseText(from data: Data, apiFormat: AIAPIFormat) -> String? {
        let decoder = JSONDecoder()
        switch apiFormat {
        case .openAIChatCompletions:
            return (try? decoder.decode(OpenAIResponse.self, from: data))?
                .choices
                .first?
                .message
                .content
        case .openAIResponses:
            return (try? decoder.decode(OpenAIResponsesResponse.self, from: data))?.outputText
        case .anthropicMessages:
            return (try? decoder.decode(AnthropicResponse.self, from: data))?.outputText
        case .vertexAIExpress:
            return (try? decoder.decode(VertexGenerateContentResponse.self, from: data))?.outputText
        }
    }

    static func modelsURL(from baseURL: String, apiFormat: AIAPIFormat, filtersTextChatModels: Bool) throws -> URL {
        let url = try AIService.validatedRequestURL(from: baseURL)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AIServiceError.invalidURL
        }

        let path = components.path
        if apiFormat == .anthropicMessages {
            if path.hasSuffix("/v1/messages") {
                components.path = String(path.dropLast("/v1/messages".count)) + "/v1/models"
            } else if path.hasSuffix("/messages") {
                components.path = String(path.dropLast("/messages".count)) + "/models"
            } else {
                let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                components.path = basePath.isEmpty ? "/v1/models" : "/" + basePath + "/v1/models"
            }
        } else if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/responses") {
            components.path = String(path.dropLast("/responses".count)) + "/models"
        } else {
            let basePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = basePath.isEmpty ? "/models" : "/" + basePath + "/models"
        }
        components.query = nil

        if filtersTextChatModels, apiFormat == .openAIChatCompletions {
            components.queryItems = [
                URLQueryItem(name: "type", value: "text"),
                URLQueryItem(name: "sub_type", value: "chat")
            ]
        }

        guard let modelsURL = components.url else {
            throw AIServiceError.invalidURL
        }
        return modelsURL
    }

}
