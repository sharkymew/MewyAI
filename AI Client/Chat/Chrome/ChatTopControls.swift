import SwiftUI

struct ChatTopFloatingControls<TitleMenu: View>: View {
    let canCreateConversation: Bool
    let showsTemporaryChatNotice: Bool
    let actionSystemImage: String
    let actionAccessibilityLabel: String
    let actionAccessibilityHint: String
    let controlSize: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let glassTint: Color
    let glassHighlight: Color
    let glassFadeExclusionInset: CGFloat
    let onAction: () -> Void
    let titleMenu: () -> TitleMenu

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                ChatTopGlassControl(
                    tint: glassTint,
                    highlight: glassHighlight,
                    fadeExclusionInset: glassFadeExclusionInset
                ) {
                    Button(action: onAction) {
                        ChatTopConversationActionLabel(
                            showsTemporaryChatNotice: showsTemporaryChatNotice,
                            systemName: actionSystemImage,
                            controlSize: controlSize
                        )
                    }
                }
                .disabled(!canCreateConversation)
                .accessibilityLabel(actionAccessibilityLabel)
                .accessibilityHint(actionAccessibilityHint)
            }

            titleMenu()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
    }
}

struct ChatSidebarToggleControl: View {
    let isSidebarVisible: Bool
    let controlSize: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let glassTint: Color
    let glassHighlight: Color
    let glassFadeExclusionInset: CGFloat
    let onToggle: () -> Void

    var body: some View {
        VStack {
            HStack {
                ChatTopGlassControl(
                    tint: glassTint,
                    highlight: glassHighlight,
                    fadeExclusionInset: glassFadeExclusionInset
                ) {
                    Button(action: onToggle) {
                        ChatTopIconLabel(
                            systemName: "sidebar.left",
                            controlSize: controlSize
                        )
                    }
                }
                .accessibilityLabel(isSidebarVisible
                    ? AppLocalizations.string("accessibility.closeConversationList", defaultValue: "Close conversation list")
                    : AppLocalizations.string("accessibility.openConversationList", defaultValue: "Open conversation list"))

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
    }
}

private struct ChatTopConversationActionLabel: View {
    let showsTemporaryChatNotice: Bool
    let systemName: String
    let controlSize: CGFloat

    var body: some View {
        if showsTemporaryChatNotice {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text("临时")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(height: controlSize)
            .padding(.horizontal, 13)
            .contentShape(Capsule())
        } else {
            ChatTopIconLabel(
                systemName: systemName,
                controlSize: controlSize
            )
        }
    }
}
