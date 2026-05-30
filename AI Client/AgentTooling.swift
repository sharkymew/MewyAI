import Foundation

struct AgentToolDefinition: Identifiable, Equatable {
    var id: String { functionName }
    var functionName: String
    var displayName: String
    var description: String
    var inputSchema: JSONValue
    var mcpServerID: UUID
    var mcpServerName: String
    var mcpServerURL: String
    var mcpToolName: String
    var requiresApproval: Bool
    var authorizationToken: String

    static func make(server: MCPServerConfiguration, tool: MCPToolDefinition) -> AgentToolDefinition {
        let functionName = sanitizedFunctionName(serverName: server.name, toolName: tool.name)
        return AgentToolDefinition(
            functionName: functionName,
            displayName: "\(server.name) · \(tool.name)",
            description: tool.description.isEmpty ? "Call \(tool.name) on \(server.name)." : tool.description,
            inputSchema: tool.inputSchema,
            mcpServerID: server.id,
            mcpServerName: server.name,
            mcpServerURL: server.serverURL,
            mcpToolName: tool.name,
            requiresApproval: server.requiresApproval,
            authorizationToken: server.authorizationToken
        )
    }

    private static func sanitizedFunctionName(serverName: String, toolName: String) -> String {
        let rawName = "\(serverName)_\(toolName)".lowercased()
        var output = ""
        var previousWasSeparator = false
        for scalar in rawName.unicodeScalars {
            let isAllowed = (48...57).contains(scalar.value)
                || (97...122).contains(scalar.value)
            if isAllowed {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("_")
                previousWasSeparator = true
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String((trimmed.isEmpty ? "mcp_tool" : trimmed).prefix(64))
    }
}

struct AgentToolCallRequest: Equatable {
    var id: String
    var functionName: String
    var argumentsJSON: String
    var tool: AgentToolDefinition
}

struct AgentToolCallResult: Equatable {
    var content: String
    var isError: Bool
}

struct AgentToolRunResult {
    var content: String
    var reasoningContent: String
    var toolExchanges: [ChatToolExchange]
}

enum AgentTooling {
    static let maxToolRounds = 4
    static let maxToolCalls = 8
    static let maxToolResultCharacters = 20_000

    static func promptAppendix(for skills: [AgentSkill]) -> String {
        guard !skills.isEmpty else { return "" }

        let sections = skills.map { skill in
            """
            <skill name="\(skill.name)">
            \(skill.content)
            </skill>
            """
        }

        return """

        下面是用户在当前对话中持续启用的 AI Client Agent Skills。它们是文本指令包，不代表本机可以执行脚本、Python、shell、子进程或未声明工具。仅在与用户请求相关时遵循。

        \(sections.joined(separator: "\n\n"))
        """
    }
}
