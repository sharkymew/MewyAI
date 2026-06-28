import Foundation
import SwiftUI

@MainActor
final class AssistantLiveDisplay {
    let reasoningChannel = StreamingTextUpdateChannel()
    let contentChannel = StreamingTextUpdateChannel()
}
