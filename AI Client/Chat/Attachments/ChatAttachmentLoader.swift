import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ChatAttachmentLoader {
    static let maxImageInputByteCount = 12 * 1024 * 1024
    static let maxImagePixelCount: Int64 = 24_000_000

    static func imageAttachment(from data: Data, storesLocally: Bool) -> ChatImageAttachment? {
        guard imageDataIsWithinLimits(data) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        return imageAttachment(from: image, storesLocally: storesLocally)
    }

    static func imageAttachment(fromImageFileAt url: URL, storesLocally: Bool) -> ChatImageAttachment? {
        guard imageFileIsWithinLimits(url),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return imageAttachment(from: data, storesLocally: storesLocally)
    }

    static func imageAttachment(from image: UIImage, storesLocally: Bool) -> ChatImageAttachment? {
        guard imagePixelCount(image) <= maxImagePixelCount else { return nil }
        let scaledImage = image.scaledDown(maxDimension: 1600)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        if storesLocally {
            return ConversationImageStore.storeJPEGData(jpegData)
        }

        var attachment = ChatImageAttachment(
            dataURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        )
        attachment.byteCount = jpegData.count
        return attachment
    }

    static func imageDataIsWithinLimits(_ data: Data) -> Bool {
        guard data.count <= maxImageInputByteCount else { return false }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }

        let pixelCount = Int64(width.intValue) * Int64(height.intValue)
        return pixelCount > 0 && pixelCount <= maxImagePixelCount
    }

    static func imageFileIsWithinLimits(_ url: URL) -> Bool {
        guard url.isFileURL,
              let byteCount = fileByteCount(for: url),
              byteCount <= maxImageInputByteCount,
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }

        let pixelCount = Int64(width.intValue) * Int64(height.intValue)
        return pixelCount > 0 && pixelCount <= maxImagePixelCount
    }

    static func fileByteCount(for url: URL) -> Int? {
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) {
            if resourceValues.isRegularFile == false {
                return nil
            }
            if let fileSize = resourceValues.fileSize {
                return fileSize
            }
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    static func imagePixelCount(_ image: UIImage) -> Int64 {
        let scale = max(image.scale, 1)
        let width = Int64((image.size.width * scale).rounded())
        let height = Int64((image.size.height * scale).rounded())
        return width * height
    }

    nonisolated static func providerContainsImage(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
    }

    nonisolated static func providerContainsReadableFile(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { identifier in
            isReadableFileIdentifier(identifier)
        }
    }

    static func fileAttachment(from provider: NSItemProvider) async -> ChatFileAttachment? {
        if provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier),
           let url = await fileURL(from: provider),
           url.isFileURL {
            return try? ChatFileAttachmentReader.attachment(from: url)
        }

        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            isReadableFileIdentifier(identifier)
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: try? ChatFileAttachmentReader.attachment(from: url))
            }
        }
    }

    static func imageAttachments(
        from items: [PhotosPickerItem],
        storesLocally: Bool
    ) async -> [ChatImageAttachment] {
        var attachments = [ChatImageAttachment]()

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let attachment = imageAttachment(from: data, storesLocally: storesLocally) else {
                continue
            }

            attachments.append(attachment)
        }

        return attachments
    }

    static func imageAttachments(
        from providers: [NSItemProvider],
        storesLocally: Bool,
        maxCount: Int = ChatAttachmentDraft.maxImageAttachmentCount
    ) async -> [ChatImageAttachment] {
        var attachments = [ChatImageAttachment]()

        for provider in providers.prefix(maxCount) {
            guard let attachment = await imageAttachment(
                from: provider,
                storesLocally: storesLocally
            ) else {
                continue
            }

            attachments.append(attachment)
        }

        return attachments
    }

    static func fileAttachments(
        from providers: [NSItemProvider],
        maxCount: Int = ChatAttachmentDraft.maxFileAttachmentCount
    ) async -> [ChatFileAttachment] {
        var attachments = [ChatFileAttachment]()

        for provider in providers.prefix(maxCount) {
            guard let attachment = await fileAttachment(from: provider) else { continue }
            attachments.append(attachment)
        }

        return attachments
    }

    static func fileAttachments(
        from urls: [URL],
        maxCount: Int = ChatAttachmentDraft.maxFileAttachmentCount
    ) -> (attachments: [ChatFileAttachment], firstError: String?) {
        var attachments = [ChatFileAttachment]()
        var firstError: String?

        for url in urls.prefix(maxCount) {
            do {
                attachments.append(try ChatFileAttachmentReader.attachment(from: url))
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }

        return (attachments, firstError)
    }

    nonisolated static func isReadableFileIdentifier(_ identifier: String) -> Bool {
        guard identifier != UTType.fileURL.identifier else { return true }
        guard let type = UTType(identifier) else { return false }

        return ChatFileAttachmentReader.supportedDocumentTypes.contains { supportedType in
            type.conforms(to: supportedType) || supportedType.conforms(to: type)
        }
    }

    static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL, url.isFileURL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString),
                   url.isFileURL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    static func imageAttachment(
        from provider: NSItemProvider,
        storesLocally: Bool
    ) async -> ChatImageAttachment? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url,
                      let attachment = imageAttachment(
                        fromImageFileAt: url,
                        storesLocally: storesLocally
                      ) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: attachment)
            }
        }
    }
}
