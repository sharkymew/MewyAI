import SwiftUI

struct ConversationSidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let conversations: [AIConversation]
    let selectedConversationID: UUID?
    let topSafeAreaInset: CGFloat
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onDelete: (UUID) -> Void
    let canCreateConversation: Bool

    private let topControlSize: CGFloat = 44
    private let topControlsTopPadding: CGFloat = 8
    private let topControlsHorizontalPadding: CGFloat = 16
    private let topFadeBottomPadding: CGFloat = 155
    private let topFadeVerticalOffset: CGFloat = -55

    private var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.14)
    }

    private var glassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : Color.white.opacity(0.74)
    }

    private var topFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.36) : Color.white.opacity(0.56)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if colorScheme == .dark {
            Color.clear
        } else {
            Color.white.opacity(0.94)
        }
    }

    private var topFadeHeight: CGFloat {
        topControlsTopPadding + topControlSize + topFadeBottomPadding
    }

    private func topScrollContentPadding(topSafeAreaInset: CGFloat) -> CGFloat {
        topSafeAreaInset + topControlsTopPadding + topControlSize + 18
    }

    @ViewBuilder
    private var fadeBase: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(Color.black)
        } else {
            Rectangle()
                .fill(.thickMaterial)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = geometry.size.width
            let rowWidth = max(0, sidebarWidth - 16)

            ZStack(alignment: .top) {
                sidebarBackground
                    .allowsHitTesting(false)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(conversations) { conversation in
                            conversationRow(conversation, rowWidth: rowWidth)
                        }
                    }
                    .padding(8)
                    .padding(.top, topScrollContentPadding(topSafeAreaInset: topSafeAreaInset))
                }

                topFade(topSafeAreaInset: topSafeAreaInset)
                    .frame(width: sidebarWidth, height: topSafeAreaInset + topFadeHeight)
                    .offset(y: topFadeVerticalOffset)
                    .ignoresSafeArea(edges: .top)

                topFloatingControls(topSafeAreaInset: topSafeAreaInset)
            }
            .frame(width: sidebarWidth, height: geometry.size.height, alignment: .top)
        }
        .clipped()
    }

    private func topFade(topSafeAreaInset: CGFloat) -> some View {
        fadeBase
            .overlay(topFadeTint)
            .mask(
                FunctionOpacityMask(
                    topOpacity: 0.90,
                    maxOpacity: 0.90,
                    fadeInEnd: 0.22,
                    holdEnd: 0.48,
                    fadeOutEnd: 0.88
                )
            )
            .allowsHitTesting(false)
    }

    private func topFloatingControls(topSafeAreaInset: CGFloat) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            topGlassControl {
                Button(action: onCreate) {
                    topIconLabel(systemName: "plus")
                }
            }
            .disabled(!canCreateConversation)
            .accessibilityLabel("新建对话")
        }
        .padding(.horizontal, topControlsHorizontalPadding)
        .padding(.top, topSafeAreaInset + topControlsTopPadding)
    }

    @ViewBuilder
    private func topGlassControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .buttonStyle(
                FixedTopGlassButtonStyle(
                    tint: glassTint,
                    highlight: glassHighlight
                )
            )
    }

    private func topIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: topControlSize, height: topControlSize)
            .contentShape(Circle())
    }

    private func conversationRow(_ conversation: AIConversation, rowWidth: CGFloat) -> some View {
        let isSelected = conversation.id == selectedConversationID

        return HStack(spacing: 8) {
            Button {
                onSelect(conversation.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete(conversation.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0.64)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(width: rowWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipped()
    }
}
