import Foundation

struct AgentCapabilitySelection: Equatable {
    var activeSkillIDs: Set<UUID>
    var activeMCPServerIDs: Set<UUID>

    init(
        activeSkillIDs: Set<UUID> = [],
        activeMCPServerIDs: Set<UUID> = []
    ) {
        self.activeSkillIDs = activeSkillIDs
        self.activeMCPServerIDs = activeMCPServerIDs
    }

    init(
        skillIDs: [UUID],
        mcpServerIDs: [UUID]
    ) {
        self.init(
            activeSkillIDs: Set(skillIDs),
            activeMCPServerIDs: Set(mcpServerIDs)
        )
    }

    mutating func clear() {
        activeSkillIDs.removeAll()
        activeMCPServerIDs.removeAll()
    }

    mutating func restore(skillIDs: [UUID], mcpServerIDs: [UUID]) {
        activeSkillIDs = Set(skillIDs)
        activeMCPServerIDs = Set(mcpServerIDs)
    }

    mutating func keepAvailable(
        skills: [AgentSkill],
        mcpServers: [MCPServerConfiguration]
    ) {
        activeSkillIDs = activeSkillIDs.intersection(Set(skills.map(\.id)))
        activeMCPServerIDs = activeMCPServerIDs.intersection(Set(mcpServers.map(\.id)))
    }

    func containsSkill(_ id: UUID) -> Bool {
        activeSkillIDs.contains(id)
    }

    func containsMCPServer(_ id: UUID) -> Bool {
        activeMCPServerIDs.contains(id)
    }

    mutating func toggleSkill(_ id: UUID) {
        if activeSkillIDs.contains(id) {
            activeSkillIDs.remove(id)
        } else {
            activeSkillIDs.insert(id)
        }
    }

    mutating func toggleMCPServer(_ id: UUID) {
        if activeMCPServerIDs.contains(id) {
            activeMCPServerIDs.remove(id)
        } else {
            activeMCPServerIDs.insert(id)
        }
    }

    mutating func deactivate(_ capsule: ActiveAgentCapsule) {
        switch capsule.kind {
        case .skill:
            activeSkillIDs.remove(capsule.id)
        case .mcp:
            activeMCPServerIDs.remove(capsule.id)
        }
    }

    func activeSkills(in skills: [AgentSkill]) -> [AgentSkill] {
        skills.filter { activeSkillIDs.contains($0.id) }
    }

    func activeMCPServers(in servers: [MCPServerConfiguration]) -> [MCPServerConfiguration] {
        servers.filter { activeMCPServerIDs.contains($0.id) }
    }

    func capsules(
        skills: [AgentSkill],
        mcpServers: [MCPServerConfiguration]
    ) -> [ActiveAgentCapsule] {
        let skillCapsules = activeSkills(in: skills).map { skill in
            ActiveAgentCapsule(
                id: skill.id,
                kind: .skill,
                title: skill.displayName,
                icon: "wand.and.sparkles"
            )
        }
        let mcpCapsules = activeMCPServers(in: mcpServers).map { server in
            ActiveAgentCapsule(
                id: server.id,
                kind: .mcp,
                title: server.name,
                icon: server.kind == .tavily ? "globe" : "point.3.connected.trianglepath.dotted"
            )
        }
        return skillCapsules + mcpCapsules
    }
}
