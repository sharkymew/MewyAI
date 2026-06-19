import Foundation
import SwiftUI

nonisolated struct StreamingMarkdownRenderResult: @unchecked Sendable {
    let segments: [StreamingChatMarkdownSegment]
    let cache: PreparedMarkdownBlockCache
}
