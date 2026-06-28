import Foundation
import SwiftUI

extension View {
    @ViewBuilder
    func observeChatScrollUserInteraction(
        onBegin: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .interacting, .decelerating:
                    onBegin()
                case .idle:
                    onEnd()
                case .tracking, .animating:
                    break
                }
            }
        } else {
            simultaneousGesture(
                DragGesture(minimumDistance: ChatScrollMetrics.dragIntentMinimumDistance)
                    .onChanged { _ in
                        onBegin()
                    }
                    .onEnded { _ in
                        onEnd()
                    }
            )
        }
    }
}
