import XCTest
@testable import MewyAI

@MainActor
final class AgentToolExecutionCoordinatorTests: XCTestCase {
    func testActiveToolDefinitionsNormalizesAndDeduplicatesTavilyTools() {
        let server = MCPServerConfiguration(
            name: "Tavily Search",
            serverURL: "https://mcp.tavily.com/mcp/",
            kind: .tavily,
            allowedToolNames: ["tavily-search"],
            requiresApproval: true,
            cachedTools: [
                MCPToolDefinition(name: "tavily-search"),
                MCPToolDefinition(name: "tavily_search")
            ]
        )

        let definitions = AgentToolExecutionCoordinator.activeToolDefinitions(for: [server])

        XCTAssertEqual(definitions.map(\.mcpToolName), ["tavily_search"])
        XCTAssertEqual(definitions.map(\.functionName), ["tavily_search_tavily_search"])
    }

    func testEffectiveMCPToolsFallsBackToTavilyDefaultWhenAllowedNamesFilterEverything() {
        let server = MCPServerConfiguration(
            name: "Tavily Search",
            serverURL: "https://mcp.tavily.com/mcp/",
            kind: .tavily,
            allowedToolNames: ["missing_tool"],
            cachedTools: [MCPToolDefinition(name: "tavily_extract")]
        )

        let tools = AgentToolExecutionCoordinator.effectiveMCPTools(for: server)

        XCTAssertEqual(tools.map(\.name), [MCPServerConfiguration.tavilySearchToolName])
    }

    func testCurrentServerConfigurationUsesStoredServerAndFallsBackToToolToken() {
        let serverID = UUID()
        let tool = AgentToolDefinition(
            functionName: "server_tool",
            displayName: "Server Tool",
            description: "Tool",
            inputSchema: .object([:]),
            mcpServerID: serverID,
            mcpServerName: "Server",
            mcpServerURL: "https://example.com/mcp",
            mcpToolName: "tool",
            requiresApproval: true,
            authorizationToken: "tool-token"
        )
        let server = MCPServerConfiguration(
            id: serverID,
            name: "Stored Server",
            serverURL: "https://stored.example.com/mcp",
            authorizationToken: ""
        )

        let resolved = AgentToolExecutionCoordinator.currentMCPServerConfiguration(
            for: tool,
            in: [server]
        )

        XCTAssertEqual(resolved.name, "Stored Server")
        XCTAssertEqual(resolved.serverURL, "https://stored.example.com/mcp")
        XCTAssertEqual(resolved.authorizationToken, "tool-token")
    }

    func testReplacementToolNameHandlesTavilyNormalizationAndSearchFallback() {
        let tools = [
            MCPToolDefinition(name: MCPServerConfiguration.tavilySearchToolName)
        ]

        XCTAssertEqual(
            AgentToolExecutionCoordinator.replacementToolName(
                for: "tavily-search",
                in: tools,
                serverKind: .tavily
            ),
            MCPServerConfiguration.tavilySearchToolName
        )
        XCTAssertEqual(
            AgentToolExecutionCoordinator.replacementToolName(
                for: "web-search",
                in: tools,
                serverKind: .tavily
            ),
            MCPServerConfiguration.tavilySearchToolName
        )
        XCTAssertNil(AgentToolExecutionCoordinator.replacementToolName(
            for: "missing",
            in: tools,
            serverKind: .custom
        ))
    }

    func testJsonValueFallsBackToEmptyObjectForInvalidJSON() {
        XCTAssertEqual(
            AgentToolExecutionCoordinator.jsonValue(from: #"{"query":"swift"}"#),
            .object(["query": .string("swift")])
        )
        XCTAssertEqual(
            AgentToolExecutionCoordinator.jsonValue(from: "not json"),
            .object([:])
        )
    }

    func testApplyRefreshedToolsNormalizesTavilyAllowedNames() {
        let serverID = MCPServerConfiguration.tavilyID
        let originalDate = Date(timeIntervalSince1970: 10)
        let refreshedDate = Date(timeIntervalSince1970: 20)
        var servers = [
            MCPServerConfiguration(
                id: serverID,
                name: "Tavily Search",
                serverURL: "https://mcp.tavily.com/mcp/",
                kind: .tavily,
                allowedToolNames: ["tavily-search", "missing"],
                cachedTools: [],
                updatedAt: originalDate
            )
        ]

        let didApply = AgentToolExecutionCoordinator.applyRefreshedTools(
            [MCPToolDefinition(name: MCPServerConfiguration.tavilySearchToolName)],
            for: servers[0],
            to: &servers,
            date: refreshedDate
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(servers[0].cachedTools.map(\.name), [MCPServerConfiguration.tavilySearchToolName])
        XCTAssertEqual(servers[0].allowedToolNames, [MCPServerConfiguration.tavilySearchToolName])
        XCTAssertEqual(servers[0].updatedAt, refreshedDate)
    }

    func testExecuteReturnsDeniedResultWithoutCallingRemoteTool() async {
        let server = MCPServerConfiguration(
            name: "Server",
            serverURL: "https://example.com/mcp",
            requiresApproval: true,
            cachedTools: [MCPToolDefinition(name: "tool")]
        )
        let tool = AgentToolDefinition.make(server: server, tool: server.cachedTools[0])
        let request = AgentToolCallRequest(
            id: "call-1",
            functionName: tool.functionName,
            argumentsJSON: #"{"value":1}"#,
            tool: tool
        )
        var didCallRemoteTool = false

        let result = await AgentToolExecutionCoordinator.execute(
            request,
            in: UUID(),
            privateConversationID: nil,
            mcpServers: [server],
            conversations: { [] },
            requestApproval: { _, _ in false },
            saveRefreshedTools: { _, _ in },
            callTool: { _, _, _ in
                didCallRemoteTool = true
                return RemoteMCPToolCallResult(content: "unexpected", isError: false)
            },
            listTools: { _ in
                didCallRemoteTool = true
                return []
            }
        )

        XCTAssertTrue(result.isError)
        XCTAssertFalse(didCallRemoteTool)
    }

    func testExecuteRefreshesToolsAndRetriesMatchingReplacement() async {
        let server = MCPServerConfiguration(
            name: "Tavily Search",
            serverURL: "https://mcp.tavily.com/mcp/",
            kind: .tavily,
            allowedToolNames: ["tavily-search"],
            requiresApproval: false,
            cachedTools: [MCPToolDefinition(name: "tavily-search")]
        )
        let tool = AgentToolDefinition.make(server: server, tool: server.cachedTools[0])
        let request = AgentToolCallRequest(
            id: "call-1",
            functionName: tool.functionName,
            argumentsJSON: #"{"query":"swift"}"#,
            tool: tool
        )
        var calledToolNames: [String] = []
        var savedTools: [MCPToolDefinition] = []

        let result = await AgentToolExecutionCoordinator.execute(
            request,
            in: UUID(),
            privateConversationID: nil,
            mcpServers: [server],
            conversations: { [] },
            requestApproval: { _, _ in true },
            saveRefreshedTools: { tools, _ in
                savedTools = tools
            },
            callTool: { _, toolName, _ in
                calledToolNames.append(toolName)
                if calledToolNames.count == 1 {
                    return RemoteMCPToolCallResult(content: "unknown tool", isError: true)
                }
                return RemoteMCPToolCallResult(content: "ok", isError: false)
            },
            listTools: { _ in
                [MCPToolDefinition(name: "tavily-search")]
            }
        )

        XCTAssertEqual(result, AgentToolCallResult(content: "ok", isError: false))
        XCTAssertEqual(calledToolNames, [
            MCPServerConfiguration.tavilySearchToolName,
            MCPServerConfiguration.tavilySearchToolName
        ])
        XCTAssertEqual(savedTools.map(\.name), [MCPServerConfiguration.tavilySearchToolName])
    }
}
