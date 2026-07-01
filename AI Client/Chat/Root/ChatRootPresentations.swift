import PhotosUI
import SwiftUI

struct ChatRootPresentations: ViewModifier {
    @Binding var showConfiguration: Bool
    @Binding var showPromptSettings: Bool
    @Binding var showAgentCapabilities: Bool
    @Binding var conversationRenameDraft: ConversationRenameDraft
    @Binding var conversationExportDraft: ConversationExportDraft
    @Binding var conversationSaveErrorMessage: String?
    @Binding var pendingClearGeneratedContentMessageID: UUID?
    @Binding var attachmentDraft: ChatAttachmentDraft

    let promptConfigurationID: UUID
    let pendingToolApproval: PendingToolApproval?
    let toolApprovalMessage: String
    let onResetRenamingConversation: () -> Void
    let onCommitRenamingConversation: () -> Void
    let onConfirmClearGeneratedContent: () -> Void
    let onResolveToolApproval: (Bool) -> Void
    let onLoadSelectedFiles: (Result<[URL], Error>) -> Void
    let onConfigurationDismissed: () -> Void
    let onPromptSettingsDismissed: () -> Void
    let onAgentCapabilitiesDismissed: () -> Void
    let onSelectedPhotoItemsChanged: ([PhotosPickerItem]) -> Void
    let onCameraImageCaptured: @MainActor @Sendable (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showConfiguration) {
                AIConfigurationView()
            }
            .sheet(isPresented: $showPromptSettings) {
                AIPromptSettingsView(configurationID: promptConfigurationID)
            }
            .sheet(isPresented: $showAgentCapabilities) {
                AgentCapabilitiesView()
            }
            .alert("重命名对话", isPresented: $conversationRenameDraft.isPresented) {
                TextField("名称", text: $conversationRenameDraft.title)

                Button("取消", role: .cancel, action: onResetRenamingConversation)
                Button("保存", action: onCommitRenamingConversation)
            } message: {
                Text("请输入新的对话名称。")
            }
            .alert("导出失败", isPresented: conversationExportErrorPresented) {
                Button("好", role: .cancel) {
                    conversationExportDraft.clearError()
                }
            } message: {
                Text(conversationExportDraft.errorMessage ?? "")
            }
            .alert("保存失败", isPresented: conversationSaveErrorPresented) {
                Button("好", role: .cancel) {
                    conversationSaveErrorMessage = nil
                }
            } message: {
                Text(conversationSaveErrorMessage ?? "")
            }
            .alert(
                AppLocalizations.string("chat.message.clearConfirmationTitle", defaultValue: "清除 AI 内容？"),
                isPresented: clearGeneratedContentPresented
            ) {
                Button(AppLocalizations.string("取消", defaultValue: "取消"), role: .cancel) {
                    pendingClearGeneratedContentMessageID = nil
                }
                Button(
                    AppLocalizations.string("chat.message.clearConfirm", defaultValue: "清除内容"),
                    role: .destructive,
                    action: onConfirmClearGeneratedContent
                )
            } message: {
                Text(AppLocalizations.string(
                    "chat.message.clearConfirmationMessage",
                    defaultValue: "这会在本机清除该条 AI 生成内容，不会上传聊天内容或清除记录。"
                ))
            }
            .alert(
                "允许工具调用？",
                isPresented: toolApprovalPresented
            ) {
                Button("拒绝", role: .cancel) {
                    onResolveToolApproval(false)
                }
                Button("允许") {
                    onResolveToolApproval(true)
                }
            } message: {
                Text(toolApprovalMessage)
            }
            .photosPicker(
                isPresented: $attachmentDraft.isPhotoPickerPresented,
                selection: $attachmentDraft.selectedPhotoItems,
                maxSelectionCount: ChatAttachmentDraft.maxImageAttachmentCount,
                matching: .images
            )
            .fullScreenCover(isPresented: $attachmentDraft.isCameraPresented) {
                CameraCaptureViewController(
                    onCaptured: { image in
                        onCameraImageCaptured(image)
                    },
                    onCancel: {
                        attachmentDraft.isCameraPresented = false
                    }
                )
                .presentationBackground(.black)
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $attachmentDraft.isFileImporterPresented,
                allowedContentTypes: ChatFileAttachmentReader.supportedDocumentTypes,
                allowsMultipleSelection: true,
                onCompletion: onLoadSelectedFiles
            )
            .fileExporter(
                isPresented: $conversationExportDraft.isPresented,
                document: conversationExportDraft.document,
                contentType: ConversationMarkdownDocument.contentType,
                defaultFilename: conversationExportDraft.fileName,
                onCompletion: { result in
                    conversationExportDraft.handleCompletion(result)
                }
            )
            .onChange(of: showConfiguration) { _, isPresented in
                if !isPresented {
                    onConfigurationDismissed()
                }
            }
            .onChange(of: showPromptSettings) { _, isPresented in
                if !isPresented {
                    onPromptSettingsDismissed()
                }
            }
            .onChange(of: showAgentCapabilities) { _, isPresented in
                if !isPresented {
                    onAgentCapabilitiesDismissed()
                }
            }
            .onChange(of: attachmentDraft.selectedPhotoItems) { _, newItems in
                onSelectedPhotoItemsChanged(newItems)
            }
    }

    private var conversationExportErrorPresented: Binding<Bool> {
        Binding {
            conversationExportDraft.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                conversationExportDraft.clearError()
            }
        }
    }

    private var conversationSaveErrorPresented: Binding<Bool> {
        Binding {
            conversationSaveErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                conversationSaveErrorMessage = nil
            }
        }
    }

    private var clearGeneratedContentPresented: Binding<Bool> {
        Binding {
            pendingClearGeneratedContentMessageID != nil
        } set: { isPresented in
            if !isPresented {
                pendingClearGeneratedContentMessageID = nil
            }
        }
    }

    private var toolApprovalPresented: Binding<Bool> {
        Binding {
            pendingToolApproval != nil
        } set: { isPresented in
            if !isPresented {
                onResolveToolApproval(false)
            }
        }
    }
}

extension View {
    func chatRootPresentations(
        showConfiguration: Binding<Bool>,
        showPromptSettings: Binding<Bool>,
        showAgentCapabilities: Binding<Bool>,
        conversationRenameDraft: Binding<ConversationRenameDraft>,
        conversationExportDraft: Binding<ConversationExportDraft>,
        conversationSaveErrorMessage: Binding<String?>,
        pendingClearGeneratedContentMessageID: Binding<UUID?>,
        attachmentDraft: Binding<ChatAttachmentDraft>,
        promptConfigurationID: UUID,
        pendingToolApproval: PendingToolApproval?,
        toolApprovalMessage: String,
        onResetRenamingConversation: @escaping () -> Void,
        onCommitRenamingConversation: @escaping () -> Void,
        onConfirmClearGeneratedContent: @escaping () -> Void,
        onResolveToolApproval: @escaping (Bool) -> Void,
        onLoadSelectedFiles: @escaping (Result<[URL], Error>) -> Void,
        onConfigurationDismissed: @escaping () -> Void,
        onPromptSettingsDismissed: @escaping () -> Void,
        onAgentCapabilitiesDismissed: @escaping () -> Void,
        onSelectedPhotoItemsChanged: @escaping ([PhotosPickerItem]) -> Void,
        onCameraImageCaptured: @escaping @MainActor @Sendable (UIImage) -> Void
    ) -> some View {
        modifier(ChatRootPresentations(
            showConfiguration: showConfiguration,
            showPromptSettings: showPromptSettings,
            showAgentCapabilities: showAgentCapabilities,
            conversationRenameDraft: conversationRenameDraft,
            conversationExportDraft: conversationExportDraft,
            conversationSaveErrorMessage: conversationSaveErrorMessage,
            pendingClearGeneratedContentMessageID: pendingClearGeneratedContentMessageID,
            attachmentDraft: attachmentDraft,
            promptConfigurationID: promptConfigurationID,
            pendingToolApproval: pendingToolApproval,
            toolApprovalMessage: toolApprovalMessage,
            onResetRenamingConversation: onResetRenamingConversation,
            onCommitRenamingConversation: onCommitRenamingConversation,
            onConfirmClearGeneratedContent: onConfirmClearGeneratedContent,
            onResolveToolApproval: onResolveToolApproval,
            onLoadSelectedFiles: onLoadSelectedFiles,
            onConfigurationDismissed: onConfigurationDismissed,
            onPromptSettingsDismissed: onPromptSettingsDismissed,
            onAgentCapabilitiesDismissed: onAgentCapabilitiesDismissed,
            onSelectedPhotoItemsChanged: onSelectedPhotoItemsChanged,
            onCameraImageCaptured: onCameraImageCaptured
        ))
    }
}
