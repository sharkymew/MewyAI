import Foundation

/// Per-request token usage reported by a provider, normalized so that
/// `inputTokens` always counts the full prompt (including cached tokens)
/// and `outputTokens` always counts the full completion (including
/// reasoning tokens), regardless of provider conventions.
nonisolated struct ChatUsage: Codable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var cacheReadInputTokens: Int?
    var cacheWriteInputTokens: Int?
    var reasoningOutputTokens: Int?
    var modelName: String?
    var configurationID: UUID?

    init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil,
        cacheWriteInputTokens: Int? = nil,
        reasoningOutputTokens: Int? = nil,
        modelName: String? = nil,
        configurationID: UUID? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.modelName = modelName
        self.configurationID = configurationID
    }

    var hasTokenCounts: Bool {
        inputTokens != nil || outputTokens != nil || totalTokens != nil
    }

    var resolvedTotalTokens: Int? {
        if let totalTokens {
            return totalTokens
        }
        guard inputTokens != nil || outputTokens != nil else { return nil }
        return (inputTokens ?? 0) + (outputTokens ?? 0)
    }

    /// Field-wise overwrite used while a single streamed response progresses:
    /// later events win, fields the newer event does not carry are kept.
    func merging(_ newer: ChatUsage) -> ChatUsage {
        ChatUsage(
            inputTokens: newer.inputTokens ?? inputTokens,
            outputTokens: newer.outputTokens ?? outputTokens,
            totalTokens: newer.totalTokens ?? totalTokens,
            cacheReadInputTokens: newer.cacheReadInputTokens ?? cacheReadInputTokens,
            cacheWriteInputTokens: newer.cacheWriteInputTokens ?? cacheWriteInputTokens,
            reasoningOutputTokens: newer.reasoningOutputTokens ?? reasoningOutputTokens,
            modelName: newer.modelName ?? modelName,
            configurationID: newer.configurationID ?? configurationID
        )
    }

    /// Field-wise sum used to accumulate several requests (tool-call rounds)
    /// into the usage of one assistant message.
    func adding(_ other: ChatUsage) -> ChatUsage {
        func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
            guard lhs != nil || rhs != nil else { return nil }
            return (lhs ?? 0) + (rhs ?? 0)
        }

        return ChatUsage(
            inputTokens: sum(inputTokens, other.inputTokens),
            outputTokens: sum(outputTokens, other.outputTokens),
            totalTokens: sum(totalTokens, other.totalTokens),
            cacheReadInputTokens: sum(cacheReadInputTokens, other.cacheReadInputTokens),
            cacheWriteInputTokens: sum(cacheWriteInputTokens, other.cacheWriteInputTokens),
            reasoningOutputTokens: sum(reasoningOutputTokens, other.reasoningOutputTokens),
            modelName: modelName ?? other.modelName,
            configurationID: configurationID ?? other.configurationID
        )
    }
}

nonisolated struct ChatUsageCost: Equatable {
    var amount: Double
    var currencyCode: String
}

nonisolated enum ChatUsagePricing {
    static let defaultCurrencyCode = "USD"
    static let supportedCurrencyCodes = ["USD", "CNY", "EUR", "GBP", "JPY"]

    static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD":
            return "$"
        case "CNY":
            return "¥"
        case "EUR":
            return "€"
        case "GBP":
            return "£"
        case "JPY":
            return "JP¥"
        default:
            return code
        }
    }

    /// Finds the model whose manually maintained prices should be used for
    /// the given usage. Prefers the configuration that produced the message,
    /// then any configuration that has a priced model with the same name.
    static func modelConfiguration(
        for usage: ChatUsage,
        in configurations: [AIConfiguration]
    ) -> AIModelConfiguration? {
        guard let modelName = usage.modelName else { return nil }

        if let configurationID = usage.configurationID,
           let configuration = configurations.first(where: { $0.id == configurationID }),
           let model = configuration.models.first(where: { $0.name == modelName }) {
            return model
        }

        let candidates = configurations.flatMap(\.models).filter { $0.name == modelName }
        return candidates.first(where: \.hasPricing) ?? candidates.first
    }

    static func estimatedCost(
        for usage: ChatUsage,
        model: AIModelConfiguration?
    ) -> ChatUsageCost? {
        guard let model, model.hasPricing else { return nil }

        let inputAmount = Double(usage.inputTokens ?? 0) / 1_000_000
            * (model.inputPricePerMillionTokens ?? 0)
        let outputAmount = Double(usage.outputTokens ?? 0) / 1_000_000
            * (model.outputPricePerMillionTokens ?? 0)
        return ChatUsageCost(
            amount: inputAmount + outputAmount,
            currencyCode: model.priceCurrencyCode ?? defaultCurrencyCode
        )
    }

    static func estimatedCost(
        for usage: ChatUsage,
        in configurations: [AIConfiguration]
    ) -> ChatUsageCost? {
        estimatedCost(for: usage, model: modelConfiguration(for: usage, in: configurations))
    }
}

/// Aggregated usage of all messages currently visible in a conversation.
nonisolated struct ConversationUsageSummary: Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var costsByCurrency: [String: Double]

    nonisolated static func summary(
        of messages: [ChatMessage],
        configurations: [AIConfiguration]
    ) -> ConversationUsageSummary? {
        var summary = ConversationUsageSummary(
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
            costsByCurrency: [:]
        )
        var hasUsage = false

        for message in messages {
            guard let usage = message.usage, usage.hasTokenCounts else { continue }
            hasUsage = true
            summary.inputTokens += usage.inputTokens ?? 0
            summary.outputTokens += usage.outputTokens ?? 0
            summary.totalTokens += usage.resolvedTotalTokens ?? 0
            if let cost = ChatUsagePricing.estimatedCost(for: usage, in: configurations) {
                summary.costsByCurrency[cost.currencyCode, default: 0] += cost.amount
            }
        }

        return hasUsage ? summary : nil
    }
}

nonisolated enum ChatUsageFormatting {
    static func tokenCountText(_ count: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func amountText(_ amount: Double) -> String {
        let decimals: Int
        switch abs(amount) {
        case 0.1...:
            decimals = 2
        case 0.001...:
            decimals = 4
        case 0:
            decimals = 2
        default:
            decimals = 6
        }
        return String(format: "%.\(decimals)f", amount)
    }

    static func costText(_ cost: ChatUsageCost) -> String {
        ChatUsagePricing.currencySymbol(for: cost.currencyCode) + amountText(cost.amount)
    }

    static func costsText(_ costsByCurrency: [String: Double]) -> String? {
        guard !costsByCurrency.isEmpty else { return nil }
        return costsByCurrency
            .sorted { $0.key < $1.key }
            .map { costText(ChatUsageCost(amount: $0.value, currencyCode: $0.key)) }
            .joined(separator: " + ")
    }
}
