import SwiftUI

struct ChatCircularGlassIconLabel: View {
    let systemName: String
    let size: CGFloat
    let weight: Font.Weight
    let frame: CGFloat
    let tint: Color
    let highlight: Color
    var foreground: Color = .primary

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(tint))
                .overlay(
                    Circle()
                        .stroke(highlight, lineWidth: 1)
                )

            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(foreground)
        }
        .frame(width: frame, height: frame)
    }
}

struct ChatScrollToBottomGlassIconLabel: View {
    let tint: Color
    let highlight: Color

    var body: some View {
        let shape = Circle()

        ZStack {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(tint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint))
                    .overlay(
                        shape
                            .stroke(highlight, lineWidth: 1)
                            .blendMode(.screen)
                    )
            }

            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 36, height: 36)
    }
}

struct ChatTopGlassControl<Content: View>: View {
    let tint: Color
    let highlight: Color
    let fadeExclusionInset: CGFloat
    let content: () -> Content

    var body: some View {
        content()
            .buttonStyle(
                FixedTopGlassButtonStyle(
                    tint: tint,
                    highlight: highlight
                )
            )
            .glassFadeExclusion(inset: fadeExclusionInset)
    }
}

struct ChatTopIconLabel: View {
    let systemName: String
    let controlSize: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
    }
}

struct ChatInputBottomFadeBackdrop: View {
    let colorScheme: ColorScheme
    let tint: Color
    let fadeHeight: CGFloat
    let fadeOverlap: CGFloat
    let inputBottomPadding: CGFloat
    let scrollButtonBottomPadding: CGFloat
    let scrollButtonFadeExclusionSize: CGFloat
    let showsScrollToBottomButton: Bool

    var body: some View {
        GeometryReader { geometry in
            let fadeTop = geometry.size.height - fadeOverlap - inputBottomPadding
            let scrollButtonCenterY = geometry.size.height
                - max(scrollButtonBottomPadding - ChatScrollMetrics.scrollToBottomButtonHitOutset, 0)
                - ChatScrollMetrics.scrollToBottomButtonHitSize / 2

            ZStack(alignment: .topLeading) {
                ChatInputBottomFade(colorScheme: colorScheme, tint: tint)
                    .frame(width: geometry.size.width, height: fadeHeight)
                    .offset(y: fadeTop)

                if showsScrollToBottomButton {
                    Circle()
                        .frame(
                            width: scrollButtonFadeExclusionSize,
                            height: scrollButtonFadeExclusionSize
                        )
                        .position(x: geometry.size.width / 2, y: scrollButtonCenterY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

struct ChatTopChrome<Controls: View>: View {
    let colorScheme: ColorScheme
    let tint: Color
    let topSafeAreaInset: CGFloat
    let fadeHeight: CGFloat
    let controlSize: CGFloat
    let controlsTopPadding: CGFloat
    let controlsHorizontalPadding: CGFloat
    let sidebarToggleExclusionLeadingOffset: CGFloat
    let glassFadeExclusionInset: CGFloat
    let showsSidebarToggleExclusion: Bool
    let controls: () -> Controls

    var body: some View {
        controls()
            .frame(maxWidth: .infinity, maxHeight: fadeHeight, alignment: .top)
            .backgroundPreferenceValue(GlassFadeExclusionPreferenceKey.self) { exclusions in
                GeometryReader { proxy in
                    fadeBackdrop(exclusions: exclusions, proxy: proxy)
                }
            }
    }

    private func fadeBackdrop(
        exclusions: [GlassFadeExclusion],
        proxy: GeometryProxy
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ChatTopFade(colorScheme: colorScheme, tint: tint)
                .frame(width: proxy.size.width, height: topSafeAreaInset + fadeHeight)
                .offset(y: -topSafeAreaInset)
                .ignoresSafeArea(edges: .top)

            Capsule()
                .frame(
                    width: max(controlSize - glassFadeExclusionInset * 2, 0),
                    height: max(controlSize - glassFadeExclusionInset * 2, 0)
                )
                .position(
                    x: controlsHorizontalPadding + sidebarToggleExclusionLeadingOffset + controlSize / 2,
                    y: controlsTopPadding + controlSize / 2
                )
                .opacity(showsSidebarToggleExclusion ? 1 : 0)
                .blendMode(.destinationOut)

            ForEach(Array(exclusions.enumerated()), id: \.offset) { _, exclusion in
                let rect = proxy[exclusion.bounds]

                Capsule()
                    .frame(
                        width: max(rect.width - exclusion.inset * 2, 0),
                        height: max(rect.height - exclusion.inset * 2, 0)
                    )
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

private struct ChatInputBottomFade: View {
    let colorScheme: ColorScheme
    let tint: Color

    var body: some View {
        ChatFadeBase(colorScheme: colorScheme)
            .overlay(tint)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.08), location: 0.00),
                        .init(color: .black.opacity(0.18), location: 0.10),
                        .init(color: .black.opacity(0.36), location: 0.24),
                        .init(color: .black.opacity(0.66), location: 0.48),
                        .init(color: .black.opacity(0.90), location: 0.72),
                        .init(color: .black.opacity(1.00), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

private struct ChatTopFade: View {
    let colorScheme: ColorScheme
    let tint: Color

    var body: some View {
        ChatFadeBase(colorScheme: colorScheme)
            .overlay(tint)
            .mask(
                FunctionOpacityMask(
                    topOpacity: 0.28,
                    maxOpacity: 0.90,
                    fadeInEnd: 0.22,
                    holdEnd: 0.48,
                    fadeOutEnd: 0.88
                )
            )
            .allowsHitTesting(false)
    }
}

private struct ChatFadeBase: View {
    let colorScheme: ColorScheme

    var body: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(Color.black)
        } else {
            Rectangle()
                .fill(.thickMaterial)
        }
    }
}
