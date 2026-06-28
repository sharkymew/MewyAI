import Foundation
import SwiftUI

struct AssistantMessageContent: View {
    let content: String
    let isStreaming: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let isStopped: Bool
    let markdownRenderCache: MarkdownRenderCacheEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorContent = ErrorDetailContent.parse(content),
               streamingContentChannel == nil,
               !isStreaming {
                CollapsibleErrorDetailsView(error: errorContent)
            } else if let streamingContentChannel {
                StreamingAssistantMarkdownText(streamingChannel: streamingContentChannel)
            } else if isStreaming {
                StreamingAssistantMarkdownText(content)
            } else if let markdownRenderCache {
                AssistantMarkdownText(renderCache: markdownRenderCache)
            } else {
                PlainAssistantText(content)
            }

            if isStopped {
                Text(AppLocalizations.string("chat.message.stopped", defaultValue: "Generation stopped."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
