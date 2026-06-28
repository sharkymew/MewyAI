import Foundation
import SwiftUI
import UIKit

struct ChatAttachmentImage: View {
    let attachment: ChatImageAttachment

    var body: some View {
        if let image = UIImage(chatImageAttachment: attachment) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
