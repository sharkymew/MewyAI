import Foundation

nonisolated enum KnowledgeBaseStore {
    private static let directoryName = "KnowledgeBases"
    private static let indexFileName = "Index.json"
    private static let manifestFileName = "Manifest.json"
    private static let documentsDirectoryName = "Documents"
    private static let vectorsDirectoryName = "Vectors"
    private static let vectorMagic = Data("MEWV1".utf8)

    private struct KnowledgeBaseIndex: Codable {
        var version: Int
        var ids: [UUID]
    }

    static func loadKnowledgeBases(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [KnowledgeBase] {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL),
              let data = try? Data(contentsOf: rootURL.appendingPathComponent(indexFileName)),
              let index = try? JSONDecoder().decode(KnowledgeBaseIndex.self, from: data) else {
            return []
        }

        return index.ids.compactMap { id in
            let url = rootURL
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent(manifestFileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(KnowledgeBase.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    static func saveKnowledgeBase(
        _ knowledgeBase: KnowledgeBase,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return false
        }
        let baseURL = rootURL.appendingPathComponent(knowledgeBase.id.uuidString, isDirectory: true)
        let documentsURL = baseURL.appendingPathComponent(documentsDirectoryName, isDirectory: true)
        let vectorsURL = baseURL.appendingPathComponent(vectorsDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: vectorsURL, withIntermediateDirectories: true)

            for document in knowledgeBase.documents where !document.extractedText.isEmpty {
                let data = try JSONEncoder().encode(document)
                try compressed(data).write(
                    to: documentsURL.appendingPathComponent("\(document.id.uuidString).json.lzfse"),
                    options: [.atomic, .completeFileProtection]
                )
            }

            var manifest = knowledgeBase
            manifest.documents = knowledgeBase.documents.map { document in
                var metadata = document
                metadata.extractedText = ""
                metadata.chunks = document.chunks.map { chunk in
                    KnowledgeChunk(id: chunk.id, index: chunk.index, text: "", location: chunk.location)
                }
                return metadata
            }
            try JSONEncoder().encode(manifest).write(
                to: baseURL.appendingPathComponent(manifestFileName),
                options: [.atomic, .completeFileProtection]
            )

            var ids = loadIndex(rootURL: rootURL).ids.filter { $0 != knowledgeBase.id }
            ids.insert(knowledgeBase.id, at: 0)
            try JSONEncoder().encode(KnowledgeBaseIndex(version: 1, ids: ids)).write(
                to: rootURL.appendingPathComponent(indexFileName),
                options: [.atomic, .completeFileProtection]
            )
            return true
        } catch {
            return false
        }
    }

    static func loadDocument(
        knowledgeBaseID: UUID,
        documentID: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> KnowledgeDocument? {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return nil
        }
        let url = rootURL
            .appendingPathComponent(knowledgeBaseID.uuidString, isDirectory: true)
            .appendingPathComponent(documentsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).json.lzfse")
        guard let storedData = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(
                KnowledgeDocument.self,
                from: decompressed(storedData)
              ) else {
            return nil
        }
        return document
    }

    @discardableResult
    static func saveVectors(
        _ vectors: [[Float]],
        knowledgeBaseID: UUID,
        documentID: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard let dimensions = vectors.first?.count,
              dimensions > 0,
              vectors.allSatisfy({ $0.count == dimensions }),
              let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return false
        }
        let directoryURL = rootURL
            .appendingPathComponent(knowledgeBaseID.uuidString, isDirectory: true)
            .appendingPathComponent(vectorsDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var data = vectorMagic
            appendUInt32(UInt32(dimensions), to: &data)
            appendUInt32(UInt32(vectors.count), to: &data)
            for value in vectors.joined() {
                appendUInt32(value.bitPattern, to: &data)
            }
            try data.write(
                to: directoryURL.appendingPathComponent("\(documentID.uuidString).bin"),
                options: [.atomic, .completeFileProtection]
            )
            return true
        } catch {
            return false
        }
    }

    static func loadVectors(
        knowledgeBaseID: UUID,
        documentID: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> [[Float]]? {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return nil
        }
        let url = rootURL
            .appendingPathComponent(knowledgeBaseID.uuidString, isDirectory: true)
            .appendingPathComponent(vectorsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).bin")
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.starts(with: vectorMagic),
              let dimensions = readUInt32(data, at: vectorMagic.count).map(Int.init),
              let count = readUInt32(data, at: vectorMagic.count + 4).map(Int.init),
              dimensions > 0,
              count >= 0 else {
            return nil
        }

        let valueOffset = vectorMagic.count + 8
        let (valueCount, countOverflowed) = dimensions.multipliedReportingOverflow(by: count)
        let (valueByteCount, byteOverflowed) = valueCount.multipliedReportingOverflow(by: 4)
        let (expectedByteCount, offsetOverflowed) = valueOffset.addingReportingOverflow(valueByteCount)
        guard !countOverflowed,
              !byteOverflowed,
              !offsetOverflowed,
              data.count == expectedByteCount else { return nil }
        var vectors = [[Float]]()
        vectors.reserveCapacity(count)
        var offset = valueOffset
        for _ in 0..<count {
            var vector = [Float]()
            vector.reserveCapacity(dimensions)
            for _ in 0..<dimensions {
                guard let bits = readUInt32(data, at: offset) else { return nil }
                vector.append(Float(bitPattern: bits))
                offset += 4
            }
            vectors.append(vector)
        }
        return vectors
    }

    @discardableResult
    static func deleteKnowledgeBase(
        _ id: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return false
        }
        do {
            let baseURL = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
            if fileManager.fileExists(atPath: baseURL.path) {
                try fileManager.removeItem(at: baseURL)
            }
            let ids = loadIndex(rootURL: rootURL).ids.filter { $0 != id }
            try JSONEncoder().encode(KnowledgeBaseIndex(version: 1, ids: ids)).write(
                to: rootURL.appendingPathComponent(indexFileName),
                options: [.atomic, .completeFileProtection]
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteDocumentFiles(
        knowledgeBaseID: UUID,
        documentID: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> Bool {
        guard let rootURL = rootURL(fileManager: fileManager, override: applicationSupportURL) else {
            return false
        }
        let baseURL = rootURL.appendingPathComponent(knowledgeBaseID.uuidString, isDirectory: true)
        let urls = [
            baseURL.appendingPathComponent(documentsDirectoryName, isDirectory: true)
                .appendingPathComponent("\(documentID.uuidString).json.lzfse"),
            baseURL.appendingPathComponent(vectorsDirectoryName, isDirectory: true)
                .appendingPathComponent("\(documentID.uuidString).bin")
        ]
        do {
            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    private static func rootURL(fileManager: FileManager, override: URL?) -> URL? {
        let applicationSupportURL = override
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let rootURL = applicationSupportURL?.appendingPathComponent(directoryName, isDirectory: true) else {
            return nil
        }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL
        } catch {
            return nil
        }
    }

    private static func loadIndex(rootURL: URL) -> KnowledgeBaseIndex {
        guard let data = try? Data(contentsOf: rootURL.appendingPathComponent(indexFileName)),
              let index = try? JSONDecoder().decode(KnowledgeBaseIndex.self, from: data) else {
            return KnowledgeBaseIndex(version: 1, ids: [])
        }
        return index
    }

    private static func compressed(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .lzfse) as Data) ?? data
    }

    private static func decompressed(_ data: Data) -> Data {
        guard data.starts(with: Data("bvx".utf8)) else { return data }
        return (try? (data as NSData).decompressed(using: .lzfse) as Data) ?? data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
