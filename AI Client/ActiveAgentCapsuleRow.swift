import SwiftUI

struct ActiveAgentCapsuleRow: View {
    static let fallbackHeight: CGFloat = 46

    let capsules: [ActiveAgentCapsule]
    let onDeactivate: (ActiveAgentCapsule) -> Void

    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(capsules) { capsule in
                    ActiveAgentCapsuleView(capsule: capsule) {
                        onDeactivate(capsule)
                    }
                }
            }
            .padding(.horizontal, 6)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ActiveAgentCapsuleRowHeightPreferenceKey.self,
                        value: ChatScrollMetrics.roundedDistance(geometry.size.height)
                    )
                }
            }
        }
        .frame(height: rowHeight)
        .onPreferenceChange(ActiveAgentCapsuleRowHeightPreferenceKey.self) { height in
            guard height > 0, abs(measuredContentHeight - height) > 0.5 else { return }
            measuredContentHeight = height
        }
    }

    private var rowHeight: CGFloat {
        measuredContentHeight > 0 ? measuredContentHeight : Self.fallbackHeight
    }
}

private struct ActiveAgentCapsuleRowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
