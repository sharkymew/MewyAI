import Foundation
import SwiftUI

struct ActiveAgentCapsuleView: View {
    @Environment(\.colorScheme) private var colorScheme

    let capsule: ActiveAgentCapsule
    let onClose: () -> Void

    private var glassTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.18)
    }

    private var glassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.62)
    }

    var body: some View {
        let shape = Capsule()

        HStack(spacing: 8) {
            Image(systemName: capsule.icon)
                .font(.system(size: 17, weight: .semibold))

            Text(capsule.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.blue)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(glassTint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(glassTint))
                    .overlay(
                        shape
                            .stroke(glassHighlight, lineWidth: 1)
                            .blendMode(.screen)
                    )
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch capsule.kind {
        case .skill:
            return AppLocalizations.format(
                "accessibility.enabledSkill",
                defaultValue: "Enabled Skill: %@",
                arguments: [capsule.title]
            )
        case .mcp:
            return AppLocalizations.format(
                "accessibility.enabledMCP",
                defaultValue: "Enabled MCP: %@",
                arguments: [capsule.title]
            )
        case .knowledgeBase:
            return "已启用知识库：\(capsule.title)"
        }
    }
}
