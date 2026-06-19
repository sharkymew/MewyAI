import Foundation
import SwiftUI

struct FixedTopGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.46)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: Capsule())
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(tint))
                        .overlay(
                            Capsule()
                                .stroke(highlight, lineWidth: 1)
                                .blendMode(.screen)
                        )
                }
            }
            .scaleEffect(configuration.isPressed ? 1.05 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
