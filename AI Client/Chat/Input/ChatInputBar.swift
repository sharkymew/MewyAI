import SwiftUI
import UniformTypeIdentifiers

struct ChatInputBar<ActiveAgentCapsules: View, PendingAttachmentPreview: View, Composer: View, LegacyFade: View>: View {
    let showsActiveAgentCapsules: Bool
    let showsPendingAttachments: Bool
    let imageSelectionError: String?
    let speechInputError: String?
    let isEditingMessage: Bool
    let inputGlassTint: Color
    let inputGlassHighlight: Color
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    @Binding var isAttachmentDropTargeted: Bool
    let onDropAttachments: ([NSItemProvider]) -> Bool
    let onMeasuredHeightChanged: (CGFloat) -> Void
    let activeAgentCapsules: () -> ActiveAgentCapsules
    let pendingAttachmentPreview: () -> PendingAttachmentPreview
    let composer: () -> Composer
    let legacyFade: () -> LegacyFade

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsActiveAgentCapsules {
                activeAgentCapsules()
                    .padding(.horizontal, 6)
            }

            ChatInputGlassContainer(
                cornerRadius: cornerRadius,
                tint: inputGlassTint,
                highlight: inputGlassHighlight
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if showsPendingAttachments {
                        pendingAttachmentPreview()
                    }

                    if let imageSelectionError {
                        Text(imageSelectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                    }

                    if let speechInputError {
                        Text(speechInputError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                    }

                    if isEditingMessage {
                        Text("正在修改消息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }

                    composer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isAttachmentDropTargeted ? Color.accentColor.opacity(0.56) : Color.secondary.opacity(0.12),
                        lineWidth: isAttachmentDropTargeted ? 2 : 1
                    )
            )
            .onDrop(
                of: [UTType.image.identifier] + ChatFileAttachmentReader.dropTypeIdentifiers,
                isTargeted: $isAttachmentDropTargeted,
                perform: onDropAttachments
            )

            inputDisclaimer
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(alignment: .bottom) {
            legacyFade()
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InputBarHeightPreferenceKey.self,
                    value: ChatScrollMetrics.roundedDistance(geometry.size.height)
                )
            }
        }
        .onPreferenceChange(InputBarHeightPreferenceKey.self, perform: onMeasuredHeightChanged)
    }

    private var inputDisclaimer: some View {
        Text("AI也有可能出错，输出仅供参考，请亲自核查重要信息。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
    }
}

private struct ChatInputGlassContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    let highlight: Color
    let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content()
                .background {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: shape)
                }
        } else {
            content()
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint))
                .overlay(
                    shape
                        .stroke(highlight, lineWidth: 1)
                        .blendMode(.screen)
                )
        }
    }
}
