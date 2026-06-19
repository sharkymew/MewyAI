import Foundation
import SwiftUI
import UIKit

extension UIImage {
    convenience init?(chatImageAttachment attachment: ChatImageAttachment) {
        guard let data = ConversationImageStore.imageData(for: attachment) else { return nil }
        self.init(data: data)
    }

    func scaledDown(maxDimension: CGFloat) -> UIImage {
        let largestDimension = max(size.width, size.height)
        guard largestDimension > maxDimension else { return self }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
