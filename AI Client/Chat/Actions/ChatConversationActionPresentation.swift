import Foundation

struct ChatConversationActionPresentation: Equatable {
    let canCreateConversation: Bool
    let showsTemporaryChatNotice: Bool
    let showsPrivateConversationAction: Bool
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String

    init(
        isCurrentConversationBlank: Bool,
        isPrivateConversationSelected: Bool,
        canCreateConversation: Bool = true
    ) {
        self.canCreateConversation = canCreateConversation
        showsTemporaryChatNotice = isPrivateConversationSelected && isCurrentConversationBlank
        showsPrivateConversationAction = isCurrentConversationBlank && !isPrivateConversationSelected
        systemImage = showsPrivateConversationAction ? "lock" : "square.and.pencil"

        if showsTemporaryChatNotice {
            accessibilityLabel = AppLocalizations.string(
                "accessibility.exitTemporaryChat",
                defaultValue: "Exit temporary chat"
            )
            accessibilityHint = AppLocalizations.string(
                "accessibility.temporaryChatHint",
                defaultValue: "Temporary chats are not saved locally"
            )
            return
        }

        accessibilityLabel = showsPrivateConversationAction
            ? AppLocalizations.string(
                "accessibility.startPrivateConversation",
                defaultValue: "Start private conversation"
            )
            : AppLocalizations.string(
                "accessibility.newConversation",
                defaultValue: "New conversation"
            )
        accessibilityHint = ""
    }
}
