import XCTest
@testable import MewyAI

@MainActor
final class AIServiceToolLoopTests: XCTestCase {
    override func tearDown() {
        MockStreamingURLProtocol.reset()
        super.tearDown()
    }

    func testToolLoopExecutesToolAndStreamsFinalAnswer() async throws {
        MockStreamingURLProtocol.setResponses([
            .eventStream([
                #"{"choices":[{"delta":{"content":"Searching ","tool_calls":[{"index":0,"id":"call_search","function":{"name":"local_search","arguments":""}}]}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#,
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"swift\"}"}}]}}]}"#,
                #"[DONE]"#
            ]),
            .eventStream([
                #"{"choices":[{"delta":{"content":"Final answer"}}],"usage":{"prompt_tokens":4,"completion_tokens":5,"total_tokens":9}}"#,
                #"[DONE]"#
            ])
        ])

        let service = AIService(session: makeMockSession())
        let tool = makeTool(functionName: "local_search")
        let completed = expectation(description: "streaming completed")
        var completedContent = ""
        var completedUsage: ChatUsage?
        var errors = [String]()
        var contentTokens = [String]()
        var toolRequests = [AgentToolCallRequest]()
        var exchangeSnapshots = [[ChatToolExchange]]()
        var toolRoundResetCount = 0

        service.sendStreamingMessage(
            message: "Search first",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            usesImageAttachments: true,
            agentTools: [tool],
            toolExecutor: { request in
                toolRequests.append(request)
                return AgentToolCallResult(content: "tool-result", isError: false)
            },
            onToolExchangesUpdated: { exchanges in
                exchangeSnapshots.append(exchanges)
            },
            onToolRoundReset: {
                toolRoundResetCount += 1
            },
            isReasoningDisplayActive: { false },
            onReasoningToken: { _ in },
            onContentToken: { token in
                contentTokens.append(token)
            },
            onComplete: { content, usage in
                completedContent = content
                completedUsage = usage
                completed.fulfill()
            },
            onError: { error in
                errors.append(error)
            }
        )

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(completedContent, "Final answer")
        XCTAssertEqual(completedUsage?.inputTokens, 7)
        XCTAssertEqual(completedUsage?.outputTokens, 7)
        XCTAssertEqual(completedUsage?.totalTokens, 14)
        XCTAssertEqual(contentTokens.joined(), "Searching Final answer")
        XCTAssertEqual(toolRoundResetCount, 1)
        XCTAssertEqual(toolRequests.count, 1)
        XCTAssertEqual(toolRequests.first?.id, "call_search")
        XCTAssertEqual(toolRequests.first?.functionName, "local_search")
        XCTAssertEqual(toolRequests.first?.argumentsJSON, #"{"query":"swift"}"#)
        XCTAssertEqual(exchangeSnapshots.last?.first?.assistantContent, "Searching ")
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolCalls.first?.name, "local_search")
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolResults.first?.content, "tool-result")
        XCTAssertEqual(MockStreamingURLProtocol.capturedRequestCount, 2)
    }

    func testToolLoopStopsExecutingWhenToolCallLimitIsExceeded() async throws {
        let tooManyToolCalls = (0...AgentTooling.maxToolCalls).map { index in
            #"{"index":\#(index),"id":"call_\#(index)","function":{"name":"limited_tool","arguments":"{}"}}"#
        }.joined(separator: ",")
        MockStreamingURLProtocol.setResponses([
            .eventStream([
                #"{"choices":[{"delta":{"tool_calls":[\#(tooManyToolCalls)]}}]}"#,
                #"[DONE]"#
            ]),
            .eventStream([
                #"{"choices":[{"delta":{"content":"Fallback answer"}}]}"#,
                #"[DONE]"#
            ])
        ])

        let service = AIService(session: makeMockSession())
        let tool = makeTool(functionName: "limited_tool")
        let completed = expectation(description: "streaming completed")
        var completedContent = ""
        var errors = [String]()
        var executedToolCallCount = 0
        var toolRoundResetCount = 0

        service.sendStreamingMessage(
            message: "Trigger many calls",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            usesImageAttachments: true,
            agentTools: [tool],
            toolExecutor: { _ in
                executedToolCallCount += 1
                return AgentToolCallResult(content: "should-not-run", isError: false)
            },
            onToolExchangesUpdated: { _ in },
            onToolRoundReset: {
                toolRoundResetCount += 1
            },
            isReasoningDisplayActive: { false },
            onReasoningToken: { _ in },
            onContentToken: { _ in },
            onComplete: { content, _ in
                completedContent = content
                completed.fulfill()
            },
            onError: { error in
                errors.append(error)
            }
        )

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(completedContent, "Fallback answer")
        XCTAssertEqual(executedToolCallCount, 0)
        XCTAssertEqual(toolRoundResetCount, 1)
        XCTAssertEqual(MockStreamingURLProtocol.capturedRequestCount, 2)
    }

    func testToolLoopStopsRequestingToolsAfterRoundLimit() async throws {
        let toolRoundResponses = (0..<AgentTooling.maxToolRounds).map { round in
            MockStreamingURLProtocol.Response.eventStream([
                #"{"choices":[{"delta":{"content":"Round \#(round) ","tool_calls":[{"index":0,"id":"call_round_\#(round)","function":{"name":"round_tool","arguments":"{}"}}]}}]}"#,
                #"[DONE]"#
            ])
        }
        MockStreamingURLProtocol.setResponses(toolRoundResponses + [
            .eventStream([
                #"{"choices":[{"delta":{"content":"Final after round cap"}}]}"#,
                #"[DONE]"#
            ])
        ])

        let service = AIService(session: makeMockSession())
        let tool = makeTool(functionName: "round_tool")
        let completed = expectation(description: "streaming completed")
        var completedContent = ""
        var errors = [String]()
        var toolRequests = [AgentToolCallRequest]()
        var exchangeSnapshots = [[ChatToolExchange]]()
        var toolRoundResetCount = 0

        service.sendStreamingMessage(
            message: "Keep using tools",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            usesImageAttachments: true,
            agentTools: [tool],
            toolExecutor: { request in
                toolRequests.append(request)
                return AgentToolCallResult(content: "round-result", isError: false)
            },
            onToolExchangesUpdated: { exchanges in
                exchangeSnapshots.append(exchanges)
            },
            onToolRoundReset: {
                toolRoundResetCount += 1
            },
            isReasoningDisplayActive: { false },
            onReasoningToken: { _ in },
            onContentToken: { _ in },
            onComplete: { content, _ in
                completedContent = content
                completed.fulfill()
            },
            onError: { error in
                errors.append(error)
            }
        )

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(completedContent, "Final after round cap")
        XCTAssertEqual(toolRequests.count, AgentTooling.maxToolRounds)
        XCTAssertEqual(toolRequests.map(\.id), (0..<AgentTooling.maxToolRounds).map { "call_round_\($0)" })
        XCTAssertEqual(toolRoundResetCount, AgentTooling.maxToolRounds)
        XCTAssertEqual(exchangeSnapshots.last?.count, AgentTooling.maxToolRounds)
        XCTAssertEqual(MockStreamingURLProtocol.capturedRequestCount, AgentTooling.maxToolRounds + 1)
    }

    func testToolLoopRecordsUnknownToolAsErrorResult() async throws {
        MockStreamingURLProtocol.setResponses([
            .eventStream([
                #"{"choices":[{"delta":{"content":"Trying ","tool_calls":[{"index":0,"id":"call_unknown","function":{"name":"unknown_tool","arguments":"{}"}}]}}]}"#,
                #"[DONE]"#
            ]),
            .eventStream([
                #"{"choices":[{"delta":{"content":"Recovered answer"}}]}"#,
                #"[DONE]"#
            ])
        ])

        let service = AIService(session: makeMockSession())
        let knownTool = makeTool(functionName: "known_tool")
        let completed = expectation(description: "streaming completed")
        var completedContent = ""
        var errors = [String]()
        var executedToolCallCount = 0
        var exchangeSnapshots = [[ChatToolExchange]]()
        var toolRoundResetCount = 0

        service.sendStreamingMessage(
            message: "Call an unavailable tool",
            imageAttachments: [],
            imageContextDescription: "",
            fileAttachments: [],
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil,
            usesImageAttachments: true,
            agentTools: [knownTool],
            toolExecutor: { _ in
                executedToolCallCount += 1
                return AgentToolCallResult(content: "should-not-run", isError: false)
            },
            onToolExchangesUpdated: { exchanges in
                exchangeSnapshots.append(exchanges)
            },
            onToolRoundReset: {
                toolRoundResetCount += 1
            },
            isReasoningDisplayActive: { false },
            onReasoningToken: { _ in },
            onContentToken: { _ in },
            onComplete: { content, _ in
                completedContent = content
                completed.fulfill()
            },
            onError: { error in
                errors.append(error)
            }
        )

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(completedContent, "Recovered answer")
        XCTAssertEqual(executedToolCallCount, 0)
        XCTAssertEqual(toolRoundResetCount, 1)
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolCalls.first?.name, "unknown_tool")
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolResults.first?.toolCallID, "call_unknown")
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolResults.first?.name, "unknown_tool")
        XCTAssertEqual(exchangeSnapshots.last?.first?.toolResults.first?.isError, true)
        XCTAssertTrue(exchangeSnapshots.last?.first?.toolResults.first?.content.contains("unknown_tool") == true)
        XCTAssertEqual(MockStreamingURLProtocol.capturedRequestCount, 2)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockStreamingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTool(functionName: String) -> AgentToolDefinition {
        AgentToolDefinition(
            functionName: functionName,
            displayName: "Local Search",
            description: "Search local data.",
            inputSchema: .object(["type": .string("object")]),
            mcpServerID: UUID(),
            mcpServerName: "Local",
            mcpServerURL: "https://tools.example.com",
            mcpToolName: "search",
            requiresApproval: false,
            authorizationToken: ""
        )
    }
}

private final class MockStreamingURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data

        static func eventStream(_ events: [String], statusCode: Int = 200) -> Response {
            Response(
                statusCode: statusCode,
                body: events
                    .map { "data: \($0)\n\n" }
                    .joined()
                    .data(using: .utf8) ?? Data()
            )
        }
    }

    private static let lock = NSLock()
    private static var responses = [Response]()
    private static var capturedRequests = [URLRequest]()

    static var capturedRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.count
    }

    static func setResponses(_ newResponses: [Response]) {
        lock.lock()
        responses = newResponses
        capturedRequests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses = []
        capturedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let response = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()

        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["content-type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
