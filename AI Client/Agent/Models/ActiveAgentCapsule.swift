import Foundation
import SwiftUI

struct ActiveAgentCapsule: Identifiable {
    enum Kind {
        case skill
        case mcp
    }

    let id: UUID
    let kind: Kind
    let title: String
    let icon: String
}
