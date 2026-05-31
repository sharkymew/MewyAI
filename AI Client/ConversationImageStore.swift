import CryptoKit
import Foundation

enum ConversationImageStore {
    nonisolated private static let imageDirectoryName = "ConversationImages"
    nonisolated private static let jpegMIMEType = "image/jpeg"
    nonisolated private static let jpegFileExtension = "jpg"

    nonisolated static func storeJPEGData(_ data: Data, id: UUID = UUID()) -> ChatImageAttachment? {
        storeImageData(data, id: id, mimeType: jpegMIMEType)
    }

    nonisolated static func dataURL(for attachment: ChatImageAttachment) -> String? {
        if let data = imageData(for: attachment) {
            return "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
        }

        return attachment.dataURL
    }

    nonisolated static func removeUnreferencedImages(
        retainedBy conversations: [AIConversation],
        additionalAttachments: [ChatImageAttachment] = []
    ) {
        guard let imageDirectoryURL,
              let storedFileURLs = try? FileManager.default.contentsOfDirectory(
                at: imageDirectoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        let retainedFileNames = Set(
            conversations
                .flatMap(\.allStoredMessages)
                .flatMap(\.imageAttachments)
                .compactMap(\.fileName)
                + additionalAttachments.compactMap(\.fileName)
        )

        for fileURL in storedFileURLs {
            let fileName = fileURL.lastPathComponent
            guard isValidStoredImageFileName(fileName),
                  !retainedFileNames.contains(fileName) else {
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    nonisolated static func imageData(for attachment: ChatImageAttachment) -> Data? {
        if let fileName = attachment.fileName,
           let fileURL = fileURL(for: fileName),
           let data = try? Data(contentsOf: fileURL) {
            return data
        }

        guard let dataURL = attachment.dataURL else { return nil }
        return imageData(fromDataURL: dataURL)
    }

    nonisolated static func migratedLegacyImages(in conversations: [AIConversation]) -> [AIConversation] {
        conversations.map(migratedLegacyImages)
    }

    nonisolated static func imageData(fromDataURL dataURL: String) -> Data? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = dataURL[dataURL.index(after: commaIndex)...]
        return Data(base64Encoded: String(base64), options: .ignoreUnknownCharacters)
    }

    nonisolated private static func migratedLegacyImages(in conversation: AIConversation) -> AIConversation {
        var conversation = conversation
        conversation.messages = conversation.messages.map { message in
            var message = message
            message.imageAttachments = message.imageAttachments.map(migratedLegacyImage)
            return message
        }
        conversation.messageRevisionGroups = conversation.messageRevisionGroups.map { group in
            var group = group
            group.revisions = group.revisions.map { revision in
                var revision = revision
                revision.messages = revision.messages.map { message in
                    var message = message
                    message.imageAttachments = message.imageAttachments.map(migratedLegacyImage)
                    return message
                }
                return revision
            }
            return group
        }
        return conversation
    }

    nonisolated private static func migratedLegacyImage(_ attachment: ChatImageAttachment) -> ChatImageAttachment {
        guard attachment.fileName == nil,
              let dataURL = attachment.dataURL,
              let data = imageData(fromDataURL: dataURL) else {
            return attachment
        }

        return storeImageData(
            data,
            id: attachment.id,
            mimeType: attachment.mimeType
        ) ?? attachment
    }

    nonisolated private static func storeImageData(
        _ data: Data,
        id: UUID,
        mimeType: String
    ) -> ChatImageAttachment? {
        let digest = sha256HexString(for: data)
        let fileName = "\(digest).\(fileExtension(for: mimeType))"

        guard let fileURL = fileURL(for: fileName) else { return nil }

        do {
            try ensureImageDirectoryExists()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: fileURL.path
                )
            }

            return ChatImageAttachment(
                id: id,
                fileName: fileName,
                md5: digest,
                byteCount: data.count,
                mimeType: mimeType
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func ensureImageDirectoryExists() throws {
        guard let imageDirectoryURL else { return }
        try FileManager.default.createDirectory(
            at: imageDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    nonisolated private static func fileURL(for fileName: String) -> URL? {
        guard isValidStoredImageFileName(fileName),
              let imageDirectoryURL else {
            return nil
        }

        let directoryURL = imageDirectoryURL.standardizedFileURL
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard fileURL.path.hasPrefix(directoryURL.path + "/") else { return nil }
        return fileURL
    }

    nonisolated private static var imageDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(imageDirectoryName, isDirectory: true)
    }

    nonisolated private static func sha256HexString(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated private static func isValidStoredImageFileName(_ fileName: String) -> Bool {
        let parts = fileName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let digest = parts.first,
              let fileExtension = parts.last,
              [32, 64].contains(digest.count),
              ["jpg", "png"].contains(fileExtension.lowercased()) else {
            return false
        }

        let lowercaseHexCharacters = Set("0123456789abcdef")
        return digest.allSatisfy { lowercaseHexCharacters.contains($0) }
    }

    nonisolated private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return jpegFileExtension
        case "image/png":
            return "png"
        default:
            return jpegFileExtension
        }
    }
}
