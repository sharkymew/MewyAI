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

    func testAnthropicOneMillionContextKeepsManagedBetaHeader() {
        let request = AIProviderRequestFactory.makeRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiFormat: .anthropicMessages,
            model: "claude-sonnet-4 [1m]",
            apiKey: "anthropic-key",
            customHeaders: """
            anthropic-beta: custom-beta
            X-Extra: extra
            """,
            acceptsEventStream: false
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Extra"), "extra")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "custom-beta")
        XCTAssertTrue(request.value(forHTTPHeaderField: "anthropic-beta")?.contains("context-1m-2025-08-07") == true)
    }

    func testAnthropicClaudeCodeImpersonationIgnoresManagedCustomHeaders() {
        let request = AIProviderRequestFactory.makeRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiFormat: .anthropicMessages,
            model: "claude-sonnet-4",
            apiKey: "anthropic-key",
            customHeaders: """
            authorization: Bearer custom
            anthropic-beta: custom-beta
            user-agent: custom-agent
            x-stainless-runtime: custom-runtime
            X-Extra: extra
            """,
            acceptsEventStream: true,
            anthropicClaudeCodeImpersonationEnabled: true
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-dangerous-direct-browser-access"), "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-app"), "cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Extra"), "extra")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "custom-beta")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "user-agent"), "custom-agent")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-stainless-runtime"), "custom-runtime")
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

    func testAnthropicOneMillionContextURLAddsBetaQuery() throws {
        let url = try AIProviderRequestFactory.requestURL(
            from: "https://api.anthropic.com/v1/messages",
            apiFormat: .anthropicMessages,
            model: "claude-sonnet-4 [1m]",
            apiKey: "",
            isStreaming: false
        )

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "beta" })?.value, "true")
    }
}
