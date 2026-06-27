import XCTest
@testable import MewyAI

@MainActor
final class AIProviderRequestFactoryTests: XCTestCase {
    func testOpenAIRequestUsesBearerAuthorizationAndEventStreamAccept() {
        let request = AIProviderRequestFactory.makeRequest(
            url: URL(string: "https://api.example.com/v1/chat/completions")!,
            apiFormat: .openAIChatCompletions,
            model: "gpt-5",
            apiKey: " sk-test ",
            customHeaders: "X-Trace-ID: trace-1",
            acceptsEventStream: true
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace-ID"), "trace-1")
    }

    func testAnthropicRequestUsesAPIKeyAndDoesNotAddManagedBetaHeaders() {
        let betaHeader = "anthropic" + "-beta"
        let modelName = "claude-sonnet-4 " + "[1" + "m]"
        let request = AIProviderRequestFactory.makeRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiFormat: .anthropicMessages,
            model: modelName,
            apiKey: "anthropic-key",
            customHeaders: """
            \(betaHeader): custom-beta
            X-Extra: extra
            """,
            acceptsEventStream: false
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Extra"), "extra")
        XCTAssertEqual(request.value(forHTTPHeaderField: betaHeader), "custom-beta")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAnthropicRequestDoesNotAddImpersonationHeaders() {
        let dangerousHeader = "anthropic-dangerous" + "-direct-browser-access"
        let stainlessRuntimeHeader = "x" + "-stainless-runtime"
        let appHeader = "x" + "-app"
        let request = AIProviderRequestFactory.makeRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiFormat: .anthropicMessages,
            model: "claude-sonnet-4",
            apiKey: "anthropic-key",
            customHeaders: """
            authorization: Bearer custom
            user-agent: custom-agent
            \(stainlessRuntimeHeader): custom-runtime
            X-Extra: extra
            """,
            acceptsEventStream: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNil(request.value(forHTTPHeaderField: dangerousHeader))
        XCTAssertNil(request.value(forHTTPHeaderField: appHeader))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Extra"), "extra")
        XCTAssertEqual(request.value(forHTTPHeaderField: "user-agent"), "custom-agent")
        XCTAssertEqual(request.value(forHTTPHeaderField: stainlessRuntimeHeader), "custom-runtime")
    }

    func testVertexStreamingURLInjectsModelKeyAndSSEQueryItems() throws {
        let url = try AIProviderRequestFactory.requestURL(
            from: "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
            apiFormat: .vertexAIExpress,
            model: "gemini-2.5-pro",
            apiKey: "vertex-key",
            isStreaming: true
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1beta/models/gemini-2.5-pro:streamGenerateContent")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "key" })?.value, "vertex-key")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "alt" })?.value, "sse")
    }

    func testAnthropicURLDoesNotAddBetaQuery() throws {
        let modelName = "claude-sonnet-4 " + "[1" + "m]"
        let url = try AIProviderRequestFactory.requestURL(
            from: "https://api.anthropic.com/v1/messages",
            apiFormat: .anthropicMessages,
            model: modelName,
            apiKey: "",
            isStreaming: false
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "beta" }))
    }
}
