import Foundation
import SwiftUI

struct PendingToolApproval: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: String
}
