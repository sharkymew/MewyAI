import Foundation

enum AgentToolExecutionCoordinator {
    typealias ToolApprovalHandler = (_ toolName: String, _ arguments: String) async -> Bool
    typealias ConversationLoader = () -> [AIConversation]
    typealias KnowledgeBaseLoader = () -> [KnowledgeBase]
    typealias ConfigurationLoader = () -> [AIConfiguration]
    typealias RefreshedToolsSaver = (_ tools: [MCPToolDefinition], _ server: MCPServerConfiguration) -> Void
    typealias ToolCaller = (_ server: MCPServerConfiguration, _ toolName: String, _ arguments: JSONValue) async throws -> RemoteMCPToolCallResult
    typealias ToolLister = (_ server: MCPServerConfiguration) async throws -> [MCPToolDefinition]

    static func activeToolDefinitions(for servers: [MCPServerConfiguration]) -> [AgentToolDefinition] {
        var definitions = [AgentToolDefinition]()
        var usedFunctionNames = Set<String>()

        for server in servers {
            for tool in effectiveMCPTools(for: server) {
                let definition = AgentToolDefinition.make(server: server, tool: tool)
                guard usedFunctionNames.insert(definition.functionName).inserted else { continue }
                definitions.append(definition)
            }
        }

        return definitions
    }

    static func effectiveMCPTools(for server: MCPServerConfiguration) -> [MCPToolDefinition] {
        var tools = server.cachedTools.map { tool in
            var normalizedTool = tool
            if server.kind == .tavily {
                normalizedTool.name = AgentCapabilityStore.normalizedTavilyToolName(tool.name)
            }
            return normalizedTool
        }
        if server.kind == .tavily {
            for defaultTool in MCPServerConfiguration.tavilyDefault().cachedTools
            where !tools.contains(where: { $0.name == defaultTool.name }) {
                tools.append(defaultTool)
            }
        }

        let allowedToolNames: [String]
        if server.kind == .tavily {
            let normalizedAllowedToolNames = server.allowedToolNames.map(AgentCapabilityStore.normalizedTavilyToolName)
            allowedToolNames = normalizedAllowedToolNames.isEmpty
                ? MCPServerConfiguration.tavilyDefault().allowedToolNames
                : normalizedAllowedToolNames
        } else {
            allowedToolNames = server.allowedToolNames
        }
        let allowedNames = Set(allowedToolNames)
        let filteredTools = tools.filter { allowedNames.isEmpty || allowedNames.contains($0.name) }

        if filteredTools.isEmpty && server.kind == .tavily {
            return MCPServerConfiguration.tavilyDefault().cachedTools
        }
        return filteredTools
    }

    static func execute(
        _ request: AgentToolCallRequest,
        in conversationID: UUID?,
        privateConversationID: UUID?,
        mcpServers: [MCPServerConfiguration],
        conversations: ConversationLoader,
        knowledgeBases: KnowledgeBaseLoader = { [] },
        configurations: ConfigurationLoader = { [] },
        knowledgeBaseRetrievalService: KnowledgeBaseRetrievalService = KnowledgeBaseRetrievalService(),
        requestApproval: ToolApprovalHandler,
        saveRefreshedTools: RefreshedToolsSaver,
        callTool: @escaping ToolCaller = { server, toolName, arguments in
            try await RemoteMCPClient(configuration: server).callTool(
                name: toolName,
                arguments: arguments
            )
        },
        listTools: @escaping ToolLister = { server in
            try await RemoteMCPClient(configuration: server).listTools()
        }
    ) async -> AgentToolCallResult {
        if ConversationRecallTool.isRecallTool(request.tool) {
            var excludedConversationIDs = Set<UUID>()
            if let conversationID {
                excludedConversationIDs.insert(conversationID)
            }
            if let privateConversationID {
                excludedConversationIDs.insert(privateConversationID)
            }
            return ConversationRecallTool.execute(
                functionName: request.functionName,
                argumentsJSON: request.argumentsJSON,
                conversations: conversations(),
                excludedConversationIDs: excludedConversationIDs
            )
        }

        if KnowledgeBaseTool.isKnowledgeBaseTool(request.tool) {
            return await KnowledgeBaseTool.execute(
                functionName: request.functionName,
                argumentsJSON: request.argumentsJSON,
                knowledgeBases: knowledgeBases(),
                configurations: configurations(),
                retrievalService: knowledgeBaseRetrievalService
            )
        }

        if request.tool.requiresApproval {
            let isAllowed = await requestApproval(
                request.tool.displayName,
                request.argumentsJSON
            )
            guard isAllowed else {
                return AgentToolCallResult(
                    content: AppLocalizations.string(
                        "agentTool.result.userDenied",
                        defaultValue: "The user denied this tool call."
                    ),
                    isError: true
                )
            }
        }

        let server = currentMCPServerConfiguration(for: request.tool, in: mcpServers)
        let mcpToolName = normalizedToolName(request.tool.mcpToolName, for: server.kind)

        do {
            let result = try await callTool(server, mcpToolName, jsonValue(from: request.argumentsJSON))
            if result.isError,
               shouldRefreshTools(after: result.content),
               let retryResult = await retryAfterRefreshingTools(
                request,
                server: server,
                failedToolName: mcpToolName,
                saveRefreshedTools: saveRefreshedTools,
                callTool: callTool,
                listTools: listTools
               ) {
                return retryResult
            }
            return AgentToolCallResult(content: result.content, isError: result.isError)
        } catch {
            return AgentToolCallResult(content: error.localizedDescription, isError: true)
        }
    }

    static func currentMCPServerConfiguration(
        for tool: AgentToolDefinition,
        in servers: [MCPServerConfiguration]
    ) -> MCPServerConfiguration {
        if var server = servers.first(where: { $0.id == tool.mcpServerID }) {
            if server.authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                server.authorizationToken = tool.authorizationToken
            }
            return server
        }

        return MCPServerConfiguration(
            id: tool.mcpServerID,
            name: tool.mcpServerName,
            serverURL: tool.mcpServerURL,
            kind: tool.mcpServerID == MCPServerConfiguration.tavilyID ? .tavily : .custom,
            requiresApproval: tool.requiresApproval,
            authorizationToken: tool.authorizationToken
        )
    }

    static func shouldRefreshTools(after errorContent: String) -> Bool {
        let lowercasedContent = errorContent.lowercased()
        return lowercasedContent.contains("unknown tool")
            || lowercasedContent.contains("tool not found")
            || lowercasedContent.contains("not found")
    }

    static func replacementToolName(
        for failedToolName: String,
        in tools: [MCPToolDefinition],
        serverKind: MCPServerKind
    ) -> String? {
        let normalizedFailedToolName = normalizedToolName(failedToolName, for: serverKind)
        if tools.contains(where: { $0.name == normalizedFailedToolName }) {
            return normalizedFailedToolName
        }

        let underscoreName = normalizedFailedToolName.replacingOccurrences(of: "-", with: "_")
        if tools.contains(where: { $0.name == underscoreName }) {
            return underscoreName
        }

        if serverKind == .tavily,
           normalizedFailedToolName.contains("search"),
           tools.contains(where: { $0.name == MCPServerConfiguration.tavilySearchToolName }) {
            return MCPServerConfiguration.tavilySearchToolName
        }

        return nil
    }

    @discardableResult
    static func applyRefreshedTools(
        _ tools: [MCPToolDefinition],
        for server: MCPServerConfiguration,
        to servers: inout [MCPServerConfiguration],
        date: Date = Date()
    ) -> Bool {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return false }

        servers[index].cachedTools = tools
        if server.kind == .tavily {
            let toolNames = Set(tools.map(\.name))
            let normalizedAllowedToolNames = servers[index].allowedToolNames
                .map(AgentCapabilityStore.normalizedTavilyToolName)
                .filter { toolNames.contains($0) }
            servers[index].allowedToolNames = normalizedAllowedToolNames.isEmpty
                ? MCPServerConfiguration.tavilyDefault().allowedToolNames
                : normalizedAllowedToolNames
        }
        servers[index].updatedAt = date
        return true
    }

    static func jsonValue(from json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    private static func retryAfterRefreshingTools(
        _ request: AgentToolCallRequest,
        server: MCPServerConfiguration,
        failedToolName: String,
        saveRefreshedTools: RefreshedToolsSaver,
        callTool: @escaping ToolCaller,
        listTools: @escaping ToolLister
    ) async -> AgentToolCallResult? {
        do {
            let refreshedTools = try await listTools(server)
            guard !refreshedTools.isEmpty else { return nil }

            let normalizedTools = refreshedTools.map { tool in
                var normalizedTool = tool
                if server.kind == .tavily {
                    normalizedTool.name = AgentCapabilityStore.normalizedTavilyToolName(tool.name)
                }
                return normalizedTool
            }
            saveRefreshedTools(normalizedTools, server)

            guard let replacementTool = replacementToolName(
                for: failedToolName,
                in: normalizedTools,
                serverKind: server.kind
            ) else {
                return nil
            }

            let retryResult = try await callTool(
                server,
                replacementTool,
                jsonValue(from: request.argumentsJSON)
            )
            return AgentToolCallResult(content: retryResult.content, isError: retryResult.isError)
        } catch {
            return nil
        }
    }

    private static func normalizedToolName(_ name: String, for serverKind: MCPServerKind) -> String {
        serverKind == .tavily
            ? AgentCapabilityStore.normalizedTavilyToolName(name)
            : name
    }
}
