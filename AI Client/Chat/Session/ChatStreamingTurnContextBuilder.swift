import Foundation

struct ChatStreamingTurnContext: Equatable {
    let configuration: AIConfiguration
    let hasActiveMCPServers: Bool
    let mcpTools: [AgentToolDefinition]
    let recallTools: [AgentToolDefinition]
    let knowledgeTools: [AgentToolDefinition]
    let systemPromptAppendix: String
}

enum ChatStreamingTurnContextBuilder {
    typealias MCPToolBuilder = ([MCPServerConfiguration]) -> [AgentToolDefinition]
    typealias MemoryEntryLoader = () -> [ChatMemoryEntry]

    static func make(
        configuration: AIConfiguration,
        activeSkills: [AgentSkill],
        activeMCPServers: [MCPServerConfiguration],
        activeKnowledgeBases: [KnowledgeBase] = [],
        storedConversations: [AIConversation],
        selectedConversationID: UUID?,
        privateConversationID: UUID?,
        isHistoryRecallEnabled: Bool,
        isGlobalMemoryEnabled: Bool,
        buildMCPTools: MCPToolBuilder = {
            AgentToolExecutionCoordinator.activeToolDefinitions(for: $0)
        },
        loadMemoryEntries: MemoryEntryLoader = {
            ChatMemoryStore.loadEntries()
        }
    ) -> ChatStreamingTurnContext {
        let hasActiveMCPServers = !activeMCPServers.isEmpty
        let mcpTools = hasActiveMCPServers ? buildMCPTools(activeMCPServers) : []
        let isPrivateConversationSelected = privateConversationID.map { $0 == selectedConversationID } ?? false

        let usesHistoryRecall = isHistoryRecallEnabled
            && !isPrivateConversationSelected
            && configuration.selectedModelSupportsTools
            && configuration.apiFormat != .vertexAIExpress
        let recallTools = usesHistoryRecall
            ? ConversationRecallTool.definitions(excludingFunctionNames: Set(mcpTools.map(\.functionName)))
            : []
        let usedFunctionNames = Set((mcpTools + recallTools).map(\.functionName))
        let knowledgeTools = !activeKnowledgeBases.isEmpty
                && configuration.selectedModelSupportsTools
                && configuration.apiFormat != .vertexAIExpress
            ? KnowledgeBaseTool.definitions(excludingFunctionNames: usedFunctionNames)
            : []

        var recallExcludedConversationIDs = Set<UUID>()
        if let selectedConversationID {
            recallExcludedConversationIDs.insert(selectedConversationID)
        }
        if let privateConversationID {
            recallExcludedConversationIDs.insert(privateConversationID)
        }
        let recallPromptAppendix = recallTools.isEmpty
            ? ""
            : ConversationRecallTool.promptAppendix(
                conversations: storedConversations,
                excludedConversationIDs: recallExcludedConversationIDs
            )

        let usesGlobalMemory = isGlobalMemoryEnabled && !isPrivateConversationSelected
        let memoryPromptAppendix = usesGlobalMemory
            ? ChatMemoryStore.promptAppendix(for: loadMemoryEntries())
            : ""

        return ChatStreamingTurnContext(
            configuration: configuration,
            hasActiveMCPServers: hasActiveMCPServers,
            mcpTools: mcpTools,
            recallTools: recallTools,
            knowledgeTools: knowledgeTools,
            systemPromptAppendix: AgentTooling.promptAppendix(for: activeSkills)
                + memoryPromptAppendix
                + recallPromptAppendix
                + KnowledgeBaseTool.promptAppendix(for: activeKnowledgeBases)
        )
    }
}
