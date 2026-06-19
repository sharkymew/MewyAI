import Foundation
import SwiftUI

struct MovingHighlightTitle: View {
    let text: String
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isActive && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let cycle = 1.35
                let progress = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycle) / cycle
                let startX = progress * 2.2 - 1.1

                Text(text)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                baseColor,
                                highlightColor,
                                baseColor
                            ],
                            startPoint: UnitPoint(x: startX, y: 0.5),
                            endPoint: UnitPoint(x: startX + 0.72, y: 0.5)
                        )
                    )
            }
        } else {
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var baseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.52) : Color.secondary
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary.opacity(0.90)
    }
}
