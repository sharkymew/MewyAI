import Foundation

enum ChatStreamingErrorPresentation {
    static func assistantMessage(
        for failure: ChatSessionViewModel.StreamingTurnPreparationFailure
    ) -> String? {
        switch failure {
        case .emptyMessage, .missingConversation, .alreadyGenerating:
            return nil
        case .vertexMCPUnsupported:
            return AppLocalizations.string(
                "chat.error.vertexMCPUnsupported",
                defaultValue: "Vertex Express does not support MCP tool calls. Disable MCP capsules or switch API type."
            )
        case .modelToolsUnsupported:
            return AppLocalizations.string(
                "chat.error.modelToolsUnsupported",
                defaultValue: "The current model is not marked as supporting tool calls. Enable Tools in model settings, or disable MCP capsules before sending."
            )
        case .noMCPTools:
            return AppLocalizations.string(
                "chat.error.noMCPTools",
                defaultValue: "The enabled MCP servers have no available tools. Refresh the tool list in settings or check allowed tool names."
            )
        case .imageWithoutDescription:
            return AppLocalizations.string(
                "chat.error.imageWithoutDescription",
                defaultValue: "The current model does not support image input, and this image message does not have a usable hidden description yet. Switch to an image-capable multimodal model and try again."
            )
        case .contextImageWithoutDescription:
            return AppLocalizations.string(
                "chat.error.contextImageWithoutDescription",
                defaultValue: "The current model does not support image input, and an image message in the context does not have a usable hidden description yet. Try again later, or switch to an image-capable multimodal model."
            )
        case .missingBaseURL:
            return AppLocalizations.string(
                "chat.error.configureBaseURL",
                defaultValue: "Configure Base URL first."
            )
        case .missingModel:
            return AppLocalizations.string(
                "chat.error.selectModel",
                defaultValue: "Select a model first."
            )
        case .tooManyActiveRequests(let limit):
            return AppLocalizations.format(
                "chat.error.tooManyActiveRequests",
                defaultValue: "%d conversations are already requesting. Wait for one to finish before sending.",
                arguments: [limit]
            )
        }
    }

    static func persistentAssistantMessage(from error: String) -> String {
        let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedError.isEmpty
            ? AppLocalizations.string("aiService.diagnostics.requestFailedFallback", defaultValue: "Request failed")
            : trimmedError
    }
}
