import Foundation
import SwiftUI

struct ExpandedChatInputView: View {
    @ObservedObject var inputDraft: ChatInputDraft
    @Environment(\.colorScheme) private var colorScheme
    @State private var textViewIsFocused = false
    @State private var focusRequestID = 0

    let isGenerating: Bool
    let isEditingMessage: Bool
    let isSpeechRecording: Bool
    let hasPendingAttachments: Bool
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onDismiss: () -> Void
    let onToggleSpeechInput: () -> Void
    let onStopGenerating: () -> Void
    let onSendMessage: () -> Void
    let onCancelEditingMessage: () -> Void
    let onSaveEditingMessageOnly: () -> Void
    let onSaveEditingMessageAndRegenerate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.collapseInput", defaultValue: "Collapse input"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            GeometryReader { geometry in
                ImagePastingTextView(
                    text: inputDraft.text,
                    textRevision: inputDraft.textRevision,
                    isFocused: $textViewIsFocused,
                    focusRequestID: focusRequestID,
                    focusDelay: 0,
                    placeholder: AppLocalizations.string("input.placeholder", defaultValue: "Type a message..."),
                    maxVisibleLineCount: 200,
                    fillsAvailableHeight: true,
                    trailingAccessoryInset: 0,
                    allowsFocus: true,
                    onTextChanged: inputDraft.updateFromExpandedTextView,
                    onMeasuredLineCountChanged: { _ in },
                    onPasteImageProviders: onPasteImageProviders
                )
                .font(.body)
                .foregroundStyle(Color.primary)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                speechInputControl

                Spacer(minLength: 0)

                inputActionControl
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                textViewIsFocused = true
                focusRequestID += 1
            }
        }
        .onDisappear {
            textViewIsFocused = false
            focusRequestID += 1
        }
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText || hasPendingAttachments
    }

    private var activeControlTint: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
    }

    private var quietControlTint: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    private var cancelControlTint: Color {
        Color.red.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }

    private var speechInputControl: some View {
        Button {
            onToggleSpeechInput()
        } label: {
            expandedControlIcon(
                systemName: isSpeechRecording ? "mic.fill" : "mic",
                foreground: isSpeechRecording ? .red : .primary,
                tint: isSpeechRecording ? cancelControlTint : quietControlTint
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
            HStack(spacing: 10) {
                Button {
                    onCancelEditingMessage()
                } label: {
                    expandedControlIcon(
                        systemName: "xmark",
                        foreground: .red,
                        tint: cancelControlTint
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
                    expandedControlIcon(
                        systemName: "checkmark",
                        tint: canSendMessage ? activeControlTint : quietControlTint
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
                .accessibilityLabel(AppLocalizations.string("accessibility.saveEdit", defaultValue: "Save edit"))
            }
        } else {
            Button {
                if isGenerating {
                    onStopGenerating()
                } else {
                    onSendMessage()
                }
            } label: {
                expandedControlIcon(
                    systemName: isGenerating ? "stop.fill" : "paperplane.fill",
                    tint: isGenerating || canSendMessage ? activeControlTint : quietControlTint
                )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSendMessage)
            .accessibilityLabel(isGenerating
                ? AppLocalizations.string("accessibility.stopGenerating", defaultValue: "Stop generating")
                : AppLocalizations.string("accessibility.sendMessage", defaultValue: "Send message"))
        }
    }

    private func expandedControlIcon(
        systemName: String,
        foreground: Color = .primary,
        tint: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(tint))

            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .frame(width: 48, height: 48)
    }
}
