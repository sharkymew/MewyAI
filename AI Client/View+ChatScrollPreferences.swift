import Foundation
import SwiftUI

extension View {
    func glassFadeExclusion(inset: CGFloat) -> some View {
        anchorPreference(key: GlassFadeExclusionPreferenceKey.self, value: .bounds) { bounds in
            [GlassFadeExclusion(bounds: bounds, inset: inset)]
        }
    }

    @ViewBuilder
    func observeChatScrollBottomDistance(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(
                for: CGFloat.self,
                of: { geometry in
                    ChatScrollMetrics.roundedDistance(geometry.contentSize.height - geometry.visibleRect.maxY)
                },
                action: { _, distanceFromBottom in
                    action(distanceFromBottom)
                }
            )
        } else {
            onPreferenceChange(ChatScrollBottomDistancePreferenceKey.self) { distanceFromBottom in
                action(distanceFromBottom)
            }
        }
    }
}
