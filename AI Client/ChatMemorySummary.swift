import Foundation

nonisolated struct ChatMemorySummarySection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String

    static func == (lhs: ChatMemorySummarySection, rhs: ChatMemorySummarySection) -> Bool {
        lhs.title == rhs.title && lhs.body == rhs.body
    }
}

/// Parses model-generated memory summaries. The model is asked for
/// `{"sections":[{"title":"...","body":"..."}]}`, but parsing accepts
/// JSON wrapped in code fences or short prose so provider quirks do not break
/// the management UI.
nonisolated enum ChatMemorySummaryParser {
    static func sections(from content: String) -> [ChatMemorySummarySection]? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        for candidate in jsonCandidates(in: trimmedContent) {
            if let sections = decodedSections(fromJSONString: candidate) {
                return sections
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

    private static func decodedSections(fromJSONString jsonString: String) -> [ChatMemorySummarySection]? {
        guard let data = jsonString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SummaryPayload.self, from: data) else {
            return nil
        }

        return payload.sections.compactMap(\.section)
    }

    private struct SummaryPayload: Decodable {
        let sections: [SectionCandidate]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sections = try container.decodeIfPresent([SectionCandidate].self, forKey: .sections) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case sections
        }
    }

    private struct SectionCandidate: Decodable {
        let title: String?
        let body: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body)
                ?? container.decodeIfPresent(String.self, forKey: .content)
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case body
            case content
        }

        var section: ChatMemorySummarySection? {
            guard let title = sanitized(title),
                  let body = sanitized(body) else {
                return nil
            }

            return ChatMemorySummarySection(title: title, body: body)
        }

        private func sanitized(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
