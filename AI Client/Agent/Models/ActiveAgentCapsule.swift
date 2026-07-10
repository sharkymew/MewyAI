import Foundation
import SwiftUI

struct ActiveAgentCapsule: Identifiable {
    enum Kind: Equatable {
        case skill
        case mcp
        case knowledgeBase
    }

    let id: UUID
    let kind: Kind
    let title: String
    let icon: String
}
