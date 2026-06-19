import Foundation

struct ConversationExportDraft {
    var document = ConversationMarkdownDocument(text: "")
    var fileName = AppLocalizations.string("markdown.fileName.fallback", defaultValue: "Conversation")
    var isPresented = false
    var errorMessage: String?

    mutating func prepare(for conversation: AIConversation) {
        document = ConversationMarkdownDocument(
            text: ConversationMarkdownExporter.markdown(for: conversation)
        )
        fileName = ConversationMarkdownExporter.defaultFileName(for: conversation)
        isPresented = true
    }

    mutating func handleCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            errorMessage = nil
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            errorMessage = AppLocalizations.format(
                "markdown.exportFailed",
                defaultValue: "Unable to export Markdown file: %@",
                arguments: [error.localizedDescription]
            )
        }
    }

    mutating func clearError() {
        errorMessage = nil
    }
}
