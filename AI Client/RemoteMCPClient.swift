import Foundation

struct RemoteMCPClient {
    private let configuration: MCPServerConfiguration
    private let session: URLSession

    init(configuration: MCPServerConfiguration, session: URLSession = RemoteMCPClient.makeSecureSession()) {
        self.configuration = configuration
        self.session = session
    }

    func listTools() async throws -> [MCPToolDefinition] {
        let initializeResponse = try await send(method: "initialize", params: .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("AI Client"),
                "version": .string("1.0")
            ])
        ]))
        let sessionID = initializeResponse.sessionID
        _ = try? await send(method: "notifications/initialized", params: .object([:]), id: nil, sessionID: sessionID)
        let toolsResponse = try await send(method: "tools/list", params: .object([:]), sessionID: sessionID)
        guard case .object(let result) = toolsResponse.result,
              case .array(let toolsValue)? = result["tools"] else {
            return []
        }

        let toolsData = try JSONEncoder().encode(JSONValue.array(toolsValue))
        return (try? JSONDecoder().decode([MCPToolDefinition].self, from: toolsData)) ?? []
    }

    func callTool(name: String, arguments: JSONValue) async throws -> RemoteMCPToolCallResult {
        let initializeResponse = try await send(method: "initialize", params: .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("AI Client"),
                "version": .string("1.0")
            ])
        ]))
        let sessionID = initializeResponse.sessionID
        _ = try? await send(method: "notifications/initialized", params: .object([:]), id: nil, sessionID: sessionID)
        let response = try await send(method: "tools/call", params: .object([
            "name": .string(name),
            "arguments": arguments
        ]), sessionID: sessionID)

        if let error = response.error {
            return RemoteMCPToolCallResult(content: sanitizedResponseBody(error.message), isError: true)
        }

        return Self.toolCallResult(from: response.result)
    }

    private func send(
        method: String,
        params: JSONValue,
        id: Int? = Int.random(in: 1...Int.max),
        sessionID: String? = nil
    ) async throws -> RemoteMCPResponse {
        guard let url = requestURL(),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            throw RemoteMCPError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        let token = configuration.authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty && configuration.kind != .tavily {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(RemoteMCPRequest(
            id: id,
            method: method,
            params: params
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteMCPError.invalidResponse
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RemoteMCPError.requestFailed(sanitizedResponseBody(bodyText))
        }

        guard let responseData = Self.jsonData(from: data) else {
            throw RemoteMCPError.invalidResponse
        }

        var decoded = try JSONDecoder().decode(RemoteMCPResponse.self, from: responseData)
        decoded.sessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")
            ?? httpResponse.value(forHTTPHeaderField: "mcp-session-id")
        return decoded
    }

    private func requestURL() -> URL? {
        let rawURL = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL) else { return nil }

        let token = configuration.authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.kind == .tavily, !token.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "tavilyApiKey" }) {
            queryItems.append(URLQueryItem(name: "tavilyApiKey", value: token))
            components.queryItems = queryItems
        }
        return components.url ?? url
    }

    private static func jsonData(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return data
        }

        let dataLines = text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("data:") }
            .map { line in
                line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0 != "[DONE]" }
        return dataLines.last?.data(using: .utf8)
    }

    private static func toolContentText(from result: JSONValue?) -> String {
        guard let result else { return "" }
        if case .object(let object) = result {
            if case .bool(true)? = object["isError"],
               case .array(let content)? = object["content"] {
                return contentText(from: content, fallback: result.compactJSONString)
            }
            if case .array(let content)? = object["content"] {
                return contentText(from: content, fallback: result.compactJSONString)
            }
            if let structured = object["structuredContent"] {
                return structured.compactJSONString
            }
        }
        return result.compactJSONString
    }

    private static func makeSecureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private static func toolCallResult(from result: JSONValue?) -> RemoteMCPToolCallResult {
        guard let result else {
            return RemoteMCPToolCallResult(content: "", isError: false)
        }

        let isError: Bool
        if case .object(let object) = result,
           case .bool(let resultIsError)? = object["isError"] {
            isError = resultIsError
        } else {
            isError = false
        }

        return RemoteMCPToolCallResult(content: toolContentText(from: result), isError: isError)
    }

    private static func contentText(from content: [JSONValue], fallback: String) -> String {
        let text = content.compactMap { item -> String? in
            guard case .object(let object) = item else { return nil }
            if case .string("text")? = object["type"],
               case .string(let text)? = object["text"] {
                return text
            }
            return item.compactJSONString
        }
        .joined(separator: "\n\n")
        return text.isEmpty ? fallback : text
    }

    private func sanitizedResponseBody(_ text: String) -> String {
        let token = configuration.authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
        if !token.isEmpty {
            output = output.replacingOccurrences(of: token, with: "[redacted]")
        }
        return output
    }
}

private struct RemoteMCPRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int?
    let method: String
    let params: JSONValue

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
        if let id {
            try container.encode(id, forKey: .id)
        }
    }
}

struct RemoteMCPResponse: Decodable {
    let result: JSONValue?
    let error: RemoteMCPResponseError?
    var sessionID: String?
}

struct RemoteMCPResponseError: Decodable {
    let message: String
}

struct RemoteMCPToolCallResult {
    let content: String
    let isError: Bool
}

enum RemoteMCPError: LocalizedError {
    case insecureURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .insecureURL:
            return AppLocalizations.string("mcp.error.insecureURL", defaultValue: "MCP only supports HTTPS URLs.")
        case .invalidResponse:
            return AppLocalizations.string("mcp.error.invalidResponse", defaultValue: "The MCP response could not be parsed.")
        case .requestFailed(let message):
            return message.isEmpty
                ? AppLocalizations.string("mcp.error.requestFailed", defaultValue: "MCP request failed.")
                : AppLocalizations.format(
                    "mcp.error.requestFailedWithMessage",
                    defaultValue: "MCP request failed: %@",
                    arguments: [message]
                )
        }
    }
}
