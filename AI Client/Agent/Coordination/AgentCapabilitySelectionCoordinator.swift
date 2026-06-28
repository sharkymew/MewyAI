import Foundation

enum AgentCapabilitySelectionCoordinator {
    static func reload(
        skills: inout [AgentSkill],
        mcpServers: inout [MCPServerConfiguration],
        selection: inout AgentCapabilitySelection
    ) {
        skills = AgentCapabilityStore.loadSkills()
        mcpServers = AgentCapabilityStore.loadMCPServers()
        selection.keepAvailable(skills: skills, mcpServers: mcpServers)
    }

    static func toggleSkill(
        _ id: UUID,
        selection: inout AgentCapabilitySelection
    ) {
        selection.toggleSkill(id)
    }

    static func toggleMCPServer(
        _ id: UUID,
        selection: inout AgentCapabilitySelection
    ) {
        selection.toggleMCPServer(id)
    }

    static func deactivate(
        _ capsule: ActiveAgentCapsule,
        selection: inout AgentCapabilitySelection
    ) {
        selection.deactivate(capsule)
    }

    static func activeToolDefinitions(
        selection: AgentCapabilitySelection,
        mcpServers: [MCPServerConfiguration]
    ) -> [AgentToolDefinition] {
        AgentToolExecutionCoordinator.activeToolDefinitions(
            for: selection.activeMCPServers(in: mcpServers)
        )
    }

    static func applyRefreshedTools(
        _ tools: [MCPToolDefinition],
        for server: MCPServerConfiguration,
        to mcpServers: inout [MCPServerConfiguration]
    ) {
        guard AgentToolExecutionCoordinator.applyRefreshedTools(
            tools,
            for: server,
            to: &mcpServers
        ) else {
            return
        }
        AgentCapabilityStore.saveMCPServers(mcpServers)
    }
}
