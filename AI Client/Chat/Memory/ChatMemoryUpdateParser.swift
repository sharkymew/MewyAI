import Foundation

/// Parses memory operations from a model response. The model is asked for
/// `{"operations":[{"action":"add","content":"…"},{"action":"update","index":2,"content":"…"},{"action":"delete","index":3}]}`
/// but responses may wrap the JSON in code fences or prose, so parsing scans
/// for the outermost object and ignores unknown actions.
nonisolated enum ChatMemoryUpdateParser {
    static func operations(from content: String) -> [ChatMemoryOperation]? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        for candidate in jsonCandidates(in: trimmedContent) {
            if let operations = decodedOperations(fromJSONString: candidate) {
                return operations
            }
        }

        return nil
    }

    private static func jsonCandidates(in content: String) -> [String] {
        var candidates = [content]

        if let firstBrace = content.firstIndex(of: "{"),
           let lastBrace = content.lastIndex(of: "}"),
           firstBrace < lastBrace {
            candidates.append(String(content[firstBrace...lastBrace]))
        }

        return candidates
    }

    private static func decodedOperations(fromJSONString jsonString: String) -> [ChatMemoryOperation]? {
        guard let data = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(OperationsPayload.self, from: data) else {
            return nil
        }

        return payload.operations.compactMap(\.operation)
    }

    private struct OperationsPayload: Decodable {
        let operations: [OperationCandidate]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            operations = try container.decodeIfPresent([OperationCandidate].self, forKey: .operations) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case operations
        }
    }

    private struct OperationCandidate: Decodable {
        let action: String?
        let index: Int?
        let content: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try container.decodeIfPresent(String.self, forKey: .action)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            if let intIndex = try? container.decodeIfPresent(Int.self, forKey: .index) {
                index = intIndex
            } else if let stringIndex = try? container.decodeIfPresent(String.self, forKey: .index) {
                index = Int(stringIndex.trimmingCharacters(in: .whitespaces))
            } else {
                index = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case action
            case index
            case content
        }

        var operation: ChatMemoryOperation? {
            guard let action,
                  let parsedAction = ChatMemoryOperationAction(
                    rawValue: action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                  ) else {
                return nil
            }

            return ChatMemoryOperation(action: parsedAction, index: index, content: content)
        }
    }
}
