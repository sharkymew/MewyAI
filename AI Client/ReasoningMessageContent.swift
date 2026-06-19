import Foundation
import SwiftUI

struct ReasoningMessageContent: View {
    let content: String
    let chunks: [String]
    let isStreaming: Bool
    let streamingChannel: StreamingTextUpdateChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let streamingChannel {
                ScrollableSelectableTextView(
                    text: "",
                    streamingChannel: streamingChannel,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: true
                )
            } else if !chunks.isEmpty {
                ScrollableSelectableTextView(
                    text: "",
                    chunks: chunks,
                    appendsChunksProgressively: true,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: false
                )
            } else if usesScrollableTextView {
                ScrollableSelectableTextView(
                    text: content,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: isStreaming
                )
            } else {
                ReasoningPlainText(content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesScrollableTextView: Bool {
        isStreaming || !chunks.isEmpty || content.utf16.count > Self.inlineCharacterLimit
    }

    private static let inlineCharacterLimit = 1_800
}
