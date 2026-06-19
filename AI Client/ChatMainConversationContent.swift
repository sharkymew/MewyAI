import SwiftUI
import UIKit

struct ChatMainConversationContent<ChatScroll: View, TemporaryNotice: View, TopChrome: View, InputBar: View, ScrollButtonLabel: View>: View {
    @ObservedObject var scrollController: ChatScrollController
    @State private var keyboardAvoidanceState = KeyboardAvoidanceState()

    let topSafeAreaInset: CGFloat
    let topScrollContentPadding: CGFloat
    let bottomScrollContentPadding: CGFloat
    let scrollToBottomButtonBottomPadding: CGFloat
    let showsTemporaryChatNotice: Bool
    let chatScrollView: (CGFloat, CGFloat) -> ChatScroll
    let temporaryNotice: () -> TemporaryNotice
    let topChrome: (CGFloat) -> TopChrome
    let inputBar: () -> InputBar
    let scrollButtonLabel: () -> ScrollButtonLabel

    var body: some View {
        let effectiveBottomScrollContentPadding = bottomScrollContentPadding + keyboardAvoidanceState.bottomPadding
        let effectiveScrollToBottomButtonBottomPadding = scrollToBottomButtonBottomPadding + keyboardAvoidanceState.bottomPadding

        ZStack(alignment: .top) {
            chatScrollView(topScrollContentPadding, effectiveBottomScrollContentPadding)
                .ignoresSafeArea(.container, edges: [.top, .bottom])

            temporaryNotice()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 34)
                .padding(.top, topScrollContentPadding)
                .padding(.bottom, effectiveBottomScrollContentPadding)
                .opacity(showsTemporaryChatNotice ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!showsTemporaryChatNotice)
                .animation(.easeInOut(duration: 0.22), value: showsTemporaryChatNotice)

            topChrome(topSafeAreaInset)
        }
        .overlay(alignment: .bottom) {
            inputBar()
                .padding(.bottom, keyboardAvoidanceState.bottomPadding)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            scrollController.requestImmediateAutoScroll(animated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            scrollController.requestImmediateAutoScroll(animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            updateKeyboardAvoidance(to: 0, duration: 0, animates: false)
        }
        .overlay(alignment: .bottom) {
            ScrollToBottomButtonOverlay(
                scrollController: scrollController,
                bottomPadding: effectiveScrollToBottomButtonBottomPadding,
                label: scrollButtonLabel
            )
        }
        .background {
            KeyboardAvoidanceGuideReader { bottomPadding in
                updateKeyboardAvoidance(to: bottomPadding, duration: 0.25, animates: true)
            }
        }
    }

    private func updateKeyboardAvoidance(to bottomPadding: CGFloat, duration: TimeInterval, animates: Bool) {
        var nextState = keyboardAvoidanceState
        guard nextState.updateBottomPadding(bottomPadding) else { return }

        if animates, duration > 0 {
            withAnimation(.easeOut(duration: duration)) {
                keyboardAvoidanceState = nextState
            }
        } else {
            keyboardAvoidanceState = nextState
        }
    }
}
