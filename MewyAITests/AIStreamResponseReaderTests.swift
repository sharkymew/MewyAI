import XCTest
@testable import MewyAI

@MainActor
final class AIStreamResponseReaderTests: XCTestCase {
    override func tearDown() {
        StreamReaderMockURLProtocol.reset()
        super.tearDown()
    }

    func testReadsEventStreamAndFlushesTokensAndUsage() async throws {
        StreamReaderMockURLProtocol.setResponse(.eventStream([
            #"{"choices":[{"delta":{"reasoning_content":"think","content":"Hello "}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#,
            #"{"choices":[{"delta":{"content":"world"}}],"usage":{"prompt_tokens":4,"completion_tokens":5,"total_tokens":9}}"#,
            #"[DONE]"#
        ]))

        var reasoningTokens = [String]()
        var contentTokens = [String]()
        var errors = [String]()

        let response = await AIStreamResponseReader.read(
            session: makeMockSession(),
            request: makeRequest(),
            apiFormat: .openAIChatCompletions,
            redactionValues: [],
            maxContentCharacters: 1_000,
            maxReasoningCharacters: 1_000,
            isReasoningDisplayActive: { true },
            onReasoningToken: { reasoningTokens.append($0) },
            onContentToken: { contentTokens.append($0) },
            onError: { errors.append($0) },
            errorMessage: { statusCode, body, _, _ in
                "status \(statusCode ?? -1): \(body)"
            },
            sanitizedErrorBody: { body, _ in body }
        )

        let streamedResponse = try XCTUnwrap(response)
        XCTAssertEqual(streamedResponse.reasoningContent, "think")
        XCTAssertEqual(streamedResponse.content, "Hello world")
        XCTAssertEqual(streamedResponse.usage?.inputTokens, 7)
        XCTAssertEqual(streamedResponse.usage?.outputTokens, 7)
        XCTAssertEqual(streamedResponse.usage?.totalTokens, 14)
        XCTAssertEqual(reasoningTokens.joined(), "think")
        XCTAssertEqual(contentTokens.joined(), "Hello world")
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(StreamReaderMockURLProtocol.capturedRequestCount, 1)
    }

    func testStopsWithErrorWhenContentLimitIsExceeded() async {
        StreamReaderMockURLProtocol.setResponse(.eventStream([
            #"{"choices":[{"delta":{"content":"too long"}}]}"#,
            #"[DONE]"#
        ]))

        var contentTokens = [String]()
        var errors = [String]()

        let response = await AIStreamResponseReader.read(
            session: makeMockSession(),
            request: makeRequest(),
            apiFormat: .openAIChatCompletions,
            redactionValues: [],
            maxContentCharacters: 4,
            maxReasoningCharacters: 1_000,
            isReasoningDisplayActive: { false },
            onReasoningToken: { _ in },
            onContentToken: { contentTokens.append($0) },
            onError: { errors.append($0) },
            errorMessage: { statusCode, body, _, _ in
                "status \(statusCode ?? -1): \(body)"
            },
            sanitizedErrorBody: { body, _ in body }
        )

        XCTAssertNil(response)
        XCTAssertTrue(contentTokens.isEmpty)
        XCTAssertEqual(errors.count, 1)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamReaderMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!)
    }
}

private final class StreamReaderMockURLProtocol: URLProtocol {
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
    private static var response: Response?
    private static var capturedRequests = [URLRequest]()

    static var capturedRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.count
    }

    static func setResponse(_ newResponse: Response) {
        lock.lock()
        response = newResponse
        capturedRequests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        response = nil
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
        let response = Self.response
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
