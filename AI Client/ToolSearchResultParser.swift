import Foundation

nonisolated struct ToolSearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
}

private nonisolated struct ToolSearchResultCandidate: Equatable {
    let title: String
    let url: URL
}

nonisolated enum ToolSearchResultParser {
    static func results(from content: String) -> [ToolSearchResult] {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return []
        }

        var visitedStrings = Set<String>()
        var candidates = candidates(fromJSONString: trimmedContent, depth: 0, visitedStrings: &visitedStrings)
        if candidates.isEmpty {
            candidates = scannedCandidates(from: trimmedContent)
        }
        var seenURLs = Set<String>()

        return candidates.enumerated().compactMap { index, candidate in
            let key = candidate.url.absoluteString
            guard seenURLs.insert(key).inserted else { return nil }

            return ToolSearchResult(
                id: "\(index)-\(key)",
                title: candidate.title,
                url: candidate.url
            )
        }
    }

    private static func candidates(
        fromJSONString jsonString: String,
        depth: Int,
        visitedStrings: inout Set<String>
    ) -> [ToolSearchResultCandidate] {
        guard depth < 6 else { return [] }

        let trimmedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty,
              visitedStrings.insert(trimmedString).inserted,
              let data = trimmedString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return []
        }

        return candidates(fromJSONObject: object, depth: depth, visitedStrings: &visitedStrings)
    }

    private static func candidates(
        fromJSONObject object: Any,
        depth: Int,
        visitedStrings: inout Set<String>
    ) -> [ToolSearchResultCandidate] {
        guard depth < 6 else { return [] }

        if let string = object as? String {
            return candidates(fromJSONString: string, depth: depth + 1, visitedStrings: &visitedStrings)
        }

        if let array = object as? [Any] {
            let directCandidates = array.compactMap(Self.candidate)
            if !directCandidates.isEmpty {
                return directCandidates
            }

            return array.flatMap {
                Self.candidates(fromJSONObject: $0, depth: depth + 1, visitedStrings: &visitedStrings)
            }
        }

        guard let dictionary = object as? [String: Any] else {
            return []
        }

        var resolvedCandidates = [ToolSearchResultCandidate]()

        if let results = dictionary["results"] {
            resolvedCandidates.append(contentsOf: Self.candidates(fromJSONObject: results, depth: depth + 1, visitedStrings: &visitedStrings))
        }

        for key in ["structuredContent", "structured_content", "data", "result"] {
            if let nestedObject = dictionary[key] {
                resolvedCandidates.append(contentsOf: Self.candidates(fromJSONObject: nestedObject, depth: depth + 1, visitedStrings: &visitedStrings))
            }
        }

        if let content = dictionary["content"] {
            resolvedCandidates.append(contentsOf: Self.candidates(fromJSONObject: content, depth: depth + 1, visitedStrings: &visitedStrings))
        }

        for key in ["text", "json", "output"] {
            if let nestedString = dictionary[key] as? String,
               looksLikeJSON(nestedString) {
                resolvedCandidates.append(contentsOf: Self.candidates(fromJSONString: nestedString, depth: depth + 1, visitedStrings: &visitedStrings))
            }
        }

        if resolvedCandidates.isEmpty,
           let directCandidate = candidate(from: dictionary) {
            resolvedCandidates.append(directCandidate)
        }

        return resolvedCandidates
    }

    private static func candidate(from object: Any) -> ToolSearchResultCandidate? {
        guard let dictionary = object as? [String: Any] else { return nil }

        return candidate(from: dictionary)
    }

    private static func candidate(from dictionary: [String: Any]) -> ToolSearchResultCandidate? {
        guard let rawURL = firstStringValue(in: dictionary, forKeys: ["url", "link"]),
              let url = searchResultURL(from: rawURL) else {
            return nil
        }

        let rawTitle = firstStringValue(in: dictionary, forKeys: ["title", "name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty
            ? (fallbackTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString)
            : rawTitle

        return ToolSearchResultCandidate(title: title, url: url)
    }

    private static func searchResultURL(from rawURL: String) -> URL? {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        return url
    }

    private static func firstStringValue(in dictionary: [String: Any], forKeys keys: [String]) -> String? {
        for key in keys {
            if let string = dictionary[key] as? String {
                return string
            }
        }

        return nil
    }

    private static func looksLikeJSON(_ string: String) -> Bool {
        guard let firstCharacter = string.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }

        return firstCharacter == "{" || firstCharacter == "["
    }

    private static func scannedCandidates(from content: String) -> [ToolSearchResultCandidate] {
        let urlMatches = jsonStringMatches(forKey: "url", in: content)
        let titleMatches = jsonStringMatches(forKey: "title", in: content)
        guard !urlMatches.isEmpty else { return [] }

        return urlMatches.compactMap { urlMatch in
            guard let url = searchResultURL(from: urlMatch.value) else { return nil }

            let title = titleMatches
                .filter { $0.range.location > urlMatch.range.location }
                .min { $0.range.location < $1.range.location }?
                .value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                ?? fallbackTitle.flatMap { $0.isEmpty ? nil : $0 }
                ?? url.absoluteString

            return ToolSearchResultCandidate(title: resolvedTitle, url: url)
        }
    }

    private static func jsonStringMatches(forKey key: String, in content: String) -> [(value: String, range: NSRange)] {
        let pattern = #""# + NSRegularExpression.escapedPattern(for: key) + #""\s*:\s*"((?:\\.|[^"\\])*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        return regex.matches(in: content, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }

            let rawValue = nsContent.substring(with: match.range(at: 1))
            return (unescapedJSONStringValue(rawValue), match.range)
        }
    }

    private static func unescapedJSONStringValue(_ value: String) -> String {
        let jsonString = "\"\(value)\""
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return value
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
        }

        return decoded
    }
}
