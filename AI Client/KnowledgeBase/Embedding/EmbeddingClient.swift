import Foundation

nonisolated struct EmbeddingCredentials: Equatable {
    var apiKey: String
    var customHeaders: String
}

nonisolated enum EmbeddingPurpose {
    case document(title: String)
    case query
}

nonisolated enum EmbeddingClientError: LocalizedError, Equatable {
    case invalidConfiguration
    case emptyInput
    case requestFailed(Int)
    case invalidResponse
    case invalidVector
    case inconsistentDimensions

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Embedding Provider 配置无效。"
        case .emptyInput:
            return "Embedding 输入不能为空。"
        case .requestFailed(let statusCode):
            return "Embedding 请求失败（HTTP \(statusCode)）。"
        case .invalidResponse:
            return "Embedding Provider 返回了无法解析的响应。"
        case .invalidVector:
            return "Embedding Provider 返回了无效向量。"
        case .inconsistentDimensions:
            return "Embedding Provider 返回的向量维度不一致。"
        }
    }
}

nonisolated private enum EmbeddingCredentialFailureMode: Equatable, Sendable {
    case legacy
    case singleKey
    case multipleKeys
}

nonisolated private func providerAPIFormat(for embeddingAPIFormat: EmbeddingAPIFormat) -> AIAPIFormat {
    switch embeddingAPIFormat {
    case .openAICompatible:
        return .openAIChatCompletions
    case .geminiEmbedContent, .vertexPredict:
        // Both Google embedding APIs use the same structured credential-error signals.
        return .vertexAIExpress
    }
}

nonisolated private func boundedResponseBody(from data: Data) -> String {
    String(decoding: data.prefix(64 * 1024), as: UTF8.self)
}

actor EmbeddingClient {
    private let session: URLSession

    init(session: URLSession = AIService.makeSecureSession()) {
        self.session = session
    }

    func embed(
        _ texts: [String],
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials
    ) async throws -> [[Float]] {
        try await embed(
            texts,
            purpose: purpose,
            profile: profile,
            credentials: credentials,
            credentialFailureMode: .legacy
        )
    }

    func embed(
        _ texts: [String],
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String
    ) async throws -> [[Float]] {
        let configuredKeyCount = credentialSet.credentials.filter { $0.keyID != nil }.count
        let credentialFailureMode: EmbeddingCredentialFailureMode
        switch configuredKeyCount {
        case 0:
            credentialFailureMode = .legacy
        case 1:
            credentialFailureMode = .singleKey
        default:
            credentialFailureMode = .multipleKeys
        }

        return try await AIProviderFailoverExecutor().execute(
            credentialSet: credentialSet,
            customHeaders: customHeaders
        ) { credential in
            try await self.embed(
                texts,
                purpose: purpose,
                profile: profile,
                credentials: EmbeddingCredentials(
                    apiKey: credential.secret,
                    customHeaders: customHeaders
                ),
                credentialFailureMode: credentialFailureMode
            )
        }
    }

    private func embed(
        _ texts: [String],
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials,
        credentialFailureMode: EmbeddingCredentialFailureMode
    ) async throws -> [[Float]] {
        let preparedTexts = texts.map { prepare($0, purpose: purpose, profile: profile) }
        guard !preparedTexts.isEmpty, preparedTexts.allSatisfy({ !$0.isEmpty }) else {
            throw EmbeddingClientError.emptyInput
        }

        let vectors: [[Float]]
        switch profile.apiFormat {
        case .openAICompatible:
            vectors = try await requestOpenAICompatible(
                texts: preparedTexts,
                profile: profile,
                credentials: credentials,
                credentialFailureMode: credentialFailureMode
            )
        case .geminiEmbedContent:
            vectors = try await requestGemini(
                texts: preparedTexts,
                purpose: purpose,
                profile: profile,
                credentials: credentials,
                credentialFailureMode: credentialFailureMode
            )
        case .vertexPredict:
            vectors = try await requestVertex(
                texts: preparedTexts,
                profile: profile,
                credentials: credentials,
                credentialFailureMode: credentialFailureMode
            )
        }

        return try normalized(vectors, expectedCount: texts.count)
    }

    private func prepare(
        _ text: String,
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch purpose {
        case .query:
            return profile.queryPrefix + trimmed
        case .document:
            return profile.documentPrefix + trimmed
        }
    }

    private func requestOpenAICompatible(
        texts: [String],
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials,
        credentialFailureMode: EmbeddingCredentialFailureMode
    ) async throws -> [[Float]] {
        var body: [String: Any] = [
            "model": profile.model,
            "input": texts
        ]
        if let outputDimensions = profile.outputDimensions {
            body["dimensions"] = outputDimensions
        }

        let data = try await perform(
            request: try makeRequest(
                profile: profile,
                credentials: credentials,
                body: body,
                placesKeyInQuery: false
            ),
            apiFormat: profile.apiFormat,
            credentialFailureMode: credentialFailureMode
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            throw EmbeddingClientError.invalidResponse
        }

        return try items
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .map { try vector(from: $0["embedding"]) }
    }

    private func requestGemini(
        texts: [String],
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials,
        credentialFailureMode: EmbeddingCredentialFailureMode
    ) async throws -> [[Float]] {
        if texts.count > 1, profile.endpoint.contains(":embedContent") {
            var batchProfile = profile
            batchProfile.endpoint = profile.endpoint.replacingOccurrences(
                of: ":embedContent",
                with: ":batchEmbedContents"
            )
            let body: [String: Any] = [
                "requests": texts.map {
                    geminiRequestBody(text: $0, purpose: purpose, profile: profile)
                }
            ]
            let data = try await perform(
                request: try makeRequest(
                    profile: batchProfile,
                    credentials: credentials,
                    body: body,
                    placesKeyInQuery: false,
                    apiKeyHeader: "x-goog-api-key"
                ),
                apiFormat: profile.apiFormat,
                credentialFailureMode: credentialFailureMode
            )
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let embeddings = root["embeddings"] as? [[String: Any]] else {
                throw EmbeddingClientError.invalidResponse
            }
            return try embeddings.map { try vector(from: $0["values"]) }
        }

        var vectors = [[Float]]()
        vectors.reserveCapacity(texts.count)

        for text in texts {
            let data = try await perform(
                request: try makeRequest(
                    profile: profile,
                    credentials: credentials,
                    body: geminiRequestBody(text: text, purpose: purpose, profile: profile),
                    placesKeyInQuery: false,
                    apiKeyHeader: "x-goog-api-key"
                ),
                apiFormat: profile.apiFormat,
                credentialFailureMode: credentialFailureMode
            )
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let embedding = root["embedding"] as? [String: Any] else {
                throw EmbeddingClientError.invalidResponse
            }
            vectors.append(try vector(from: embedding["values"]))
        }
        return vectors
    }

    private func geminiRequestBody(
        text: String,
        purpose: EmbeddingPurpose,
        profile: EmbeddingProfileSnapshot
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": "models/\(profile.model)",
            "content": ["parts": [["text": text]]],
            "taskType": {
                switch purpose {
                case .query:
                    return "RETRIEVAL_QUERY"
                case .document:
                    return "RETRIEVAL_DOCUMENT"
                }
            }()
        ]
        if let outputDimensions = profile.outputDimensions {
            body["outputDimensionality"] = outputDimensions
        }
        return body
    }

    private func requestVertex(
        texts: [String],
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials,
        credentialFailureMode: EmbeddingCredentialFailureMode
    ) async throws -> [[Float]] {
        var parameters: [String: Any] = ["autoTruncate": false]
        if let outputDimensions = profile.outputDimensions {
            parameters["outputDimensionality"] = outputDimensions
        }
        let body: [String: Any] = [
            "instances": texts.map { ["content": $0] },
            "parameters": parameters
        ]
        let data = try await perform(
            request: try makeRequest(
                profile: profile,
                credentials: credentials,
                body: body,
                placesKeyInQuery: true
            ),
            apiFormat: profile.apiFormat,
            credentialFailureMode: credentialFailureMode
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let predictions = root["predictions"] as? [[String: Any]] else {
            throw EmbeddingClientError.invalidResponse
        }
        return try predictions.map { prediction in
            guard let embeddings = prediction["embeddings"] as? [String: Any] else {
                throw EmbeddingClientError.invalidResponse
            }
            return try vector(from: embeddings["values"])
        }
    }

    private func makeRequest(
        profile: EmbeddingProfileSnapshot,
        credentials: EmbeddingCredentials,
        body: [String: Any],
        placesKeyInQuery: Bool,
        apiKeyHeader: String? = nil
    ) throws -> URLRequest {
        var modelPathCharacters = CharacterSet.urlPathAllowed
        modelPathCharacters.remove(charactersIn: "/?#%")
        let encodedModel = profile.model.addingPercentEncoding(withAllowedCharacters: modelPathCharacters)
            ?? profile.model
        let endpoint = profile.endpoint.replacingOccurrences(of: "{model}", with: encodedModel)
        let urlString = Self.join(baseURL: profile.baseURL, endpoint: endpoint)
        let baseURL = try AIService.validatedRequestURL(from: urlString)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let trimmedAPIKey = credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if placesKeyInQuery, !trimmedAPIKey.isEmpty {
            var queryItems = components?.queryItems ?? []
            queryItems.removeAll { $0.name == "key" }
            queryItems.append(URLQueryItem(name: "key", value: trimmedAPIKey))
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw EmbeddingClientError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKeyHeader, !trimmedAPIKey.isEmpty {
            request.setValue(trimmedAPIKey, forHTTPHeaderField: apiKeyHeader)
        } else if !placesKeyInQuery, !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }
        for header in CustomHeaderSecurity.requestHeaders(from: credentials.customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func perform(
        request: URLRequest,
        apiFormat: EmbeddingAPIFormat,
        credentialFailureMode: EmbeddingCredentialFailureMode
    ) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw EmbeddingClientError.invalidResponse
            }
            if (200..<300).contains(httpResponse.statusCode) {
                guard data.count <= 32 * 1024 * 1024 else {
                    throw EmbeddingClientError.invalidResponse
                }
                return data
            }

            let providerFailure = AIProviderHTTPFailure(
                statusCode: httpResponse.statusCode,
                responseBody: boundedResponseBody(from: data),
                apiFormat: providerAPIFormat(for: apiFormat)
            )
            if providerFailure.isCredentialFailure {
                switch credentialFailureMode {
                case .multipleKeys:
                    throw providerFailure
                case .singleKey where httpResponse.statusCode != 429:
                    throw providerFailure
                case .legacy, .singleKey:
                    break
                }
            }

            let shouldRetry = httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode)
            guard shouldRetry, attempt < 2 else {
                if providerFailure.isCredentialFailure,
                   credentialFailureMode == .singleKey {
                    throw providerFailure
                }
                throw EmbeddingClientError.requestFailed(httpResponse.statusCode)
            }
            attempt += 1
            let retryAfter = Self.retryDelay(
                from: httpResponse.value(forHTTPHeaderField: "Retry-After")
            )
            let delay = retryAfter ?? pow(2, Double(attempt - 1))
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private func vector(from value: Any?) throws -> [Float] {
        guard let numbers = value as? [NSNumber], !numbers.isEmpty else {
            throw EmbeddingClientError.invalidVector
        }
        let vector = numbers.map { $0.floatValue }
        guard vector.allSatisfy(\.isFinite) else {
            throw EmbeddingClientError.invalidVector
        }
        return vector
    }

    private func normalized(_ vectors: [[Float]], expectedCount: Int) throws -> [[Float]] {
        guard vectors.count == expectedCount,
              let dimensions = vectors.first?.count,
              dimensions > 0,
              vectors.allSatisfy({ $0.count == dimensions }) else {
            throw EmbeddingClientError.inconsistentDimensions
        }

        return try vectors.map { vector in
            let magnitude = sqrt(vector.reduce(Float.zero) { $0 + $1 * $1 })
            guard magnitude.isFinite, magnitude > 0 else {
                throw EmbeddingClientError.invalidVector
            }
            return vector.map { $0 / magnitude }
        }
    }

    nonisolated private static func join(baseURL: String, endpoint: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            + "/"
            + endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private static func retryDelay(from value: String?) -> Double? {
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return min(max(seconds, 0), 60)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return min(max(date.timeIntervalSinceNow, 0), 60)
    }
}

enum EmbeddingModelDiscoveryService {
    static func discover(
        embeddingConfiguration: AIEmbeddingConfiguration,
        credentials: EmbeddingCredentials,
        session: URLSession = AIService.makeSecureSession()
    ) async throws -> [AIEmbeddingModelConfiguration] {
        try await discover(
            embeddingConfiguration: embeddingConfiguration,
            credentials: credentials,
            reportsCredentialFailure: false,
            session: session
        )
    }

    static func discover(
        embeddingConfiguration: AIEmbeddingConfiguration,
        credentialSet: AIProviderCredentialSet,
        customHeaders: String,
        session: URLSession = AIService.makeSecureSession()
    ) async throws -> [AIEmbeddingModelConfiguration] {
        try await AIProviderFailoverExecutor().execute(
            credentialSet: credentialSet,
            customHeaders: customHeaders
        ) { credential in
            try await discover(
                embeddingConfiguration: embeddingConfiguration,
                credentials: EmbeddingCredentials(
                    apiKey: credential.secret,
                    customHeaders: customHeaders
                ),
                reportsCredentialFailure: true,
                session: session
            )
        }
    }

    private static func discover(
        embeddingConfiguration: AIEmbeddingConfiguration,
        credentials: EmbeddingCredentials,
        reportsCredentialFailure: Bool,
        session: URLSession
    ) async throws -> [AIEmbeddingModelConfiguration] {
        let url = try modelsURL(for: embeddingConfiguration)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let trimmedAPIKey = credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            if embeddingConfiguration.apiFormat == .geminiEmbedContent {
                request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")
            } else {
                request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
            }
        }
        for header in CustomHeaderSecurity.requestHeaders(from: credentials.customHeaders) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingClientError.requestFailed(0)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if reportsCredentialFailure {
                throw AIProviderHTTPFailure(
                    statusCode: httpResponse.statusCode,
                    responseBody: boundedResponseBody(from: data),
                    apiFormat: providerAPIFormat(for: embeddingConfiguration.apiFormat)
                )
            }
            throw EmbeddingClientError.requestFailed(httpResponse.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EmbeddingClientError.invalidResponse
        }

        let names: [String]
        if embeddingConfiguration.apiFormat == .geminiEmbedContent {
            let models = root["models"] as? [[String: Any]] ?? []
            names = models.compactMap { model in
                let methods = model["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains(where: { $0.localizedCaseInsensitiveContains("embedContent") }) else {
                    return nil
                }
                return (model["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            }
        } else {
            let models = root["data"] as? [[String: Any]] ?? []
            names = models.compactMap { model in
                guard let id = model["id"] as? String else { return nil }
                if url.path.contains("/embeddings/models") || url.query?.contains("sub_type=embedding") == true {
                    return id
                }
                let outputModalities = ((model["architecture"] as? [String: Any])?["output_modalities"] as? [String]) ?? []
                return outputModalities.contains("embeddings") || looksLikeEmbeddingModel(id) ? id : nil
            }
        }

        return Array(Set(names))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { AIEmbeddingModelConfiguration(name: $0) }
    }

    static func probe(
        provider: AIConfiguration,
        embeddingConfiguration: AIEmbeddingConfiguration,
        model: AIEmbeddingModelConfiguration,
        client: EmbeddingClient = EmbeddingClient()
    ) async throws -> Int {
        var profile = EmbeddingProfileSnapshot(
            providerConfigurationID: provider.id,
            embeddingConfiguration: embeddingConfiguration,
            model: model,
            vectorDimensions: model.outputDimensions ?? model.validatedDimensions ?? 1
        )
        let vectors = try await client.embed(
            [
                "MewyAI embedding capability probe A",
                "MewyAI embedding capability probe B"
            ],
            purpose: .query,
            profile: profile,
            credentialSet: provider.credentialSet(),
            customHeaders: provider.customHeaders
        )
        guard vectors.count == 2, let dimensions = vectors.first?.count else {
            throw EmbeddingClientError.invalidResponse
        }
        profile.vectorDimensions = dimensions
        return dimensions
    }

    private static func modelsURL(for configuration: AIEmbeddingConfiguration) throws -> URL {
        let base = try AIService.validatedRequestURL(from: configuration.baseURL)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw EmbeddingClientError.invalidConfiguration
        }
        let host = components.host?.lowercased() ?? ""
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if host.contains("openrouter.ai") {
            components.path = "/" + [basePath, "embeddings/models"].filter { !$0.isEmpty }.joined(separator: "/")
        } else {
            components.path = "/" + [basePath, "models"].filter { !$0.isEmpty }.joined(separator: "/")
        }
        components.queryItems = nil
        if host.contains("siliconflow") {
            components.queryItems = [URLQueryItem(name: "sub_type", value: "embedding")]
        }
        guard let url = components.url else { throw EmbeddingClientError.invalidConfiguration }
        return url
    }

    private static func looksLikeEmbeddingModel(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return ["embedding", "embed", "bge", "e5", "gte", "jina", "m3e", "qwen"]
            .contains { normalized.contains($0) }
    }
}
