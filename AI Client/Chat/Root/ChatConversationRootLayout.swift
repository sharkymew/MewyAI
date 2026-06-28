import SwiftUI

struct ChatConversationRootLayout<MainContent: View, SidebarToggle: View, ExpandedInput: View>: View {
    @Binding var isSidebarVisible: Bool

    let conversations: [AIConversation]
    let conversationForSearch: (AIConversation) -> AIConversation
    let selectedConversationID: UUID?
    let showsSidebarToggleFadeExclusion: Bool
    let transitionDuration: Double
    let isExpandedInputPresented: Bool
    let onOverlayClose: () -> Void
    let onEdgeOpen: () -> Void
    let onSidebarClose: () -> Void
    let onSelectConversation: (UUID, Bool) -> Void
    let onOpenConfiguration: (Bool) -> Void
    let onRenameConversation: (UUID) -> Void
    let onTogglePinnedConversation: (UUID) -> Void
    let onExportConversation: (UUID) -> Void
    let onDeleteConversation: (UUID) -> Void
    let mainContent: (CGFloat) -> MainContent
    let sidebarToggle: () -> SidebarToggle
    let expandedInput: () -> ExpandedInput

    var body: some View {
        GeometryReader { geometry in
            let layout = SidebarLayout.layout(for: geometry.size)
            let showsOverlaySidebar = isSidebarVisible && !layout.usesPersistentSidebar
            let showsSidebar = isSidebarVisible || layout.usesPersistentSidebar

            ZStack(alignment: .leading) {
                mainContent(geometry.safeAreaInsets.top)
                    .frame(width: layout.mainContentWidth)
                    .disabled(showsOverlaySidebar)
                    .offset(x: layout.mainContentOffsetX(isOverlayVisible: showsOverlaySidebar))
                    .animation(.easeOut(duration: transitionDuration), value: isSidebarVisible)

                if showsOverlaySidebar {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture(perform: onOverlayClose)
                }

                if !isSidebarVisible && !layout.usesPersistentSidebar {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 28)
                        .ignoresSafeArea()
                        .gesture(openSidebarGesture)
                }

                ConversationSidebarView(
                    conversations: conversations,
                    conversationForSearch: conversationForSearch,
                    selectedConversationID: selectedConversationID,
                    topSafeAreaInset: geometry.safeAreaInsets.top,
                    showsSidebarToggleFadeExclusion: showsSidebarToggleFadeExclusion && !layout.usesPersistentSidebar,
                    showsCloseButton: false,
                    onSelect: { id in
                        onSelectConversation(id, !layout.usesPersistentSidebar)
                    },
                    onClose: onSidebarClose,
                    onOpenConfiguration: {
                        onOpenConfiguration(!layout.usesPersistentSidebar)
                    },
                    onRename: onRenameConversation,
                    onTogglePinned: onTogglePinnedConversation,
                    onExport: onExportConversation,
                    onDelete: onDeleteConversation
                )
                .frame(width: layout.sidebarWidth)
                .ignoresSafeArea(edges: [.top, .bottom])
                .offset(x: showsSidebar ? 0 : -layout.sidebarWidth)
                .animation(.easeOut(duration: transitionDuration), value: isSidebarVisible)

                if !layout.usesPersistentSidebar {
                    sidebarToggle()
                }
            }
            .simultaneousGesture(closeSidebarGesture)
        }
        .overlay {
            if isExpandedInputPresented {
                expandedInput()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        )
                    )
                    .zIndex(1000)
            }
        }
    }

    private var openSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if !isSidebarVisible,
                   value.translation.width > 46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.6 {
                    onEdgeOpen()
                }
            }
    }

    private var closeSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                if isSidebarVisible,
                   value.translation.width < -46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    onOverlayClose()
                }
            }
    }
}
