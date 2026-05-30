import Foundation

struct AgentSkill: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var content: String
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        content: String,
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MCPServerKind: String, Codable {
    case tavily
    case custom
}

struct MCPServerConfiguration: Identifiable, Codable, Equatable {
    static let tavilyID = UUID(uuidString: "A17A5D4B-6B08-4B7A-9F1B-6C6B8C25F511")!
    static let tavilyURL = "https://mcp.tavily.com/mcp/"
    static let tavilySearchToolName = "tavily_search"
    static let tavilyExtractToolName = "tavily_extract"

    var id: UUID
    var name: String
    var serverURL: String
    var kind: MCPServerKind
    var allowedToolNames: [String]
    var requiresApproval: Bool
    var cachedTools: [MCPToolDefinition]
    var updatedAt: Date
    var authorizationToken: String

    init(
        id: UUID = UUID(),
        name: String,
        serverURL: String,
        kind: MCPServerKind = .custom,
        allowedToolNames: [String] = [],
        requiresApproval: Bool = true,
        cachedTools: [MCPToolDefinition] = [],
        updatedAt: Date = Date(),
        authorizationToken: String = ""
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.kind = kind
        self.allowedToolNames = allowedToolNames
        self.requiresApproval = requiresApproval
        self.cachedTools = cachedTools
        self.updatedAt = updatedAt
        self.authorizationToken = authorizationToken
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case serverURL
        case kind
        case allowedToolNames
        case requiresApproval
        case cachedTools
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "MCP Server"
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        kind = try container.decodeIfPresent(MCPServerKind.self, forKey: .kind) ?? .custom
        allowedToolNames = try container.decodeIfPresent([String].self, forKey: .allowedToolNames) ?? []
        requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? true
        cachedTools = try container.decodeIfPresent([MCPToolDefinition].self, forKey: .cachedTools) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        authorizationToken = KeychainService.readAgentSecret(for: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(kind, forKey: .kind)
        try container.encode(allowedToolNames, forKey: .allowedToolNames)
        try container.encode(requiresApproval, forKey: .requiresApproval)
        try container.encode(cachedTools, forKey: .cachedTools)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    func persistSecureFields() -> Bool {
        KeychainService.saveAgentSecret(
            authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines),
            for: id
        )
    }

    static func tavilyDefault() -> MCPServerConfiguration {
        MCPServerConfiguration(
            id: tavilyID,
            name: "Tavily 搜索",
            serverURL: tavilyURL,
            kind: .tavily,
            allowedToolNames: [tavilySearchToolName],
            requiresApproval: true,
            cachedTools: [
                MCPToolDefinition(
                    name: tavilySearchToolName,
                    description: "Search the web with Tavily and return concise search results.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("Search query")
                            ]),
                            "max_results": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of results to return")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ])
                )
            ]
        )
    }
}

struct MCPToolDefinition: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var description: String
    var inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema
        case inputSchemaSnake = "input_schema"
    }

    init(name: String, description: String = "", inputSchema: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        inputSchema = try container.decodeIfPresent(JSONValue.self, forKey: .inputSchema)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .inputSchemaSnake)
            ?? .object([:])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
    }
}

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        }
    }

    var compactJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

enum AgentCapabilityStore {
    private static let skillsKey = "agentSkills"
    private static let mcpServersKey = "agentMCPServers"

    static func loadSkills() -> [AgentSkill] {
        let decoded = UserDefaults.standard.data(forKey: skillsKey)
            .flatMap { try? JSONDecoder().decode([AgentSkill].self, from: $0) } ?? []

        if decoded.contains(where: { $0.name == builtInSkillCreator.name }) {
            return decoded
        }

        let skills = [builtInSkillCreator] + decoded
        saveSkills(skills)
        return skills
    }

    @discardableResult
    static func saveSkills(_ skills: [AgentSkill]) -> Bool {
        guard let data = try? JSONEncoder().encode(skills) else { return false }
        UserDefaults.standard.set(data, forKey: skillsKey)
        return true
    }

    static func loadMCPServers() -> [MCPServerConfiguration] {
        var servers = UserDefaults.standard.data(forKey: mcpServersKey)
            .flatMap { try? JSONDecoder().decode([MCPServerConfiguration].self, from: $0) } ?? []
        var didRepairServers = false

        if let tavilyIndex = servers.firstIndex(where: { $0.id == MCPServerConfiguration.tavilyID }) {
            let repairedServer = repairedTavilyServer(servers[tavilyIndex])
            if repairedServer != servers[tavilyIndex] {
                servers[tavilyIndex] = repairedServer
                didRepairServers = true
            }
        } else {
            servers.insert(MCPServerConfiguration.tavilyDefault(), at: 0)
            didRepairServers = true
        }

        if didRepairServers {
            saveMCPServers(servers)
        }

        return servers
    }

    @discardableResult
    static func saveMCPServers(_ servers: [MCPServerConfiguration]) -> Bool {
        guard servers.allSatisfy({ $0.persistSecureFields() }) else { return false }
        guard let data = try? JSONEncoder().encode(servers) else { return false }
        UserDefaults.standard.set(data, forKey: mcpServersKey)
        return true
    }

    static func deleteMCPServerSecret(id: UUID) {
        KeychainService.deleteAgentSecret(for: id)
    }

    private static func repairedTavilyServer(_ server: MCPServerConfiguration) -> MCPServerConfiguration {
        let defaultServer = MCPServerConfiguration.tavilyDefault()
        var repairedServer = server
        repairedServer.id = defaultServer.id
        repairedServer.name = defaultServer.name
        repairedServer.serverURL = defaultServer.serverURL
        repairedServer.kind = .tavily
        repairedServer.requiresApproval = true
        repairedServer.cachedTools = repairedServer.cachedTools.map { tool in
            var normalizedTool = tool
            normalizedTool.name = normalizedTavilyToolName(tool.name)
            return normalizedTool
        }
        repairedServer.cachedTools = Array(
            Dictionary(grouping: repairedServer.cachedTools, by: \.name)
                .compactMap { $0.value.first }
        )
        .sorted { $0.name < $1.name }

        for defaultTool in defaultServer.cachedTools
        where !repairedServer.cachedTools.contains(where: { $0.name == defaultTool.name }) {
            repairedServer.cachedTools.append(defaultTool)
        }

        let cachedToolNames = Set(repairedServer.cachedTools.map(\.name))
        let allowedToolNames = repairedServer.allowedToolNames
            .map(normalizedTavilyToolName)
            .filter { cachedToolNames.contains($0) }
        repairedServer.allowedToolNames = allowedToolNames.isEmpty ? defaultServer.allowedToolNames : allowedToolNames

        return repairedServer
    }

    nonisolated static func normalizedTavilyToolName(_ name: String) -> String {
        switch name {
        case "tavily-search":
            return "tavily_search"
        case "tavily-extract", "tavily-search-extract":
            return "tavily_extract"
        default:
            return name
        }
    }

    static func parseSkillMarkdown(_ markdown: String) throws -> AgentSkill {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("---") else {
            throw AgentSkillParseError.missingFrontmatter
        }

        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 2 else { throw AgentSkillParseError.missingFrontmatter }

        var metadataLines = [String]()
        var bodyStartIndex: Int?
        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                bodyStartIndex = index + 1
                break
            }
            metadataLines.append(lines[index])
        }

        guard bodyStartIndex != nil else { throw AgentSkillParseError.missingFrontmatter }
        let metadata = parseSimpleFrontmatter(metadataLines)
        let name = metadata["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = metadata["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isValidSkillName(name) else { throw AgentSkillParseError.invalidName }
        guard !description.isEmpty else { throw AgentSkillParseError.missingDescription }

        return AgentSkill(
            name: name,
            description: description,
            content: text,
            isBuiltIn: false
        )
    }

    static func skillMarkdown(name: String, description: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name.count <= 64,
              name.first?.isLetter == true || name.first?.isNumber == true else {
            return false
        }
        return name.allSatisfy { character in
            character.isLowercase || character.isNumber || character == "-"
        }
    }

    private static func parseSimpleFrontmatter(_ lines: [String]) -> [String: String] {
        var metadata: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            metadata[key] = String(value)
        }
        return metadata
    }

    static let builtInSkillCreator = AgentSkill(
        id: UUID(uuidString: "A9A69604-3160-4D72-B203-5E2A9B1F5E48")!,
        name: "skill-creator",
        description: "Create iPhone-friendly text-only SKILL.md files for AI Client without Python scripts, shell commands, or local code execution.",
        content: """
        ---
        name: skill-creator
        description: Create iPhone-friendly text-only SKILL.md files for AI Client without Python scripts, shell commands, or local code execution.
        ---

        # Skill Creator for AI Client

        Use this skill to draft a complete `SKILL.md` that can be imported into AI Client as a text-only Agent Skill.

        ## Constraints

        - Output one complete Markdown file.
        - Start with YAML frontmatter containing `name` and `description`.
        - Use a lowercase, dash-separated `name`.
        - Keep `description` short and action-oriented.
        - Do not require Python, shell commands, local scripts, subprocesses, hidden files, package installation, or desktop-only tooling.
        - Do not claim the skill can execute code. In AI Client, skills are instruction packages injected into model context.
        - Prefer concise instructions, clear trigger guidance, input expectations, output shape, and safety notes.

        ## Recommended Structure

        1. `# Overview`
        2. `## When to Use`
        3. `## Inputs`
        4. `## Workflow`
        5. `## Output`
        6. `## Safety Notes`

        ## Output Rule

        Return only the `SKILL.md` content. Do not wrap it in code fences.
        """,
        isBuiltIn: true
    )
}

enum AgentSkillParseError: LocalizedError {
    case missingFrontmatter
    case invalidName
    case missingDescription

    var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            return "SKILL.md 必须包含 YAML frontmatter。"
        case .invalidName:
            return "Skill name 只能包含小写字母、数字和连字符。"
        case .missingDescription:
            return "Skill description 不能为空。"
        }
    }
}
