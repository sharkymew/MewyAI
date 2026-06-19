import SwiftUI
import UIKit

struct ChatMainConversationContent<ChatScroll: View, TemporaryNotice: View, TopChrome: View, InputBar: View, ScrollButtonLabel: View>: View {
    @ObservedObject var scrollController: ChatScrollController

    let topSafeAreaInset: CGFloat
    let topScrollContentPadding: CGFloat
    let bottomScrollContentPadding: CGFloat
    let scrollToBottomButtonBottomPadding: CGFloat
    let showsTemporaryChatNotice: Bool
    let chatScrollView: (CGFloat) -> ChatScroll
    let temporaryNotice: () -> TemporaryNotice
    let topChrome: (CGFloat) -> TopChrome
    let inputBar: () -> InputBar
    let scrollButtonLabel: () -> ScrollButtonLabel

    var body: some View {
        ZStack(alignment: .top) {
            chatScrollView(topScrollContentPadding)
                .ignoresSafeArea(.container, edges: [.top, .bottom])

            temporaryNotice()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 34)
                .padding(.top, topScrollContentPadding)
                .padding(.bottom, bottomScrollContentPadding)
                .opacity(showsTemporaryChatNotice ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!showsTemporaryChatNotice)
                .animation(.easeInOut(duration: 0.22), value: showsTemporaryChatNotice)

            topChrome(topSafeAreaInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0, content: inputBar)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            scrollController.requestImmediateAutoScroll(animated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            scrollController.requestImmediateAutoScroll(animated: false)
        }
        .overlay(alignment: .bottom) {
            ScrollToBottomButtonOverlay(
                scrollController: scrollController,
                bottomPadding: scrollToBottomButtonBottomPadding,
                label: scrollButtonLabel
            )
        }
    }
}
