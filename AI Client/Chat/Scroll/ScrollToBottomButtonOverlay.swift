import Foundation
import SwiftUI

struct ScrollToBottomButtonOverlay<Label: View>: View {
    @ObservedObject var scrollController: ChatScrollController
    let bottomPadding: CGFloat
    let label: () -> Label

    var body: some View {
        let adjustedBottomPadding = max(bottomPadding - ChatScrollMetrics.scrollToBottomButtonHitOutset, 0)
        ZStack {
            if scrollController.shouldShowScrollToBottomButton {
                Button {
                    scrollController.returnToBottom()
                } label: {
                    label()
                        .frame(
                            width: ChatScrollMetrics.scrollToBottomButtonHitSize,
                            height: ChatScrollMetrics.scrollToBottomButtonHitSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, adjustedBottomPadding)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: 0.18),
            value: scrollController.shouldShowScrollToBottomButton
        )
    }
}
