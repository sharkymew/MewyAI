import SwiftUI

struct ChatMessageScrollView: View {
    @Binding var messages: [ChatMessage]
    @Binding var messageInteraction: MessageInteractionState
    @ObservedObject var scrollController: ChatScrollController

    let isGenerating: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let visibleAssistantDisplayState: (UUID) -> ChatSessionViewModel.VisibleAssistantDisplayState
    let markdownRenderCacheEntry: (UUID) -> MarkdownRenderCacheEntry?
    let usageFooterText: (ChatMessage) -> String?
    let revisionNavigationState: (UUID) -> MessageRevisionNavigationState?
    let onReasoningExpansionChanged: (UUID, Bool) -> Void
    let onRegenerate: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onSelectPreviousRevision: (UUID) -> Void
    let onSelectNextRevision: (UUID) -> Void
    let onHideKeyboard: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { scrollGeometry in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($messages) { $message in
                            let streamingDisplay = visibleAssistantDisplayState(message.id)
                            let revisionNavigation = isGenerating ? nil : revisionNavigationState(message.id)

                            MessageBubble(
                                message: $message,
                                isStreaming: streamingDisplay.isStreaming,
                                hasStreamingReasoning: streamingDisplay.hasStreamingReasoning,
                                hasStreamingContent: streamingDisplay.hasStreamingContent,
                                streamingContentChannel: streamingDisplay.streamingContentChannel,
                                streamingReasoningChannel: streamingDisplay.streamingReasoningChannel,
                                markdownRenderCache: markdownRenderCacheEntry(message.id),
                                usageDisplayText: usageFooterText(message),
                                showsActions: messageInteraction.activeActionID == message.id,
                                revisionNavigationState: revisionNavigation,
                                onSelect: {
                                    selectMessageAction(for: message.id)
                                },
                                onReasoningExpansionChanged: { isExpanded in
                                    onReasoningExpansionChanged(message.id, isExpanded)
                                },
                                onRegenerate: {
                                    onRegenerate(message.id)
                                },
                                onEdit: {
                                    onEdit(message.id)
                                },
                                onSelectPreviousRevision: {
                                    onSelectPreviousRevision(message.id)
                                },
                                onSelectNextRevision: {
                                    onSelectNextRevision(message.id)
                                }
                            )
                            .id(message.id)
                        }

                        bottomAnchor(viewportHeight: scrollGeometry.size.height)
                    }
                    .padding(.horizontal)
                    .padding(.top, topPadding)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: scrollGeometry.size.height,
                        alignment: .top
                    )
                    .contentShape(Rectangle())
                }
                .coordinateSpace(name: ChatScrollMetrics.coordinateSpaceName)
                .observeChatScrollUserInteraction(
                    onBegin: {
                        scrollController.beginUserScrollInteraction()
                    },
                    onEnd: {
                        scrollController.endUserScrollInteraction()
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        handleScrollTap()
                    }
                )
                .onChange(of: messages.count) { _, _ in
                    scrollController.requestImmediateAutoScroll(animated: true)
                }
                .observeChatScrollBottomDistance { distanceFromBottom in
                    scrollController.scheduleBottomDistanceUpdate(distanceFromBottom)
                }
                .onAppear {
                    scrollController.setScrollAction { animated in
                        forceScrollToBottom(proxy: proxy, animated: animated)
                    }
                    scrollController.requestImmediateAutoScroll(animated: false)
                }
                .onDisappear {
                    scrollController.clearScrollAction()
                }
            }
        }
    }

    @ViewBuilder
    private func bottomAnchor(viewportHeight: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            Color.clear
                .frame(height: bottomPadding)
                .id("bottomAnchor")
        } else {
            Color.clear
                .frame(height: bottomPadding)
                .id("bottomAnchor")
                .background(
                    GeometryReader { bottomGeometry in
                        Color.clear.preference(
                            key: ChatScrollBottomDistancePreferenceKey.self,
                            value: chatScrollBottomDistance(
                                bottomGeometry: bottomGeometry,
                                viewportHeight: viewportHeight
                            )
                        )
                    }
                )
        }
    }

    private func selectMessageAction(for id: UUID) {
        messageInteraction.didTapBubble = true
        guard messageInteraction.activeActionID != id else { return }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                messageInteraction.activeActionID = id
            }
        }
    }

    private func handleScrollTap() {
        DispatchQueue.main.async {
            if messageInteraction.didTapBubble {
                messageInteraction.didTapBubble = false
                return
            }

            onHideKeyboard()

            withAnimation(.easeOut(duration: 0.16)) {
                messageInteraction.activeActionID = nil
            }
        }
    }

    private func chatScrollBottomDistance(bottomGeometry: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let bottomY = bottomGeometry.frame(in: .named(ChatScrollMetrics.coordinateSpaceName)).maxY
        return ChatScrollMetrics.roundedDistance(bottomY - viewportHeight)
    }

    private func forceScrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }
}
