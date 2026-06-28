import SwiftUI

struct ChatPendingAttachmentPreview: View {
    let imageAttachments: [ChatImageAttachment]
    let fileAttachments: [ChatFileAttachment]
    let onRemoveImage: (UUID) -> Void
    let onRemoveFile: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !imageAttachments.isEmpty {
                imageAttachmentPreview
            }

            if !fileAttachments.isEmpty {
                fileAttachmentPreview
            }
        }
    }

    private var imageAttachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(imageAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        ChatAttachmentImage(attachment: attachment)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            onRemoveImage(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white, .black.opacity(0.60))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    private var fileAttachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileAttachments) { attachment in
                    ChatFileAttachmentChip(attachment: attachment) {
                        onRemoveFile(attachment.id)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
    }
}
