import XCTest
@testable import MewyAI

@MainActor
final class ChatUsageTests: XCTestCase {
    func testOpenAIChatCompletionsUsageDecodes() throws {
        let data = """
        {
          "choices": [{"message": {"role": "assistant", "content": "hi"}}],
          "usage": {
            "prompt_tokens": 100,
            "completion_tokens": 40,
            "total_tokens": 140,
            "prompt_tokens_details": {"cached_tokens": 24},
            "completion_tokens_details": {"reasoning_tokens": 8}
          }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(OpenAIResponse.self, from: data).usage?.chatUsage

        XCTAssertEqual(usage?.inputTokens, 100)
        XCTAssertEqual(usage?.outputTokens, 40)
        XCTAssertEqual(usage?.totalTokens, 140)
        XCTAssertEqual(usage?.cacheReadInputTokens, 24)
        XCTAssertEqual(usage?.reasoningOutputTokens, 8)
    }

    func testDeepSeekCacheHitTokensDecodeAsCacheRead() throws {
        let data = """
        {
          "choices": [{"message": {"role": "assistant", "content": "hi"}}],
          "usage": {
            "prompt_tokens": 50,
            "completion_tokens": 10,
            "total_tokens": 60,
            "prompt_cache_hit_tokens": 32,
            "prompt_cache_miss_tokens": 18
          }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(OpenAIResponse.self, from: data).usage?.chatUsage

        XCTAssertEqual(usage?.inputTokens, 50)
        XCTAssertEqual(usage?.cacheReadInputTokens, 32)
    }

    func testAnthropicUsageFoldsCacheTokensIntoInput() throws {
        let data = """
        {
          "content": [{"type": "text", "text": "hi"}],
          "usage": {
            "input_tokens": 20,
            "output_tokens": 15,
            "cache_creation_input_tokens": 100,
            "cache_read_input_tokens": 300
          }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(AnthropicResponse.self, from: data).usage?.chatUsage

        XCTAssertEqual(usage?.inputTokens, 420)
        XCTAssertEqual(usage?.outputTokens, 15)
        XCTAssertEqual(usage?.cacheReadInputTokens, 300)
        XCTAssertEqual(usage?.cacheWriteInputTokens, 100)
        XCTAssertEqual(usage?.resolvedTotalTokens, 435)
    }

    func testOpenAIResponsesUsageDecodes() throws {
        let data = """
        {
          "output": [],
          "usage": {
            "input_tokens": 12,
            "output_tokens": 34,
            "total_tokens": 46,
            "input_tokens_details": {"cached_tokens": 6},
            "output_tokens_details": {"reasoning_tokens": 20}
          }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data).usage?.chatUsage

        XCTAssertEqual(usage?.inputTokens, 12)
        XCTAssertEqual(usage?.outputTokens, 34)
        XCTAssertEqual(usage?.totalTokens, 46)
        XCTAssertEqual(usage?.cacheReadInputTokens, 6)
        XCTAssertEqual(usage?.reasoningOutputTokens, 20)
    }

    func testVertexUsageFoldsThoughtsIntoOutput() throws {
        let data = """
        {
          "candidates": [{"content": {"parts": [{"text": "hi"}]}}],
          "usageMetadata": {
            "promptTokenCount": 9,
            "candidatesTokenCount": 11,
            "thoughtsTokenCount": 5,
            "totalTokenCount": 25
          }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(VertexGenerateContentResponse.self, from: data)
            .usageMetadata?
            .chatUsage

        XCTAssertEqual(usage?.inputTokens, 9)
        XCTAssertEqual(usage?.outputTokens, 16)
        XCTAssertEqual(usage?.totalTokens, 25)
        XCTAssertEqual(usage?.reasoningOutputTokens, 5)
    }

    func testMergingPrefersNewerFieldsAndKeepsOlderOnes() {
        let messageStart = ChatUsage(inputTokens: 400, outputTokens: 1)
        let messageDelta = ChatUsage(outputTokens: 220)

        let merged = messageStart.merging(messageDelta)

        XCTAssertEqual(merged.inputTokens, 400)
        XCTAssertEqual(merged.outputTokens, 220)
    }

    func testAddingSumsFieldsAcrossToolRounds() {
        let firstRound = ChatUsage(inputTokens: 100, outputTokens: 30, totalTokens: 130)
        let secondRound = ChatUsage(inputTokens: 150, outputTokens: 60, totalTokens: 210)

        let sum = firstRound.adding(secondRound)

        XCTAssertEqual(sum.inputTokens, 250)
        XCTAssertEqual(sum.outputTokens, 90)
        XCTAssertEqual(sum.totalTokens, 340)
        XCTAssertNil(sum.cacheReadInputTokens)
    }

    func testEstimatedCostUsesManuallyMaintainedPrices() {
        let configuration = AIConfiguration(
            models: [
                AIModelConfiguration(
                    name: "deepseek-v4-pro",
                    inputPricePerMillionTokens: 4,
                    outputPricePerMillionTokens: 16,
                    priceCurrencyCode: "CNY"
                )
            ],
            selectedModel: "deepseek-v4-pro"
        )
        let usage = ChatUsage(
            inputTokens: 500_000,
            outputTokens: 250_000,
            modelName: "deepseek-v4-pro",
            configurationID: configuration.id
        )

        let cost = ChatUsagePricing.estimatedCost(for: usage, in: [configuration])

        XCTAssertEqual(cost?.currencyCode, "CNY")
        XCTAssertEqual(cost?.amount ?? 0, 6, accuracy: 0.000001)
    }

    func testEstimatedCostIsNilWithoutPricing() {
        let configuration = AIConfiguration(
            models: [AIModelConfiguration(name: "deepseek-v4-pro")],
            selectedModel: "deepseek-v4-pro"
        )
        let usage = ChatUsage(
            inputTokens: 1_000,
            outputTokens: 1_000,
            modelName: "deepseek-v4-pro",
            configurationID: configuration.id
        )

        XCTAssertNil(ChatUsagePricing.estimatedCost(for: usage, in: [configuration]))
    }

    func testConversationUsageSummaryAggregatesTokensAndCosts() {
        let configuration = AIConfiguration(
            models: [
                AIModelConfiguration(
                    name: "deepseek-v4-pro",
                    inputPricePerMillionTokens: 2,
                    outputPricePerMillionTokens: 8,
                    priceCurrencyCode: "CNY"
                )
            ],
            selectedModel: "deepseek-v4-pro"
        )
        let usage = ChatUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            modelName: "deepseek-v4-pro",
            configurationID: configuration.id
        )
        let messages = [
            ChatMessage(role: "user", content: "hello"),
            ChatMessage(role: "assistant", content: "hi", usage: usage),
            ChatMessage(role: "assistant", content: "again", usage: usage)
        ]

        let summary = ConversationUsageSummary.summary(of: messages, configurations: [configuration])

        XCTAssertEqual(summary?.inputTokens, 2_000_000)
        XCTAssertEqual(summary?.outputTokens, 1_000_000)
        XCTAssertEqual(summary?.totalTokens, 3_000_000)
        XCTAssertEqual(summary?.costsByCurrency["CNY"] ?? 0, 12, accuracy: 0.000001)
    }

    func testConversationUsageSummaryIsNilWithoutUsage() {
        let messages = [
            ChatMessage(role: "user", content: "hello"),
            ChatMessage(role: "assistant", content: "hi")
        ]

        XCTAssertNil(ConversationUsageSummary.summary(of: messages, configurations: []))
    }

    func testCostTextFormatting() {
        XCTAssertEqual(
            ChatUsageFormatting.costText(ChatUsageCost(amount: 1.234567, currencyCode: "USD")),
            "$1.23"
        )
        XCTAssertEqual(
            ChatUsageFormatting.costText(ChatUsageCost(amount: 0.012345, currencyCode: "CNY")),
            "¥0.0123"
        )
        XCTAssertEqual(
            ChatUsageFormatting.costText(ChatUsageCost(amount: 0.000123, currencyCode: "EUR")),
            "€0.000123"
        )
        XCTAssertEqual(
            ChatUsageFormatting.costText(ChatUsageCost(amount: 0, currencyCode: "USD")),
            "$0.00"
        )
    }

    func testTokenCountTextUsesGroupingSeparators() {
        XCTAssertEqual(
            ChatUsageFormatting.tokenCountText(1_234_567, locale: Locale(identifier: "en_US")),
            "1,234,567"
        )
    }

    func testCostsTextJoinsCurrenciesSorted() {
        let text = ChatUsageFormatting.costsText(["USD": 0.5, "CNY": 1.25])

        XCTAssertEqual(text, "¥1.25 + $0.50")
        XCTAssertNil(ChatUsageFormatting.costsText([:]))
    }
}
