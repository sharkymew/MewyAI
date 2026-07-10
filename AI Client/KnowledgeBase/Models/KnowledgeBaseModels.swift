import Foundation

nonisolated enum EmbeddingAPIFormat: String, CaseIterable, Codable, Identifiable {
    case openAICompatible
    case geminiEmbedContent
    case vertexPredict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenAI Compatible"
        case .geminiEmbedContent:
            return "Google Gemini embedContent"
        case .vertexPredict:
            return "Google Vertex predict"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible:
            return "embeddings"
        case .geminiEmbedContent:
            return "models/{model}:embedContent"
        case .vertexPredict:
            return "v1/publishers/google/models/{model}:predict"
        }
    }
}

nonisolated struct AIEmbeddingModelConfiguration: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var alias: String
    var outputDimensions: Int?
    var queryPrefix: String
    var documentPrefix: String
    var validatedDimensions: Int?
    var lastValidatedAt: Date?

    var displayName: String {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAlias.isEmpty ? name : trimmedAlias
    }

    init(
        name: String,
        alias: String = "",
        outputDimensions: Int? = nil,
        queryPrefix: String = "",
        documentPrefix: String = "",
        validatedDimensions: Int? = nil,
        lastValidatedAt: Date? = nil
    ) {
        self.name = name
        self.alias = alias
        self.outputDimensions = outputDimensions.flatMap { $0 > 0 ? $0 : nil }
        self.queryPrefix = queryPrefix
        self.documentPrefix = documentPrefix
        self.validatedDimensions = validatedDimensions.flatMap { $0 > 0 ? $0 : nil }
        self.lastValidatedAt = lastValidatedAt
    }
}

nonisolated struct AIEmbeddingConfiguration: Codable, Equatable {
    var apiFormat: EmbeddingAPIFormat
    var baseURL: String
    var endpoint: String
    var models: [AIEmbeddingModelConfiguration]

    init(
        apiFormat: EmbeddingAPIFormat = .openAICompatible,
        baseURL: String,
        endpoint: String? = nil,
        models: [AIEmbeddingModelConfiguration] = []
    ) {
        self.apiFormat = apiFormat
        self.baseURL = baseURL
        self.endpoint = endpoint ?? apiFormat.defaultEndpoint
        self.models = models
    }
}

nonisolated struct EmbeddingProfileSnapshot: Codable, Equatable {
    static let currentChunkingVersion = 1

    var providerConfigurationID: UUID
    var apiFormat: EmbeddingAPIFormat
    var baseURL: String
    var endpoint: String
    var model: String
    var outputDimensions: Int?
    var queryPrefix: String
    var documentPrefix: String
    var vectorDimensions: Int
    var chunkingVersion: Int

    init(
        providerConfigurationID: UUID,
        embeddingConfiguration: AIEmbeddingConfiguration,
        model: AIEmbeddingModelConfiguration,
        vectorDimensions: Int
    ) {
        self.providerConfigurationID = providerConfigurationID
        self.apiFormat = embeddingConfiguration.apiFormat
        self.baseURL = embeddingConfiguration.baseURL
        self.endpoint = embeddingConfiguration.endpoint
        self.model = model.name
        self.outputDimensions = model.outputDimensions
        self.queryPrefix = model.queryPrefix
        self.documentPrefix = model.documentPrefix
        self.vectorDimensions = vectorDimensions
        self.chunkingVersion = Self.currentChunkingVersion
    }

    var signature: String {
        [
            providerConfigurationID.uuidString,
            apiFormat.rawValue,
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            model,
            outputDimensions.map(String.init) ?? "",
            queryPrefix,
            documentPrefix,
            String(vectorDimensions),
            String(chunkingVersion)
        ].joined(separator: "\u{1F}")
    }
}

nonisolated enum KnowledgeDocumentStatus: String, Codable, Equatable {
    case pending
    case extracting
    case embedding
    case indexed
    case failed
}

nonisolated struct KnowledgeChunk: Identifiable, Codable, Equatable {
    var id: UUID
    var index: Int
    var text: String
    var location: String

    init(id: UUID = UUID(), index: Int, text: String, location: String = "") {
        self.id = id
        self.index = index
        self.text = text
        self.location = location
    }
}

nonisolated struct KnowledgeDocument: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var typeIdentifier: String?
    var byteCount: Int
    var characterCount: Int
    var contentHash: String
    var extractedText: String
    var chunks: [KnowledgeChunk]
    var status: KnowledgeDocumentStatus
    var errorMessage: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        typeIdentifier: String?,
        byteCount: Int,
        characterCount: Int,
        contentHash: String,
        extractedText: String,
        chunks: [KnowledgeChunk],
        status: KnowledgeDocumentStatus,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.characterCount = characterCount
        self.contentHash = contentHash
        self.extractedText = extractedText
        self.chunks = chunks
        self.status = status
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

nonisolated struct KnowledgeBase: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var profile: EmbeddingProfileSnapshot
    var documents: [KnowledgeDocument]
    var createdAt: Date
    var updatedAt: Date
    var needsReindex: Bool

    init(
        id: UUID = UUID(),
        name: String,
        profile: EmbeddingProfileSnapshot,
        documents: [KnowledgeDocument] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        needsReindex: Bool = false
    ) {
        self.id = id
        self.name = name
        self.profile = profile
        self.documents = documents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.needsReindex = needsReindex
    }

    var indexedChunkCount: Int {
        documents
            .filter { $0.status == .indexed }
            .reduce(0) { $0 + $1.chunks.count }
    }

    var storedChunkCount: Int {
        documents.reduce(0) { $0 + $1.chunks.count }
    }
}

nonisolated struct KnowledgeCitation: Identifiable, Codable, Equatable {
    var id: UUID
    var knowledgeBaseID: UUID
    var knowledgeBaseName: String
    var documentID: UUID
    var documentName: String
    var chunkID: UUID
    var chunkIndex: Int
    var location: String
    var excerpt: String
    var similarity: Double

    init(
        id: UUID = UUID(),
        knowledgeBaseID: UUID,
        knowledgeBaseName: String,
        documentID: UUID,
        documentName: String,
        chunkID: UUID,
        chunkIndex: Int,
        location: String,
        excerpt: String,
        similarity: Double
    ) {
        self.id = id
        self.knowledgeBaseID = knowledgeBaseID
        self.knowledgeBaseName = knowledgeBaseName
        self.documentID = documentID
        self.documentName = documentName
        self.chunkID = chunkID
        self.chunkIndex = chunkIndex
        self.location = location
        self.excerpt = excerpt
        self.similarity = similarity
    }
}

nonisolated struct KnowledgeSearchResult: Equatable {
    var citation: KnowledgeCitation
    var text: String
}
