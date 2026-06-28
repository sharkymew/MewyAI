import XCTest
@testable import MewyAI

@MainActor
final class AgentCapabilitySelectionTests: XCTestCase {
    func testToggleSkillAndMCPServer() {
        let skillID = UUID()
        let serverID = UUID()
        var selection = AgentCapabilitySelection()

        selection.toggleSkill(skillID)
        selection.toggleMCPServer(serverID)

        XCTAssertTrue(selection.containsSkill(skillID))
        XCTAssertTrue(selection.containsMCPServer(serverID))

        selection.toggleSkill(skillID)
        selection.toggleMCPServer(serverID)

        XCTAssertFalse(selection.containsSkill(skillID))
        XCTAssertFalse(selection.containsMCPServer(serverID))
    }

    func testRestoreAndClearSelection() {
        let skillID = UUID()
        let serverID = UUID()
        var selection = AgentCapabilitySelection()

        selection.restore(skillIDs: [skillID], mcpServerIDs: [serverID])

        XCTAssertEqual(selection.activeSkillIDs, [skillID])
        XCTAssertEqual(selection.activeMCPServerIDs, [serverID])

        selection.clear()

        XCTAssertTrue(selection.activeSkillIDs.isEmpty)
        XCTAssertTrue(selection.activeMCPServerIDs.isEmpty)
    }

    func testKeepAvailablePrunesRemovedCapabilities() {
        let keptSkillID = UUID()
        let removedSkillID = UUID()
        let keptServerID = UUID()
        let removedServerID = UUID()
        var selection = AgentCapabilitySelection(
            activeSkillIDs: [keptSkillID, removedSkillID],
            activeMCPServerIDs: [keptServerID, removedServerID]
        )

        selection.keepAvailable(
            skills: [skill(id: keptSkillID, name: "Kept")],
            mcpServers: [server(id: keptServerID, name: "Kept")]
        )

        XCTAssertEqual(selection.activeSkillIDs, [keptSkillID])
        XCTAssertEqual(selection.activeMCPServerIDs, [keptServerID])
    }

    func testActiveCapabilitiesPreserveSourceOrder() {
        let firstSkillID = UUID()
        let secondSkillID = UUID()
        let firstServerID = UUID()
        let secondServerID = UUID()
        let selection = AgentCapabilitySelection(
            activeSkillIDs: [secondSkillID, firstSkillID],
            activeMCPServerIDs: [secondServerID, firstServerID]
        )

        let activeSkills = selection.activeSkills(in: [
            skill(id: firstSkillID, name: "First"),
            skill(id: UUID(), name: "Inactive"),
            skill(id: secondSkillID, name: "Second")
        ])
        let activeServers = selection.activeMCPServers(in: [
            server(id: firstServerID, name: "First"),
            server(id: UUID(), name: "Inactive"),
            server(id: secondServerID, name: "Second")
        ])

        XCTAssertEqual(activeSkills.map(\.id), [firstSkillID, secondSkillID])
        XCTAssertEqual(activeServers.map(\.id), [firstServerID, secondServerID])
    }

    func testCapsulesBuildDisplayMetadata() {
        let skillID = UUID()
        let tavilyID = UUID()
        let customServerID = UUID()
        let selection = AgentCapabilitySelection(
            activeSkillIDs: [skillID],
            activeMCPServerIDs: [tavilyID, customServerID]
        )

        let capsules = selection.capsules(
            skills: [skill(id: skillID, name: "  Writer  ")],
            mcpServers: [
                server(id: tavilyID, name: "Tavily", kind: .tavily),
                server(id: customServerID, name: "Docs", kind: .custom)
            ]
        )

        XCTAssertEqual(capsules.map(\.id), [skillID, tavilyID, customServerID])
        XCTAssertEqual(capsules.map(\.title), ["Writer", "Tavily", "Docs"])
        XCTAssertEqual(capsules.map(\.icon), [
            "wand.and.sparkles",
            "globe",
            "point.3.connected.trianglepath.dotted"
        ])

        assertKind(capsules[0], isSkill: true)
        assertKind(capsules[1], isSkill: false)
        assertKind(capsules[2], isSkill: false)
    }

    func testDeactivateCapsuleRemovesOnlyMatchingCapabilityKind() {
        let id = UUID()
        var selection = AgentCapabilitySelection(
            activeSkillIDs: [id],
            activeMCPServerIDs: [id]
        )

        selection.deactivate(ActiveAgentCapsule(id: id, kind: .skill, title: "Skill", icon: "wand.and.sparkles"))

        XCTAssertFalse(selection.containsSkill(id))
        XCTAssertTrue(selection.containsMCPServer(id))

        selection.deactivate(ActiveAgentCapsule(id: id, kind: .mcp, title: "MCP", icon: "globe"))

        XCTAssertFalse(selection.containsMCPServer(id))
    }

    private func skill(id: UUID, name: String) -> AgentSkill {
        AgentSkill(id: id, name: name, description: "", content: "")
    }

    private func server(
        id: UUID,
        name: String,
        kind: MCPServerKind = .custom
    ) -> MCPServerConfiguration {
        MCPServerConfiguration(
            id: id,
            name: name,
            serverURL: "https://example.com/mcp",
            kind: kind
        )
    }

    private func assertKind(_ capsule: ActiveAgentCapsule, isSkill: Bool) {
        switch (capsule.kind, isSkill) {
        case (.skill, true), (.mcp, false):
            break
        default:
            XCTFail("Unexpected capsule kind")
        }
    }
}
