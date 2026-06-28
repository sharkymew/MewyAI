import XCTest
@testable import MewyAI

@MainActor
final class ChatStreamingTurnContextBuilderTests: XCTestCase {
    func testBuildIncludesMCPRecallSkillsAndMemoryForPersistentConversation() {
        let selectedConversationID = UUID()
        let privateConversationID = UUID()
        let otherConversationID = UUID()
        let server = mcpServer()
        let mcpTool = tool(functionName: "docs_search")
        let memoryEntry = ChatMemoryEntry(content: "remembered fact")

        let result = ChatStreamingTurnContextBuilder.make(
            configuration: configuration(supportsTools: true),
            activeSkills: [AgentSkill(name: "Writer", description: "", content: "Use crisp prose.")],
            activeMCPServers: [server],
            storedConversations: [
                conversation(id: selectedConversationID, title: "Current", updatedAtOffset: 30),
                conversation(id: privateConversationID, title: "Private", updatedAtOffset: 20),
                conversation(id: otherConversationID, title: "Research", updatedAtOffset: 10)
            ],
            selectedConversationID: selectedConversationID,
            privateConversationID: privateConversationID,
            isHistoryRecallEnabled: true,
            isGlobalMemoryEnabled: true,
            buildMCPTools: { servers in
                XCTAssertEqual(servers, [server])
                return [mcpTool]
            },
            loadMemoryEntries: {
                [memoryEntry]
            }
        )

        XCTAssertTrue(result.hasActiveMCPServers)
        XCTAssertEqual(result.mcpTools, [mcpTool])
        XCTAssertEqual(result.recallTools.map(\.functionName), [
            ConversationRecallTool.searchFunctionName,
            ConversationRecallTool.readFunctionName
        ])
        XCTAssertTrue(result.systemPromptAppendix.contains("<skill name=\"Writer\">"))
        XCTAssertTrue(result.systemPromptAppendix.contains("Use crisp prose."))
        XCTAssertTrue(result.systemPromptAppendix.contains("<user_memory>"))
        XCTAssertTrue(result.systemPromptAppendix.contains("remembered fact"))
        XCTAssertTrue(result.systemPromptAppendix.contains("<chat_history_recall>"))
        XCTAssertTrue(result.systemPromptAppendix.contains("Research"))
        XCTAssertFalse(result.systemPromptAppendix.contains("Current"))
        XCTAssertFalse(result.systemPromptAppendix.contains("Private"))
    }

    func testPrivateConversationDisablesRecallAndMemoryWithoutDisablingMCPTools() {
        let privateConversationID = UUID()
        let server = mcpServer()
        let mcpTool = tool(functionName: "docs_search")
        var memoryLoadCount = 0

        let result = ChatStreamingTurnContextBuilder.make(
            configuration: configuration(supportsTools: true),
            activeSkills: [],
            activeMCPServers: [server],
            storedConversations: [
                conversation(id: UUID(), title: "Research")
            ],
            selectedConversationID: privateConversationID,
            privateConversationID: privateConversationID,
            isHistoryRecallEnabled: true,
            isGlobalMemoryEnabled: true,
            buildMCPTools: { _ in [mcpTool] },
            loadMemoryEntries: {
                memoryLoadCount += 1
                return [ChatMemoryEntry(content: "should not load")]
            }
        )

        XCTAssertTrue(result.hasActiveMCPServers)
        XCTAssertEqual(result.mcpTools, [mcpTool])
        XCTAssertTrue(result.recallTools.isEmpty)
        XCTAssertEqual(memoryLoadCount, 0)
        XCTAssertFalse(result.systemPromptAppendix.contains("<user_memory>"))
        XCTAssertFalse(result.systemPromptAppendix.contains("<chat_history_recall>"))
    }

    func testRecallToolNamesExcludeMCPConflicts() {
        let conflictingTool = tool(functionName: ConversationRecallTool.searchFunctionName)

        let result = ChatStreamingTurnContextBuilder.make(
            configuration: configuration(supportsTools: true),
            activeSkills: [],
            activeMCPServers: [mcpServer()],
            storedConversations: [
                conversation(id: UUID(), title: "Research")
            ],
            selectedConversationID: UUID(),
            privateConversationID: nil,
            isHistoryRecallEnabled: true,
            isGlobalMemoryEnabled: false,
            buildMCPTools: { _ in [conflictingTool] },
            loadMemoryEntries: {
                XCTFail("Memory should not load when global memory is disabled")
                return []
            }
        )

        XCTAssertEqual(result.mcpTools, [conflictingTool])
        XCTAssertEqual(result.recallTools.map(\.functionName), [
            ConversationRecallTool.readFunctionName
        ])
        XCTAssertTrue(result.systemPromptAppendix.contains("<chat_history_recall>"))
    }

    func testHistoryRecallRequiresToolCapableNonVertexModel() {
        let unsupportedModel = ChatStreamingTurnContextBuilder.make(
            configuration: configuration(supportsTools: false),
            activeSkills: [],
            activeMCPServers: [],
            storedConversations: [
                conversation(id: UUID(), title: "Research")
            ],
            selectedConversationID: UUID(),
            privateConversationID: nil,
            isHistoryRecallEnabled: true,
            isGlobalMemoryEnabled: false
        )

        let vertexModel = ChatStreamingTurnContextBuilder.make(
            configuration: configuration(supportsTools: true, apiFormat: .vertexAIExpress),
            activeSkills: [],
            activeMCPServers: [],
            storedConversations: [
                conversation(id: UUID(), title: "Research")
            ],
            selectedConversationID: UUID(),
            privateConversationID: nil,
            isHistoryRecallEnabled: true,
            isGlobalMemoryEnabled: false
        )

        XCTAssertTrue(unsupportedModel.recallTools.isEmpty)
        XCTAssertFalse(unsupportedModel.systemPromptAppendix.contains("<chat_history_recall>"))
        XCTAssertTrue(vertexModel.recallTools.isEmpty)
        XCTAssertFalse(vertexModel.systemPromptAppendix.contains("<chat_history_recall>"))
    }

    private func configuration(
        supportsTools: Bool,
        apiFormat: AIAPIFormat = .openAIChatCompletions
    ) -> AIConfiguration {
        AIConfiguration(
            baseURL: "https://api.example.com",
            endpoint: "chat/completions",
            apiFormat: apiFormat,
            models: [
                AIModelConfiguration(name: "model-a", supportsTools: supportsTools)
            ],
            selectedModel: "model-a"
        )
    }

    private func conversation(
        id: UUID,
        title: String,
        updatedAtOffset: TimeInterval = 0
    ) -> AIConversation {
        AIConversation(
            id: id,
            title: title,
            messages: [
                ChatMessage(role: "user", content: "hello")
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + updatedAtOffset)
        )
    }

    private func mcpServer() -> MCPServerConfiguration {
        MCPServerConfiguration(
            name: "Docs",
            serverURL: "https://example.com/mcp"
        )
    }

    private func tool(functionName: String) -> AgentToolDefinition {
        AgentToolDefinition(
            functionName: functionName,
            displayName: functionName,
            description: "Tool",
            inputSchema: .object([:]),
            mcpServerID: UUID(),
            mcpServerName: "Docs",
            mcpServerURL: "https://example.com/mcp",
            mcpToolName: functionName,
            requiresApproval: true,
            authorizationToken: ""
        )
    }
}
