import XCTest
@testable import MewyAI

@MainActor
final class ChatAuxiliaryAIServiceTests: XCTestCase {
    override func tearDown() {
        MockAuxiliaryURLProtocol.reset()
        super.tearDown()
    }

    func testGenerateConversationTitleUsesAuxiliaryRequestAndSanitizesResponse() async throws {
        MockAuxiliaryURLProtocol.setResponses([
            .json(#"{"choices":[{"message":{"content":"\"SwiftUI Debugging\""}}]}"#)
        ])

        let service = ChatAuxiliaryAIService(session: makeMockSession())
        let completed = expectation(description: "title generated")
        var title: String?

        service.generateConversationTitle(
            messages: [
                ChatMessage(role: "user", content: "SwiftUI toolbar title is wrong"),
                ChatMessage(role: "assistant", content: "Check navigation title placement.")
            ],
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil
        ) { generatedTitle in
            title = generatedTitle
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(title, "SwiftUI Debugging")
        XCTAssertEqual(MockAuxiliaryURLProtocol.capturedRequestCount, 1)
        XCTAssertEqual(MockAuxiliaryURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testExtractMemoryUpdatesParsesAuxiliaryResponse() async throws {
        MockAuxiliaryURLProtocol.setResponses([
            .json(#"{"choices":[{"message":{"content":"{\"operations\":[{\"action\":\"add\",\"content\":\"User prefers SwiftUI\"}]}"}}]}"#)
        ])

        let service = ChatAuxiliaryAIService(session: makeMockSession())
        let completed = expectation(description: "memory updates extracted")
        var operations: [ChatMemoryOperation]?

        service.extractMemoryUpdates(
            memoryEntries: [ChatMemoryEntry(content: "User works on iOS apps")],
            userText: "Remember that I prefer SwiftUI.",
            assistantText: "Got it.",
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil
        ) { extractedOperations in
            operations = extractedOperations
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(operations, [
            ChatMemoryOperation(action: .add, index: nil, content: "User prefers SwiftUI")
        ])
        XCTAssertEqual(MockAuxiliaryURLProtocol.capturedRequestCount, 1)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAuxiliaryURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockAuxiliaryURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data

        static func json(_ body: String, statusCode: Int = 200) -> Response {
            Response(
                statusCode: statusCode,
                body: body.data(using: .utf8) ?? Data()
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

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.last
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
            headerFields: ["content-type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
