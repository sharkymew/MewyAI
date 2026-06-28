import Foundation
import SwiftUI

struct ErrorDetailContent: Equatable {
    let summary: String
    let details: String

    static func parse(_ message: String) -> ErrorDetailContent? {
        let normalized = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorRange = normalized.range(of: "\n\n") ?? normalized.range(of: "\n") else {
            return nil
        }

        let summary = String(normalized[..<separatorRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let details = String(normalized[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty,
              !details.isEmpty,
              summaryLooksLikeError(summary) else {
            return nil
        }

        return ErrorDetailContent(summary: summary, details: details)
    }

    private static func summaryLooksLikeError(_ summary: String) -> Bool {
        summary.hasPrefix("请求失败")
            || summary.hasPrefix("Request failed")
            || summary.hasPrefix("解析失败")
            || summary.hasPrefix("Parsing failed")
            || summary.hasPrefix("模型列表解析失败")
            || summary.hasPrefix("Failed to parse model list")
            || summary.hasPrefix("流式请求失败")
            || summary.hasPrefix("Streaming request failed")
            || summary.contains("状态码")
            || summary.contains("status code")
    }
}
