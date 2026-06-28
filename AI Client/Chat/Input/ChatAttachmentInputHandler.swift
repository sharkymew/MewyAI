import Foundation
import PhotosUI
import SwiftUI

enum ChatAttachmentInputHandler {
    struct SelectedImageLoadRequest {
        let items: [PhotosPickerItem]
        let storesImagesLocally: Bool
        let itemCount: Int
    }

    struct ImageProviderLoadRequest {
        let providers: [NSItemProvider]
        let storesImagesLocally: Bool
        let source: String
    }

    struct FileURLLoadRequest {
        let urls: [URL]
        let source: String
    }

    struct FileProviderLoadRequest {
        let providers: [NSItemProvider]
        let source: String
    }

    static func prepareSelectedImageLoad(
        from items: [PhotosPickerItem],
        supportsImages: Bool,
        storesImagesLocally: Bool,
        draft: inout ChatAttachmentDraft
    ) -> SelectedImageLoadRequest? {
        guard !items.isEmpty else { return nil }

        guard supportsImages else {
            draft.rejectImagesUnsupported(message: AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            ))
            return nil
        }

        draft.imageSelectionError = nil
        return SelectedImageLoadRequest(
            items: items,
            storesImagesLocally: storesImagesLocally,
            itemCount: items.count
        )
    }

    static func applySelectedImageLoadResult(
        _ attachments: [ChatImageAttachment],
        originalItemCount: Int,
        draft: inout ChatAttachmentDraft
    ) {
        if attachments.isEmpty, originalItemCount > 0 {
            draft.imageSelectionError = AppLocalizations.string(
                "attachment.image.photoPickerReadFailed",
                defaultValue: "Failed to read images. Please select them again."
            )
        } else {
            draft.setPendingImageAttachments(attachments)
            draft.imageSelectionError = nil
        }
    }

    static func prepareDroppedImageLoad(
        from providers: [NSItemProvider],
        supportsImages: Bool,
        storesImagesLocally: Bool,
        draft: inout ChatAttachmentDraft
    ) -> ImageProviderLoadRequest? {
        let imageProviders = providers.filter(ChatAttachmentLoader.providerContainsImage)

        guard !imageProviders.isEmpty else { return nil }

        guard supportsImages else {
            draft.imageSelectionError = AppLocalizations.string(
                "attachment.image.droppedUnsupported",
                defaultValue: "The current model does not support image input. Images were ignored."
            )
            return nil
        }

        draft.imageSelectionError = nil
        return ImageProviderLoadRequest(
            providers: imageProviders,
            storesImagesLocally: storesImagesLocally,
            source: AppLocalizations.string("attachment.source.drag", defaultValue: "drag and drop")
        )
    }

    static func preparePastedImageLoad(
        from providers: [NSItemProvider],
        supportsImages: Bool,
        storesImagesLocally: Bool,
        draft: inout ChatAttachmentDraft
    ) -> ImageProviderLoadRequest? {
        guard supportsImages else {
            draft.imageSelectionError = AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            )
            return nil
        }

        let imageProviders = providers.filter(ChatAttachmentLoader.providerContainsImage)
        guard !imageProviders.isEmpty else {
            draft.imageSelectionError = AppLocalizations.string(
                "attachment.image.clipboardEmpty",
                defaultValue: "There are no pasteable images on the clipboard."
            )
            return nil
        }

        return ImageProviderLoadRequest(
            providers: imageProviders,
            storesImagesLocally: storesImagesLocally,
            source: AppLocalizations.string("attachment.source.clipboard", defaultValue: "clipboard")
        )
    }

    static func applyImageProviderLoadResult(
        _ attachments: [ChatImageAttachment],
        request: ImageProviderLoadRequest,
        supportsImages: Bool,
        draft: inout ChatAttachmentDraft
    ) {
        draft.appendPendingImageAttachments(
            attachments,
            source: request.source,
            supportsImages: supportsImages
        )
    }

    static func prepareSelectedFileLoad(
        from result: Result<[URL], Error>,
        draft: inout ChatAttachmentDraft
    ) -> FileURLLoadRequest? {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return nil }
            return FileURLLoadRequest(
                urls: urls,
                source: AppLocalizations.string("attachment.source.selection", defaultValue: "selection")
            )
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return nil }
            draft.imageSelectionError = AppLocalizations.format(
                "attachment.file.selectionFailed",
                defaultValue: "File selection failed: %@",
                arguments: [error.localizedDescription]
            )
            return nil
        }
    }

    static func applySelectedFileLoadResult(
        _ result: (attachments: [ChatFileAttachment], firstError: String?),
        request: FileURLLoadRequest,
        draft: inout ChatAttachmentDraft
    ) {
        draft.appendPendingFileAttachments(
            result.attachments,
            source: request.source,
            fallbackError: result.firstError
        )
    }

    static func prepareDroppedFileLoad(from providers: [NSItemProvider]) -> FileProviderLoadRequest? {
        let fileProviders = providers.filter { provider in
            !ChatAttachmentLoader.providerContainsImage(provider)
                && ChatAttachmentLoader.providerContainsReadableFile(provider)
        }

        guard !fileProviders.isEmpty else { return nil }

        return FileProviderLoadRequest(
            providers: fileProviders,
            source: AppLocalizations.string("attachment.source.drag", defaultValue: "drag and drop")
        )
    }

    static func applyFileProviderLoadResult(
        _ attachments: [ChatFileAttachment],
        request: FileProviderLoadRequest,
        draft: inout ChatAttachmentDraft
    ) {
        draft.appendPendingFileAttachments(
            attachments,
            source: request.source
        )
    }
}
