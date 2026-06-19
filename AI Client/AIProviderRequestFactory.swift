//
//  AIProviderRequestFactory.swift
//  AI Client
//
//  Created by Codex on 2026/6/18.
//
import Foundation

enum AIProviderRequestFactory {
    private static let anthropicClaudeCodeBetaHeader = "context-1m-2025-08-07,claude-code-20250219,interleaved-thinking-2025-05-14,thinking-token-count-2026-05-13,context-management-2025-06-27,prompt-caching-scope-2026-01-05,mid-conversation-system-2026-04-07,advisor-tool-2026-03-01,effort-2025-11-24"
    private static let anthropicOneMillionContextBetaHeader = "context-1m-2025-08-07,context-management-2025-06-27"
    private static let anthropicClaudeCodeManagedHeaders: Set<String> = [
        "accept",
        "authorization",
        "content-type",
        "x-api-key",
        "anthropic-version",
        "anthropic-beta",
        "anthropic-dangerous-direct-browser-access",
        "user-agent",
        "x-app",
        "x-claude-code-session-id"
    ]

    static func makeRequest(
        url: URL,
        apiFormat: AIAPIFormat,
        model: String = "",
        apiKey: String,
        customHeaders: String,
        acceptsEventStream: Bool,
        anthropicClaudeCodeImpersonationEnabled: Bool = false,
        anthropicClaudeCodeMetadata: AnthropicClaudeCodeMetadata? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if acceptsEventStream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesAnthropicClaudeCodeImpersonation = apiFormat == .anthropicMessages
            && anthropicClaudeCodeImpersonationEnabled
        let usesAnthropicOneMillionContext = apiFormat == .anthropicMessages
            && (anthropicClaudeCodeImpersonationEnabled
                || AIRequestBodyBuilder.anthropicModelSelection(from: model).usesOneMillionContext)

        if usesAnthropicClaudeCodeImpersonation {
            request.setValue("application/json", forHTTPHeaderField: "accept")
        }

        if !trimmedAPIKey.isEmpty {
            switch apiFormat {
            case .openAIChatCompletions, .openAIResponses:
                request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                if usesAnthropicClaudeCodeImpersonation {
                    request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "authorization")
                } else {
                    request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
                }
            case .vertexAIExpress:
                break
            }
        }

        if apiFormat == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        if usesAnthropicClaudeCodeImpersonation {
            request.setValue(anthropicClaudeCodeBetaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue("true", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")
            request.setValue("claude-cli/2.1.156 (external, sdk-cli)", forHTTPHeaderField: "user-agent")
            request.setValue("cli", forHTTPHeaderField: "x-app")
            if let anthropicClaudeCodeMetadata {
                request.setValue(anthropicClaudeCodeMetadata.sessionID, forHTTPHeaderField: "x-claude-code-session-id")
            }
            request.setValue("arm64", forHTTPHeaderField: "x-stainless-arch")
            request.setValue("js", forHTTPHeaderField: "x-stainless-lang")
            request.setValue("MacOS", forHTTPHeaderField: "x-stainless-os")
            request.setValue("0.94.0", forHTTPHeaderField: "x-stainless-package-version")
            request.setValue("0", forHTTPHeaderField: "x-stainless-retry-count")
            request.setValue("node", forHTTPHeaderField: "x-stainless-runtime")
            request.setValue("v24.3.0", forHTTPHeaderField: "x-stainless-runtime-version")
            request.setValue("600", forHTTPHeaderField: "x-stainless-timeout")
        } else if usesAnthropicOneMillionContext {
            request.setValue(anthropicOneMillionContextBetaHeader, forHTTPHeaderField: "anthropic-beta")
        }

        for header in CustomHeaderSecurity.requestHeaders(from: customHeaders) {
            let headerName = header.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if (usesAnthropicClaudeCodeImpersonation && isAnthropicClaudeCodeManagedHeader(headerName))
                || (usesAnthropicOneMillionContext && headerName == "anthropic-beta") {
                continue
            }
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        return request
    }

    static func requestURL(
        from urlString: String,
        apiFormat: AIAPIFormat,
        model: String,
        apiKey: String,
        isStreaming: Bool,
        anthropicClaudeCodeImpersonationEnabled: Bool = false
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

        let usesAnthropicOneMillionContext = anthropicClaudeCodeImpersonationEnabled
            || AIRequestBodyBuilder.anthropicModelSelection(from: model).usesOneMillionContext
        if apiFormat == .anthropicMessages, usesAnthropicOneMillionContext {
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "beta" }
            queryItems.append(URLQueryItem(name: "beta", value: "true"))
            components.queryItems = queryItems
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

    private static func isAnthropicClaudeCodeManagedHeader(_ name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return anthropicClaudeCodeManagedHeaders.contains(normalizedName)
            || normalizedName.hasPrefix("x-stainless-")
    }
}
