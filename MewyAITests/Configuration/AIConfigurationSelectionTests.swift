import XCTest
@testable import MewyAI

@MainActor
final class AIConfigurationSelectionTests: XCTestCase {
    func testSelectModelAppendsUnknownModelAndRequestsImageClear() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var configurations = [
            AIConfiguration(
                id: id,
                models: [AIModelConfiguration(name: "image-model", supportsImages: true)],
                selectedModel: "image-model",
                updatedAt: .distantPast
            )
        ]

        let result = AIConfigurationSelection.selectModel(
            "text-model",
            currentConfigurationID: id,
            configurations: &configurations,
            now: now
        )

        XCTAssertEqual(result, .init(configurationID: id, shouldClearImages: true))
        XCTAssertEqual(configurations[0].selectedModel, "text-model")
        XCTAssertTrue(configurations[0].models.contains { $0.name == "text-model" })
        XCTAssertEqual(configurations[0].updatedAt, now)
    }

    func testSelectModelKeepsImagesWhenSelectedModelSupportsImages() {
        let id = UUID()
        var configurations = [
            AIConfiguration(
                id: id,
                models: [AIModelConfiguration(name: "image-model", supportsImages: true)],
                selectedModel: "text-model"
            )
        ]

        let result = AIConfigurationSelection.selectModel(
            "image-model",
            currentConfigurationID: id,
            configurations: &configurations
        )

        XCTAssertEqual(result, .init(configurationID: id, shouldClearImages: false))
        XCTAssertEqual(configurations[0].selectedModel, "image-model")
    }

    func testSelectReasoningEffortEnablesReasoning() {
        let id = UUID()
        var configurations = [
            AIConfiguration(id: id, reasoningEnabled: false, reasoningEffort: .low)
        ]

        let result = AIConfigurationSelection.selectReasoningEffort(
            .high,
            currentConfigurationID: id,
            configurations: &configurations
        )

        XCTAssertEqual(result, .init(configurationID: id, shouldClearImages: false))
        XCTAssertTrue(configurations[0].reasoningEnabled)
        XCTAssertEqual(configurations[0].reasoningEffort, .high)
    }

    func testSetReasoningEnabledOnlyTogglesReasoningFlag() {
        let id = UUID()
        var configurations = [
            AIConfiguration(id: id, reasoningEnabled: true, reasoningEffort: .max)
        ]

        let result = AIConfigurationSelection.setReasoningEnabled(
            false,
            currentConfigurationID: id,
            configurations: &configurations
        )

        XCTAssertEqual(result, .init(configurationID: id, shouldClearImages: false))
        XCTAssertFalse(configurations[0].reasoningEnabled)
        XCTAssertEqual(configurations[0].reasoningEffort, .max)
    }

    func testMissingConfigurationDoesNotMutate() {
        let id = UUID()
        var configurations = [AIConfiguration(id: id, selectedModel: "model-a")]

        let result = AIConfigurationSelection.selectModel(
            "model-b",
            currentConfigurationID: UUID(),
            configurations: &configurations
        )

        XCTAssertNil(result)
        XCTAssertEqual(configurations[0].selectedModel, "model-a")
    }

    func testSelectBuiltInDefaultPromptUpdatesCurrentConfiguration() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_001)
        var configurations = [
            AIConfiguration(
                id: id,
                systemPrompt: "custom",
                updatedAt: .distantPast
            )
        ]
        var promptPresets = [
            AIPromptPreset(name: "Custom", content: "custom")
        ]

        let result = AIConfigurationSelection.selectBuiltInDefaultPrompt(
            currentConfigurationID: id,
            configurations: &configurations,
            promptPresets: &promptPresets,
            now: now
        )

        XCTAssertEqual(result.configurationID, id)
        XCTAssertEqual(result.configuration.systemPrompt, AIConfiguration.defaultSystemPrompt)
        XCTAssertEqual(configurations[0].systemPrompt, AIConfiguration.defaultSystemPrompt)
        XCTAssertEqual(configurations[0].updatedAt, now)
        XCTAssertEqual(promptPresets.first?.content, AIConfiguration.defaultSystemPrompt)
    }

    func testLegacyConfigurationDecodesWithoutEmbeddingConfiguration() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","baseURL":"https://example.com","endpoint":"chat/completions"}"#.utf8)

        let configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertNil(configuration.embeddingConfiguration)
    }

    func testEmbeddingConfigurationRoundTripsModelSettings() throws {
        let embedding = AIEmbeddingConfiguration(
            apiFormat: .geminiEmbedContent,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            endpoint: "models/{model}:embedContent",
            models: [
                AIEmbeddingModelConfiguration(
                    name: "gemini-embedding-001",
                    alias: "Gemini Embed",
                    outputDimensions: 768,
                    queryPrefix: "query: ",
                    documentPrefix: "document: ",
                    validatedDimensions: 768,
                    lastValidatedAt: Date(timeIntervalSince1970: 1)
                )
            ]
        )
        let configuration = AIConfiguration(embeddingConfiguration: embedding)

        let decoded = try JSONDecoder().decode(
            AIConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.embeddingConfiguration, embedding)
    }
}
