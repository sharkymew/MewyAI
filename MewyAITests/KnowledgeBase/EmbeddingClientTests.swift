import XCTest
@testable import MewyAI

@MainActor
final class EmbeddingClientTests: XCTestCase {
    override func tearDown() {
        EmbeddingMockURLProtocol.reset()
        super.tearDown()
    }

    func testOpenAICompatiblePreservesBatchOrderAndNormalizesVectors() async throws {
        EmbeddingMockURLProtocol.setResponses([
            .json(#"{"data":[{"index":1,"embedding":[0,2]},{"index":0,"embedding":[3,4]}]}"#)
        ])
        let client = EmbeddingClient(session: makeSession())

        let vectors = try await client.embed(
            ["first", "second"],
            purpose: .query,
            profile: profile(format: .openAICompatible, endpoint: "embeddings"),
            credentials: EmbeddingCredentials(apiKey: "test-key", customHeaders: "")
        )

        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0][0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(vectors[0][1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(vectors[1], [0, 1])
        XCTAssertEqual(
            EmbeddingMockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-key"
        )
    }

    func testOpenAICompatibleRejectsZeroAndInconsistentVectors() async {
        EmbeddingMockURLProtocol.setResponses([
            .json(#"{"data":[{"index":0,"embedding":[0,0]}]}"#),
            .json(#"{"data":[{"index":0,"embedding":[1,0]},{"index":1,"embedding":[1,0,0]}]}"#)
        ])
        let client = EmbeddingClient(session: makeSession())

        do {
            _ = try await client.embed(
                ["zero"],
                purpose: .query,
                profile: profile(),
                credentials: .init(apiKey: "", customHeaders: "")
            )
            XCTFail("Expected a zero vector to be rejected")
        } catch {
            XCTAssertEqual(error as? EmbeddingClientError, .invalidVector)
        }

        do {
            _ = try await client.embed(
                ["one", "two"],
                purpose: .query,
                profile: profile(),
                credentials: .init(apiKey: "", customHeaders: "")
            )
            XCTFail("Expected inconsistent dimensions to be rejected")
        } catch {
            XCTAssertEqual(error as? EmbeddingClientError, .inconsistentDimensions)
        }
    }

    func testRetries429AndServerErrorsUpToSuccess() async throws {
        EmbeddingMockURLProtocol.setResponses([
            .json("{}", statusCode: 500),
            .json("{}", statusCode: 429, headers: ["Retry-After": "0"]),
            .json(#"{"data":[{"index":0,"embedding":[1,0]}]}"#)
        ])
        let client = EmbeddingClient(session: makeSession())

        _ = try await client.embed(
            ["retry"],
            purpose: .query,
            profile: profile(),
            credentials: .init(apiKey: "", customHeaders: "")
        )

        XCTAssertEqual(EmbeddingMockURLProtocol.capturedRequestCount, 3)
    }

    func testGeminiUsesBatchEndpointRetrievalTaskAndOutputDimensions() async throws {
        EmbeddingMockURLProtocol.setResponses([
            .json(#"{"embeddings":[{"values":[1,0]},{"values":[0,2]}]}"#)
        ])
        let client = EmbeddingClient(session: makeSession())

        let vectors = try await client.embed(
            ["a", "b"],
            purpose: .document(title: "Doc"),
            profile: profile(
                format: .geminiEmbedContent,
                endpoint: "models/{model}:embedContent",
                outputDimensions: 2
            ),
            credentials: .init(apiKey: "gemini-key", customHeaders: "")
        )

        XCTAssertEqual(vectors, [[1, 0], [0, 1]])
        XCTAssertTrue(EmbeddingMockURLProtocol.lastRequest?.url?.path.hasSuffix(":batchEmbedContents") == true)
        XCTAssertEqual(
            EmbeddingMockURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-goog-api-key"),
            "gemini-key"
        )
        let body = String(data: EmbeddingMockURLProtocol.lastRequestBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("RETRIEVAL_DOCUMENT"))
        XCTAssertTrue(body.contains("outputDimensionality"))
    }

    func testVertexPredictParsesPredictions() async throws {
        EmbeddingMockURLProtocol.setResponses([
            .json(#"{"predictions":[{"embeddings":{"values":[3,4]}},{"embeddings":{"values":[0,2]}}]}"#)
        ])
        let client = EmbeddingClient(session: makeSession())

        let vectors = try await client.embed(
            ["a", "b"],
            purpose: .query,
            profile: profile(format: .vertexPredict, endpoint: "v1/models/{model}:predict"),
            credentials: .init(apiKey: "vertex-key", customHeaders: "")
        )

        XCTAssertEqual(vectors[0][0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(vectors[0][1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(vectors[1], [0, 1])
        XCTAssertEqual(EmbeddingMockURLProtocol.lastRequest?.url?.query, "key=vertex-key")
    }

    func testDiscoveryUsesProviderSpecificEndpointsAndFiltersCapabilities() async throws {
        EmbeddingMockURLProtocol.setResponses([
            .json(#"{"data":[{"id":"openai/text-embedding-3-small"},{"id":"chat-only"}]}"#),
            .json(#"{"data":[{"id":"BAAI/bge-m3"}]}"#),
            .json(#"{"models":[{"name":"models/gemini-embedding-001","supportedGenerationMethods":["embedContent"]},{"name":"models/gemini-chat","supportedGenerationMethods":["generateContent"]}]}"#),
            .json(#"{"data":[{"id":"chat-only"},{"id":"Qwen/Qwen3-Embedding-4B"},{"id":"custom-vector-model","architecture":{"output_modalities":["embeddings"]}}]}"#)
        ])
        let session = makeSession()

        let openRouter = try await EmbeddingModelDiscoveryService.discover(
            embeddingConfiguration: .init(baseURL: "https://openrouter.ai/api/v1"),
            credentials: .init(apiKey: "", customHeaders: ""),
            session: session
        )
        XCTAssertEqual(openRouter.map(\.name), ["chat-only", "openai/text-embedding-3-small"])
        XCTAssertTrue(EmbeddingMockURLProtocol.capturedRequests[0].url?.path.hasSuffix("/embeddings/models") == true)

        let siliconFlow = try await EmbeddingModelDiscoveryService.discover(
            embeddingConfiguration: .init(baseURL: "https://api.siliconflow.cn/v1"),
            credentials: .init(apiKey: "", customHeaders: ""),
            session: session
        )
        XCTAssertEqual(siliconFlow.map(\.name), ["BAAI/bge-m3"])
        XCTAssertEqual(EmbeddingMockURLProtocol.capturedRequests[1].url?.query, "sub_type=embedding")

        let gemini = try await EmbeddingModelDiscoveryService.discover(
            embeddingConfiguration: .init(
                apiFormat: .geminiEmbedContent,
                baseURL: "https://generativelanguage.googleapis.com/v1beta"
            ),
            credentials: .init(apiKey: "", customHeaders: ""),
            session: session
        )
        XCTAssertEqual(gemini.map(\.name), ["gemini-embedding-001"])

        let generic = try await EmbeddingModelDiscoveryService.discover(
            embeddingConfiguration: .init(baseURL: "https://provider.example.com/v1"),
            credentials: .init(apiKey: "", customHeaders: ""),
            session: session
        )
        XCTAssertEqual(generic.map(\.name), ["custom-vector-model", "Qwen/Qwen3-Embedding-4B"])
    }

    func testCancellationCancelsPendingRequest() async {
        EmbeddingMockURLProtocol.setResponses([.delayedSuccess(seconds: 2)])
        let client = EmbeddingClient(session: makeSession())
        let task = Task {
            try await client.embed(
                ["cancel"],
                purpose: .query,
                profile: profile(),
                credentials: .init(apiKey: "", customHeaders: "")
            )
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbeddingMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func profile(
        format: EmbeddingAPIFormat = .openAICompatible,
        endpoint: String = "embeddings",
        outputDimensions: Int? = nil
    ) -> EmbeddingProfileSnapshot {
        EmbeddingProfileSnapshot(
            providerConfigurationID: UUID(),
            embeddingConfiguration: AIEmbeddingConfiguration(
                apiFormat: format,
                baseURL: "https://embedding.example.com/v1",
                endpoint: endpoint
            ),
            model: AIEmbeddingModelConfiguration(
                name: "embedding-model",
                outputDimensions: outputDimensions
            ),
            vectorDimensions: outputDimensions ?? 2
        )
    }
}

private final class EmbeddingMockURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
        var delay: TimeInterval

        static func json(
            _ body: String,
            statusCode: Int = 200,
            headers: [String: String] = [:]
        ) -> Response {
            Response(
                statusCode: statusCode,
                headers: headers,
                body: Data(body.utf8),
                delay: 0
            )
        }

        static func delayedSuccess(seconds: TimeInterval) -> Response {
            var response = json(#"{"data":[{"index":0,"embedding":[1,0]}]}"#)
            response.delay = seconds
            return response
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses = [Response]()
    private nonisolated(unsafe) static var requests = [URLRequest]()
    private nonisolated(unsafe) static var requestBodies = [Data?]()
    private var workItem: DispatchWorkItem?

    static var capturedRequestCount: Int {
        lock.withLock { requests.count }
    }

    static var capturedRequests: [URLRequest] {
        lock.withLock { requests }
    }

    static var lastRequest: URLRequest? {
        lock.withLock { requests.last }
    }

    static var lastRequestBody: Data? {
        lock.withLock { requestBodies.last ?? nil }
    }

    static func setResponses(_ value: [Response]) {
        lock.withLock {
            responses = value
            requests = []
            requestBodies = []
        }
    }

    static func reset() {
        setResponses([])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        let response = Self.lock.withLock { () -> Response? in
            Self.requests.append(request)
            Self.requestBodies.append(body)
            return Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        }
        guard let response,
              let url = request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.workItem = workItem
        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: workItem)
        } else {
            workItem.perform()
        }
    }

    override func stopLoading() {
        workItem?.cancel()
        workItem = nil
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
