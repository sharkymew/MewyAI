import Foundation
import SwiftUI

nonisolated struct StreamingChatMarkdownSegment: Identifiable, @unchecked Sendable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text([PreparedMarkdownBlock])
        case fallbackText(String)
        case code(language: String?, code: String)
        case math(formula: String, displayMode: Bool)
    }
}
