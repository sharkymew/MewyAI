import Foundation

nonisolated enum ChatUsageDisplayFormatter {
    static func footerText(
        for message: ChatMessage,
        configurations: [AIConfiguration]
    ) -> String? {
        guard message.role == "assistant",
              let usage = message.usage,
              usage.hasTokenCounts else {
            return nil
        }

        var parts = [String]()
        if let tokensText = tokensText(for: usage) {
            parts.append(tokensText)
        }
        if let cost = ChatUsagePricing.estimatedCost(for: usage, in: configurations) {
            parts.append("≈" + ChatUsageFormatting.costText(cost))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func tokensText(for usage: ChatUsage) -> String? {
        if usage.inputTokens != nil || usage.outputTokens != nil {
            return AppLocalizations.format(
                "chat.usage.tokens",
                defaultValue: "↑ %@ · ↓ %@",
                arguments: [
                    ChatUsageFormatting.tokenCountText(usage.inputTokens ?? 0),
                    ChatUsageFormatting.tokenCountText(usage.outputTokens ?? 0)
                ]
            )
        }

        guard let totalTokens = usage.resolvedTotalTokens else { return nil }
        return AppLocalizations.format(
            "chat.usage.totalTokens",
            defaultValue: "%@ tokens",
            arguments: [ChatUsageFormatting.tokenCountText(totalTokens)]
        )
    }

    static func conversationSummaryText(
        for messages: [ChatMessage],
        configurations: [AIConfiguration]
    ) -> String? {
        guard let summary = ConversationUsageSummary.summary(
            of: messages,
            configurations: configurations
        ) else {
            return nil
        }

        var text = AppLocalizations.format(
            "chat.usage.tokens",
            defaultValue: "↑ %@ · ↓ %@",
            arguments: [
                ChatUsageFormatting.tokenCountText(summary.inputTokens),
                ChatUsageFormatting.tokenCountText(summary.outputTokens)
            ]
        )
        if let costsText = ChatUsageFormatting.costsText(summary.costsByCurrency) {
            text += " · ≈" + costsText
        }
        return text
    }
}
