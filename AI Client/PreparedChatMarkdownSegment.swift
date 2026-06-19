import Foundation
import SwiftUI

nonisolated struct PreparedChatMarkdownSegment: Identifiable, @unchecked Sendable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text([PreparedMarkdownBlock])
        case code(language: String?, code: String)
        case math(PreparedLaTeXFormula)
    }
}
