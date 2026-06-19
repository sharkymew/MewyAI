import Foundation
import SwiftUI

struct ChatInputComposer<OptionsMenu: View>: View {
    @ObservedObject var inputDraft: ChatInputDraft
    @Environment(\.colorScheme) private var colorScheme

    let isGenerating: Bool
    let isEditingMessage: Bool
    let isSpeechRecording: Bool
    let hasPendingAttachments: Bool
    let inputGlassTint: Color
    let controlGlassHighlight: Color
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onExpandInput: () -> Void
    let onToggleSpeechInput: () -> Void
    let onStopGenerating: () -> Void
    let onSendMessage: () -> Void
    let onCancelEditingMessage: () -> Void
    let onSaveEditingMessageOnly: () -> Void
    let onSaveEditingMessageAndRegenerate: () -> Void
    let optionsMenu: () -> OptionsMenu

    init(
        inputDraft: ChatInputDraft,
        isGenerating: Bool,
        isEditingMessage: Bool,
        isSpeechRecording: Bool,
        hasPendingAttachments: Bool,
        inputGlassTint: Color,
        controlGlassHighlight: Color,
        onPasteImageProviders: @escaping ([NSItemProvider]) -> Void,
        onExpandInput: @escaping () -> Void,
        onToggleSpeechInput: @escaping () -> Void,
        onStopGenerating: @escaping () -> Void,
        onSendMessage: @escaping () -> Void,
        onCancelEditingMessage: @escaping () -> Void,
        onSaveEditingMessageOnly: @escaping () -> Void,
        onSaveEditingMessageAndRegenerate: @escaping () -> Void,
        @ViewBuilder optionsMenu: @escaping () -> OptionsMenu
    ) {
        self.inputDraft = inputDraft
        self.isGenerating = isGenerating
        self.isEditingMessage = isEditingMessage
        self.isSpeechRecording = isSpeechRecording
        self.hasPendingAttachments = hasPendingAttachments
        self.inputGlassTint = inputGlassTint
        self.controlGlassHighlight = controlGlassHighlight
        self.onPasteImageProviders = onPasteImageProviders
        self.onExpandInput = onExpandInput
        self.onToggleSpeechInput = onToggleSpeechInput
        self.onStopGenerating = onStopGenerating
        self.onSendMessage = onSendMessage
        self.onCancelEditingMessage = onCancelEditingMessage
        self.onSaveEditingMessageOnly = onSaveEditingMessageOnly
        self.onSaveEditingMessageAndRegenerate = onSaveEditingMessageAndRegenerate
        self.optionsMenu = optionsMenu
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            optionsMenu()

            textInputArea

            speechInputControl

            inputActionControl
        }
    }

    private var textInputArea: some View {
        ZStack(alignment: .topTrailing) {
            ImagePastingTextView(
                text: inputDraft.text,
                textRevision: inputDraft.textRevision,
                isFocused: $inputDraft.isFocused,
                focusRequestID: inputDraft.focusRequestID,
                focusDelay: 0,
                placeholder: AppLocalizations.string("input.placeholder", defaultValue: "Type a message..."),
                maxVisibleLineCount: 4,
                fillsAvailableHeight: false,
                trailingAccessoryInset: 34,
                allowsFocus: true,
                onTextChanged: inputDraft.updateFromTextView,
                onMeasuredLineCountChanged: inputDraft.updateMeasuredLineCount,
                onPasteImageProviders: onPasteImageProviders
            )
            .font(.body)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if inputDraft.showsExpandedInputButton {
                Button {
                    onExpandInput()
                } label: {
                    expandInputIcon
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.expandInput", defaultValue: "Expand input"))
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandInputIcon: some View {
        ZStack {
            Image(systemName: "arrow.up.left")
                .offset(x: -3, y: -3)
            Image(systemName: "arrow.down.right")
                .offset(x: 3, y: 3)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.primary)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText || hasPendingAttachments
    }

    private var sendControlBackground: Color {
        !canSendMessage && !isGenerating
            ? inputGlassTint
            : Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.11)
    }

    private var cancelControlBackground: Color {
        Color.red.opacity(colorScheme == .dark ? 0.18 : 0.09)
    }

    private var speechControlBackground: Color {
        isSpeechRecording
            ? Color.red.opacity(colorScheme == .dark ? 0.22 : 0.12)
            : inputGlassTint
    }

    private var speechInputControl: some View {
        Button {
            onToggleSpeechInput()
        } label: {
            controlGlassIcon(
                systemName: isSpeechRecording ? "mic.fill" : "mic",
                size: 18,
                weight: .semibold,
                frame: 40,
                tint: speechControlBackground,
                foreground: isSpeechRecording ? .red : .primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeechRecording
            ? AppLocalizations.string("accessibility.stopSpeechInput", defaultValue: "Stop speech input")
            : AppLocalizations.string("accessibility.startSpeechInput", defaultValue: "Start speech input"))
    }

    @ViewBuilder
    private var inputActionControl: some View {
        if isEditingMessage {
            HStack(spacing: 8) {
                Button {
                    onCancelEditingMessage()
                } label: {
                    controlGlassIcon(
                        systemName: "xmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: cancelControlBackground,
                        foreground: .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.cancelEdit", defaultValue: "Cancel edit"))

                Menu {
                    Button("仅修改") {
                        onSaveEditingMessageOnly()
                    }

                    Button("修改并发送") {
                        onSaveEditingMessageAndRegenerate()
                    }
                } label: {
                    controlGlassIcon(
                        systemName: "checkmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: sendControlBackground
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
            }
        } else {
            Button {
                if isGenerating {
                    onStopGenerating()
                } else {
                    onSendMessage()
                }
            } label: {
                controlGlassIcon(
                    systemName: isGenerating ? "stop.fill" : "paperplane.fill",
                    size: 19,
                    weight: .semibold,
                    frame: 48,
                    tint: sendControlBackground
                )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSendMessage)
        }
    }

    private func controlGlassBackground(_ tint: Color) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(tint))
            .overlay(
                Circle()
                    .stroke(controlGlassHighlight, lineWidth: 1)
            )
    }

    private func controlGlassIcon(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight,
        frame: CGFloat,
        tint: Color,
        foreground: Color = .primary
    ) -> some View {
        ZStack {
            controlGlassBackground(tint)

            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(foreground)
        }
        .frame(width: frame, height: frame)
    }
}
