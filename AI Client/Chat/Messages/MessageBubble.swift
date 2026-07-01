import Foundation
import SwiftUI

struct MessageBubble: View {
    @Binding var message: ChatMessage
    let isStreaming: Bool
    let hasStreamingReasoning: Bool
    let hasStreamingContent: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let streamingReasoningChannel: StreamingTextUpdateChannel?
    let markdownRenderCache: MarkdownRenderCacheEntry?
    let usageDisplayText: String?
    let showsActions: Bool
    let revisionNavigationState: MessageRevisionNavigationState?
    let onSelect: () -> Void
    let onReasoningExpansionChanged: (Bool) -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onBranch: () -> Void
    let onClearGeneratedContent: () -> Void
    let onSelectPreviousRevision: () -> Void
    let onSelectNextRevision: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool {
        message.role == "user"
    }

    private var userBubbleColor: Color {
        colorScheme == .dark ? Color.blue.opacity(0.72) : Color.accentColor
    }

    private var assistantBubbleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.gray.opacity(0.16)
    }

    private var assistantReasoningColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.10)
    }

    private var displayContent: String {
        guard !message.isContentCleared else { return "" }
        return message.content
    }

    private var displayReasoningContent: String {
        guard !message.isContentCleared else { return "" }
        return message.reasoningContent
    }

    private var displayReasoningChunks: [String] {
        guard !message.isContentCleared else { return [] }
        return message.reasoningChunks
    }

    private var hasReasoningContent: Bool {
        hasStreamingReasoning || !displayReasoningContent.isEmpty || !displayReasoningChunks.isEmpty
    }

    private var shouldShowMessageContentBubble: Bool {
        if isUser {
            return !displayContent.isEmpty
        }

        if !displayContent.isEmpty || hasStreamingContent || message.isStopped {
            return true
        }

        return !isStreaming && !hasReasoningContent
    }

    private var messageContentBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                SelectableTextView(
                    text: displayContent,
                    textColor: .white,
                    font: .preferredFont(forTextStyle: .body),
                    textAlignment: .left,
                    sizing: .natural,
                    onTap: onSelect
                )
            } else if displayContent.isEmpty, !hasStreamingContent {
                Text(message.isStopped
                    ? AppLocalizations.string("chat.message.stopped", defaultValue: "Generation stopped.")
                    : AppLocalizations.string("chat.message.generating", defaultValue: "Generating response..."))
            } else {
                AssistantMessageContent(
                    content: displayContent,
                    isStreaming: isStreaming,
                    streamingContentChannel: streamingContentChannel,
                    isStopped: message.isStopped,
                    markdownRenderCache: markdownRenderCache
                )
            }
        }
        .font(.body)
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? userBubbleColor : assistantBubbleColor)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 48)
                userMessageStack
            } else {
                assistantMessageStack
                Spacer(minLength: 48)
            }
        }
        .contextMenu {
            if shouldOfferClearGeneratedContentAction {
                Button(role: .destructive) {
                    onClearGeneratedContent()
                } label: {
                    Label(
                        AppLocalizations.string("chat.message.clearAction", defaultValue: "清除"),
                        systemImage: "trash"
                    )
                }
            }
        }
    }

    private var userMessageStack: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.imageAttachments.isEmpty {
                messageImages
            }

            if !message.fileAttachments.isEmpty {
                messageFiles
            }

            if !message.content.isEmpty {
                messageContentBubble
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
            }

            if let revisionNavigationState {
                revisionNavigationControl(revisionNavigationState)
            }

            if showsActions {
                HStack(spacing: 8) {
                    Button {
                        onBranch()
                    } label: {
                        Label(
                            AppLocalizations.string(
                                "chat.message.branchAction",
                                defaultValue: "分叉"
                            ),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)

                    Button {
                        onEdit()
                    } label: {
                        Label("修改", systemImage: "pencil")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private func revisionNavigationControl(_ state: MessageRevisionNavigationState) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectPreviousRevision()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(!state.canMovePrevious)
            .opacity(state.canMovePrevious ? 1 : 0.32)

            Text(state.displayText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 54)

            Button {
                onSelectNextRevision()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(!state.canMoveNext)
            .opacity(state.canMoveNext ? 1 : 0.32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizations.format(
            "accessibility.messageRevision",
            defaultValue: "Message version %@",
            arguments: [state.displayText]
        ))
    }

    private var assistantMessageStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.isContentCleared, !message.toolExchanges.isEmpty {
                toolActivityBlock
            }

            if !message.isContentCleared, hasReasoningContent {
                reasoningBlock
            }

            if message.isContentCleared {
                clearedContentBubble
            } else if shouldShowMessageContentBubble {
                messageContentBubble
            }

            if !message.isContentCleared, !isStreaming, let usageDisplayText {
                Text(usageDisplayText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            if showsActions, shouldShowAssistantActions {
                HStack(spacing: 8) {
                    if !displayContent.isEmpty {
                        Button {
                            onRegenerate()
                        } label: {
                            Label("重新生成", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }

                    if shouldOfferClearGeneratedContentAction {
                        Button(role: .destructive) {
                            onClearGeneratedContent()
                        } label: {
                            Label(
                                AppLocalizations.string("chat.message.clearAction", defaultValue: "清除"),
                                systemImage: "trash"
                            )
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.red.opacity(0.12)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private var shouldOfferClearGeneratedContentAction: Bool {
        !isUser && !isStreaming && !message.isContentCleared
    }

    private var shouldShowAssistantActions: Bool {
        !message.isContentCleared && (!displayContent.isEmpty || shouldOfferClearGeneratedContentAction)
    }

    private var clearedContentBubble: some View {
        Text(AppLocalizations.string(
            "chat.message.contentCleared",
            defaultValue: "此 AI 内容已在本机清除。"
        ))
        .font(.body)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(assistantBubbleColor)
        )
    }

    private var toolActivityTitleIsActive: Bool {
        guard isStreaming else { return false }

        return message.toolExchanges.contains { exchange in
            exchange.toolCalls.contains { call in
                !exchange.toolResults.contains { $0.toolCallID == call.id }
            }
        }
    }

    private var reasoningTitleIsActive: Bool {
        isStreaming && hasStreamingReasoning && !hasStreamingContent
    }

    private var toolActivityBlock: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.toolExchanges) { exchange in
                    ForEach(exchange.toolCalls) { call in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                Text(call.displayName.isEmpty ? call.name : call.displayName)
                                    .fontWeight(.semibold)
                            }

                            if let result = exchange.toolResults.first(where: { $0.toolCallID == call.id }) {
                                Text(result.isError
                                    ? AppLocalizations.string("toolCall.failed", defaultValue: "Call failed")
                                    : AppLocalizations.string("toolCall.completed", defaultValue: "Call completed"))
                                    .foregroundStyle(result.isError ? Color.red : Color.secondary)

                                toolResultContent(result)
                            } else {
                                Text(AppLocalizations.string("toolCall.calling", defaultValue: "Calling..."))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)

                MovingHighlightTitle(
                    text: AppLocalizations.string("toolCall.title", defaultValue: "Tool Calls"),
                    isActive: toolActivityTitleIsActive
                )

                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func toolResultContent(_ result: ChatToolResult) -> some View {
        let searchResults = result.isError ? [] : ToolSearchResultParser.results(from: result.content)

        if !searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(searchResults) { item in
                    Link(destination: item.url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption2.weight(.semibold))

                            Text(item.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(toolResultBackground)
        } else {
            let content = toolResultPreview(result.content)
            if !content.isEmpty {
                Text(content)
                    .font(.caption2.monospaced())
                    .foregroundStyle(result.isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(toolResultBackground)
            }
        }
    }

    private var toolResultBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05))
    }

    private func toolResultPreview(_ content: String) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        let limit = 4_000
        guard trimmedContent.count > limit else { return trimmedContent }
        return AppLocalizations.format(
            "toolResult.previewTruncated",
            defaultValue: "%@\n\n...(Result too long, display truncated)",
            arguments: [String(trimmedContent.prefix(limit))]
        )
    }

    private var messageImages: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88, maximum: 140), spacing: 8)],
            alignment: .trailing,
            spacing: 8
        ) {
            ForEach(message.imageAttachments) { attachment in
                ChatAttachmentImage(attachment: attachment)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
            }
        }
        .frame(width: imageGridWidth, alignment: .trailing)
        .onTapGesture {
            onSelect()
        }
    }

    private var messageFiles: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(message.fileAttachments) { attachment in
                ChatFileAttachmentChip(attachment: attachment)
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .onTapGesture {
            onSelect()
        }
    }

    private var imageGridWidth: CGFloat {
        let count = min(message.imageAttachments.count, 2)
        guard count > 0 else { return 0 }
        return CGFloat(count) * 112 + CGFloat(count - 1) * 8
    }

    private var reasoningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                message.isReasoningExpanded.toggle()
                onReasoningExpansionChanged(message.isReasoningExpanded)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: message.isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MovingHighlightTitle(
                        text: AppLocalizations.string("reasoning.title", defaultValue: "Reasoning"),
                        isActive: reasoningTitleIsActive
                    )
                        .font(.caption.weight(.semibold))

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if message.isReasoningExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ReasoningMessageContent(
                        content: displayReasoningContent,
                        chunks: displayReasoningChunks,
                        isStreaming: isStreaming,
                        streamingChannel: streamingReasoningChannel
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(assistantReasoningColor)
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
                .clipped()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .clipped()
    }
}
