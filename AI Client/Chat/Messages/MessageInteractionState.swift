import Foundation

struct MessageInteractionState: Equatable {
    var activeActionID: UUID?
    var didTapBubble = false
    var editingMessageID: UUID?

    var isEditing: Bool {
        editingMessageID != nil
    }
}
