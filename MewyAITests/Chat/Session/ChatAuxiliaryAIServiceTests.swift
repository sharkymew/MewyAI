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

    func testSummarizeMemoryHistoryBatchUsesHistoryPromptAndParsesResponse() async throws {
        MockAuxiliaryURLProtocol.setResponses([
            .json(#"{"choices":[{"message":{"content":"{\"summary\":\"Batch mentions SwiftUI.\",\"facts\":[\"User prefers SwiftUI-native UI fixes.\"]}"}}]}"#)
        ])

        let service = ChatAuxiliaryAIService(session: makeMockSession())
        let completed = expectation(description: "history batch summarized")
        var summary: ChatMemoryHistoryBatchSummary?
        let batch = ChatMemoryHistoryBatch(
            index: 1,
            text: """
            <conversation title="Planning">
            user: I prefer SwiftUI-native UI fixes.
            assistant: Noted.
            </conversation>
            """,
            conversationCount: 1,
            segmentCount: 1
        )

        service.summarizeMemoryHistoryBatch(
            memoryEntries: [ChatMemoryEntry(content: "User works on iOS apps")],
            batch: batch,
            batchCount: 2,
            baseURL: AIAPIFormat.openAIChatCompletions.defaultBaseURL,
            apiFormat: .openAIChatCompletions,
            apiKey: "test-key",
            customHeaders: "",
            model: "gpt-test",
            modelParameters: nil,
            anthropicMaxTokens: 4096,
            reasoningEnabled: nil,
            reasoningEffort: nil
        ) { batchSummary in
            summary = batchSummary
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(summary, ChatMemoryHistoryBatchSummary(
            batchIndex: 1,
            summary: "Batch mentions SwiftUI.",
            facts: ["User prefers SwiftUI-native UI fixes."]
        ))
        let body = try XCTUnwrap(lastRequestBodyString())
        XCTAssertTrue(body.contains("I prefer SwiftUI-native UI fixes."))
        XCTAssertTrue(body.contains("User works on iOS apps"))
        XCTAssertEqual(MockAuxiliaryURLProtocol.capturedRequestCount, 1)
    }

    func testMergeMemoryHistorySummariesUsesBatchSummariesAndParsesResult() async throws {
        MockAuxiliaryURLProtocol.setResponses([
            .json(#"{"choices":[{"message":{"content":"{\"sections\":[{\"title\":\"Preferences\",\"body\":\"User prefers SwiftUI-native fixes.\"}],\"operations\":[{\"action\":\"add\",\"content\":\"User prefers SwiftUI-native UI fixes.\"}]}"}}]}"#)
        ])

        let service = ChatAuxiliaryAIService(session: makeMockSession())
        let completed = expectation(description: "history summaries merged")
        var result: ChatMemoryHistorySummaryResult?

        service.mergeMemoryHistorySummaries(
            memoryEntries: [ChatMemoryEntry(content: "User works on iOS apps")],
            batchSummaries: [
                ChatMemoryHistoryBatchSummary(
                    batchIndex: 1,
                    summary: "Batch mentions SwiftUI.",
                    facts: ["User prefers SwiftUI-native UI fixes."]
                )
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
        ) { mergedResult in
            result = mergedResult
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(result?.sections, [
            ChatMemorySummarySection(title: "Preferences", body: "User prefers SwiftUI-native fixes.")
        ])
        XCTAssertEqual(result?.operations, [
            ChatMemoryOperation(action: .add, index: nil, content: "User prefers SwiftUI-native UI fixes.")
        ])
        let body = try XCTUnwrap(lastRequestBodyString())
        XCTAssertTrue(body.contains("Batch mentions SwiftUI."))
        XCTAssertTrue(body.contains("User works on iOS apps"))
        XCTAssertEqual(MockAuxiliaryURLProtocol.capturedRequestCount, 1)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAuxiliaryURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func lastRequestBodyString() -> String? {
        guard let data = MockAuxiliaryURLProtocol.lastRequestBody else {
            return nil
        }

        return String(data: data, encoding: .utf8)
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
    private static var capturedRequestBodies = [Data?]()

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

    static var lastRequestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequestBodies.last ?? nil
    }

    static func setResponses(_ newResponses: [Response]) {
        lock.lock()
        responses = newResponses
        capturedRequests = []
        capturedRequestBodies = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses = []
        capturedRequests = []
        capturedRequestBodies = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestBody = Self.bodyData(from: request)

        Self.lock.lock()
        Self.capturedRequests.append(request)
        Self.capturedRequestBodies.append(requestBody)
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

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }
        return data
    }
}
