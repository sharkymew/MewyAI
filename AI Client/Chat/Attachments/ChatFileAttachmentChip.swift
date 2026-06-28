import Foundation
import SwiftUI

struct ChatFileAttachmentChip: View {
    let attachment: ChatFileAttachment
    let onRemove: (() -> Void)?

    init(attachment: ChatFileAttachment, onRemove: (() -> Void)? = nil) {
        self.attachment = attachment
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 190, alignment: .leading)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.removeFile", defaultValue: "Remove file"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var detailText: String {
        let byteText = ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
        let truncatedText = attachment.isTruncated
            ? AppLocalizations.string("fileAttachment.truncatedSuffix", defaultValue: " · truncated")
            : ""
        return AppLocalizations.format(
            "fileAttachment.detail",
            defaultValue: "%@ · %d characters%@",
            arguments: [byteText, attachment.characterCount, truncatedText]
        )
    }
}
