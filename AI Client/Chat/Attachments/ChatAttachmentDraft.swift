import Foundation
import PhotosUI
import SwiftUI

struct ChatAttachmentDraft {
    nonisolated static let maxImageAttachmentCount = 4
    nonisolated static let maxFileAttachmentCount = 5

    var selectedPhotoItems: [PhotosPickerItem] = []
    var isPhotoPickerPresented = false
    var isCameraPresented = false
    var isFileImporterPresented = false
    var pendingImageAttachments: [ChatImageAttachment] = []
    var pendingFileAttachments: [ChatFileAttachment] = []
    var imageSelectionError: String?
    var isAttachmentDropTargeted = false

    var hasPendingAttachments: Bool {
        !pendingImageAttachments.isEmpty || !pendingFileAttachments.isEmpty
    }

    mutating func clear() {
        pendingImageAttachments = []
        pendingFileAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
    }

    mutating func clearImages() {
        pendingImageAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
    }

    mutating func setEditingAttachments(
        images: [ChatImageAttachment],
        files: [ChatFileAttachment]
    ) {
        pendingImageAttachments = images
        pendingFileAttachments = files
        selectedPhotoItems = []
    }

    mutating func rejectImagesUnsupported(message: String) {
        selectedPhotoItems = []
        imageSelectionError = message
    }

    mutating func setPendingImageAttachments(
        _ attachments: [ChatImageAttachment],
        maxCount: Int = Self.maxImageAttachmentCount
    ) {
        pendingImageAttachments = Array(attachments.prefix(maxCount))
        if attachments.count > maxCount {
            imageSelectionError = AppLocalizations.format(
                "attachment.image.limitTrimmed",
                defaultValue: "You can add up to %d images. The first %d were kept.",
                arguments: [maxCount, maxCount]
            )
        }
    }

    mutating func appendPendingImageAttachments(
        _ attachments: [ChatImageAttachment],
        source: String,
        supportsImages: Bool,
        maxCount: Int = Self.maxImageAttachmentCount
    ) {
        guard supportsImages else {
            imageSelectionError = AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            )
            return
        }

        guard !attachments.isEmpty else {
            imageSelectionError = AppLocalizations.format(
                "attachment.image.readFailed",
                defaultValue: "Failed to read images from %@.",
                arguments: [source]
            )
            return
        }

        let remainingCount = maxCount - pendingImageAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = AppLocalizations.format(
                "attachment.image.limit",
                defaultValue: "You can add up to %d images.",
                arguments: [maxCount]
            )
            return
        }

        pendingImageAttachments.append(contentsOf: attachments.prefix(remainingCount))
        imageSelectionError = attachments.count > remainingCount
            ? AppLocalizations.format(
                "attachment.image.limitTrimmed",
                defaultValue: "You can add up to %d images. The first %d were kept.",
                arguments: [maxCount, maxCount]
            )
            : nil
    }

    mutating func appendPendingFileAttachments(
        _ attachments: [ChatFileAttachment],
        source: String,
        fallbackError: String? = nil,
        maxCount: Int = Self.maxFileAttachmentCount
    ) {
        guard !attachments.isEmpty else {
            imageSelectionError = fallbackError ?? AppLocalizations.format(
                "attachment.file.readFailed",
                defaultValue: "Failed to read files from %@.",
                arguments: [source]
            )
            return
        }

        let remainingCount = maxCount - pendingFileAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = AppLocalizations.format(
                "attachment.file.limit",
                defaultValue: "You can add up to %d files.",
                arguments: [maxCount]
            )
            return
        }

        pendingFileAttachments.append(contentsOf: attachments.prefix(remainingCount))

        if attachments.count > remainingCount {
            imageSelectionError = AppLocalizations.format(
                "attachment.file.limitTrimmed",
                defaultValue: "You can add up to %d files. The first %d were kept.",
                arguments: [maxCount, maxCount]
            )
        } else {
            imageSelectionError = fallbackError
        }
    }

    mutating func removePendingImage(_ id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
        if pendingImageAttachments.isEmpty {
            selectedPhotoItems = []
        }
    }

    mutating func removePendingFile(_ id: UUID) {
        pendingFileAttachments.removeAll { $0.id == id }
    }
}
